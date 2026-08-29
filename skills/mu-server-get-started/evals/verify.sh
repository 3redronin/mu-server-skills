#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 PROJECT_DIR BUILD_SYSTEM JAVA_VERSION PORT MAIN_CLASS HELLO_BODY MU_SERVER_VERSION [HEALTH_BODY]" >&2
    exit 2
}

[[ $# -ge 7 && $# -le 8 ]] || usage

project_dir=$(cd "$1" && pwd)
build_system=$2
java_version=$3
port=$4
main_class=$5
hello_body=$6
mu_server_version=$7
health_body=${8-}

if ! rg -q 'ResourceHandlerBuilder[[:space:]]*\.[[:space:]]*fileOrClasspath\([[:space:]]*"src/main/resources/web"[[:space:]]*,[[:space:]]*"/web"' "$project_dir/src/main/java" --multiline; then
    echo "FAIL: expected fileOrClasspath(\"src/main/resources/web\", \"/web\")" >&2
    exit 1
fi

if [[ ! -f "$project_dir/src/main/resources/web/index.html" ]]; then
    echo "FAIL: src/main/resources/web/index.html does not exist" >&2
    exit 1
fi

main_count=$(rg -o 'static void main\(' "$project_dir/src/main/java" | wc -l)
start_count=$(rg -o '\.start\(\)' "$project_dir/src/main/java" | wc -l)
[[ "$main_count" == "1" ]] || { echo "FAIL: expected exactly one application entry point" >&2; exit 1; }
[[ "$start_count" == "1" ]] || { echo "FAIL: expected exactly one server start" >&2; exit 1; }

policy_paths=("$project_dir/src/main")
for build_file in pom.xml build.gradle build.gradle.kts; do
    if [[ -f "$project_dir/$build_file" ]]; then
        policy_paths+=("$project_dir/$build_file")
    fi
done
if rg -q 'jakarta\.ws\.rs|javax\.ws\.rs|mu-server-rest|spring-boot|io\.undertow|org\.eclipse\.jetty|slf4j-simple|logback-classic|log4j-core' \
    "${policy_paths[@]}"; then
    echo "FAIL: found an unrequested REST or web-framework integration" >&2
    exit 1
fi

temp_dir=$(mktemp -d)
server_pid=
cleanup() {
    if [[ -n "$server_pid" ]]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    find "$temp_dir" -depth -delete
}
trap cleanup EXIT

case "$build_system" in
    maven)
        dependency_count=$(rg -c '<artifactId>mu-server</artifactId>' "$project_dir/pom.xml")
        [[ "$dependency_count" == "1" ]] || { echo "FAIL: expected exactly one mu-server dependency" >&2; exit 1; }
        rg -q "<maven.compiler.release>$java_version</maven.compiler.release>" "$project_dir/pom.xml" || {
            echo "FAIL: expected Maven compiler release $java_version" >&2
            exit 1
        }
        rg -q ">$mu_server_version<" "$project_dir/pom.xml" || {
            echo "FAIL: expected mu-server version $mu_server_version" >&2
            exit 1
        }
        (
            cd "$project_dir"
            mise x "java@temurin-$java_version" -- mvn -q -DskipTests package \
                dependency:build-classpath -Dmdep.outputFile="$temp_dir/classpath.txt"
        )
        runtime_classpath="$project_dir/target/classes:$(<"$temp_dir/classpath.txt")"
        (
            cd "$temp_dir"
            exec mise x "java@temurin-$java_version" -- java -cp "$runtime_classpath" "$main_class"
        ) >"$temp_dir/server.log" 2>&1 &
        server_pid=$!
        ;;
    gradle)
        if [[ -f "$project_dir/build.gradle.kts" ]]; then
            build_file="$project_dir/build.gradle.kts"
        elif [[ -f "$project_dir/build.gradle" ]]; then
            build_file="$project_dir/build.gradle"
        else
            echo "FAIL: no Gradle build file" >&2
            exit 1
        fi
        dependency_count=$( (rg -o 'io\.muserver:mu-server:' "$build_file" || true) | wc -l )
        [[ "$dependency_count" == "1" ]] || { echo "FAIL: expected exactly one mu-server dependency" >&2; exit 1; }
        rg -q "JavaLanguageVersion\.of\($java_version\)" "$build_file" || {
            echo "FAIL: expected Gradle Java toolchain $java_version" >&2
            exit 1
        }
        rg -q "io\.muserver:mu-server:$mu_server_version" "$build_file" || {
            echo "FAIL: expected mu-server version $mu_server_version" >&2
            exit 1
        }
        gradle_jvm_version=$java_version
        if (( gradle_jvm_version < 17 )); then
            gradle_jvm_version=17
        fi
        toolchain_home=$(mise where "java@temurin-$java_version")
        if mise where gradle@9.7.1 >/dev/null 2>&1; then
            (
                cd "$project_dir"
                mise x "java@temurin-$gradle_jvm_version" gradle@9.7.1 -- gradle --quiet \
                    -Dorg.gradle.java.installations.paths="$toolchain_home" installDist
            )
        elif [[ -x "$project_dir/gradlew" ]]; then
            (
                cd "$project_dir"
                mise x "java@temurin-$gradle_jvm_version" -- ./gradlew --quiet \
                    -Dorg.gradle.java.installations.paths="$toolchain_home" installDist
            )
        else
            echo "FAIL: no Gradle installation or wrapper" >&2
            exit 1
        fi
        launcher=$(find "$project_dir/build/install" -mindepth 3 -maxdepth 3 -type f ! -name '*.bat' -perm -u+x | head -n 1)
        [[ -n "$launcher" ]] || { echo "FAIL: Gradle application distribution has no launcher" >&2; exit 1; }
        (
            cd "$temp_dir"
            exec mise x "java@temurin-$java_version" -- "$launcher"
        ) >"$temp_dir/server.log" 2>&1 &
        server_pid=$!
        ;;
    *)
        usage
        ;;
esac

base_url="http://127.0.0.1:$port"
for _ in $(seq 1 60); do
    if curl --noproxy '*' --silent --fail --max-time 1 "$base_url/hello" >/dev/null 2>&1; then
        break
    fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
        echo "FAIL: server exited during startup" >&2
        sed -n '1,200p' "$temp_dir/server.log" >&2
        exit 1
    fi
    sleep 0.5
done

request_and_check() {
    local path=$1
    local expected_body=$2
    local headers="$temp_dir/headers"
    local body="$temp_dir/body"
    local status
    status=$(curl --noproxy '*' --silent --show-error --max-time 5 --dump-header "$headers" --output "$body" \
        --write-out '%{http_code}' "$base_url$path")
    [[ "$status" == "200" ]] || { echo "FAIL: GET $path returned $status" >&2; exit 1; }
    if [[ "$path" == "/" ]]; then
        if rg -qi '^location:' "$headers"; then
            echo "FAIL: GET / returned a Location header" >&2
            exit 1
        fi
        if ! cmp -s "$body" "$project_dir/src/main/resources/web/index.html"; then
            echo "FAIL: GET / did not return the packaged index.html bytes" >&2
            exit 1
        fi
    elif [[ "$(<"$body")" != "$expected_body" ]]; then
        echo "FAIL: GET $path body did not equal: $expected_body" >&2
        exit 1
    fi
}

request_and_check "/hello" "$hello_body"
request_and_check "/" ""
if [[ -n "$health_body" ]]; then
    request_and_check "/health" "$health_body"
fi

echo "PASS: $build_system app on port $port compiled and served direct and classpath-backed routes"
