#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 CASE_ID PROJECT_DIR" >&2
    echo "Cases: new-maven-singleton, new-gradle-problem-details, adapt-gradle-kotlin-multiple-resources" >&2
    exit 2
}

[[ $# == 2 ]] || usage

case_id=$1
project_dir=$(cd "$2" && pwd)

case "$case_id" in
    new-maven-singleton)
        build_system=maven
        java_version=17
        port=8080
        mu_server_version=2.4.1
        ready_path=/hello/readiness
        ;;
    new-gradle-problem-details)
        build_system=gradle
        java_version=17
        port=9091
        mu_server_version=2.4.1
        ready_path=/validate
        ;;
    adapt-gradle-kotlin-multiple-resources)
        build_system=gradle
        java_version=11
        port=8182
        mu_server_version=2.4.0
        ready_path=/health
        ;;
    *)
        usage
        ;;
esac

source_dir="$project_dir/src/main/java"
[[ -d "$source_dir" ]] || { echo "FAIL: src/main/java does not exist" >&2; exit 1; }

main_count=$( (rg -o 'static[[:space:]]+void[[:space:]]+main[[:space:]]*\(' "$source_dir" || true) | wc -l )
start_count=$( (rg -o '\.start[[:space:]]*\(' "$source_dir" || true) | wc -l )
rest_handler_count=$( (rg --pcre2 -o '(?<![A-Za-z])(?:RestHandlerBuilder[[:space:]]*\.[[:space:]]*)?restHandler[[:space:]]*\(' "$source_dir" || true) | wc -l )
[[ "$main_count" == 1 ]] || { echo "FAIL: expected exactly one application entry point" >&2; exit 1; }
[[ "$start_count" == 1 ]] || { echo "FAIL: expected exactly one server start" >&2; exit 1; }
[[ "$rest_handler_count" == 1 ]] || { echo "FAIL: expected exactly one RestHandlerBuilder REST handler" >&2; exit 1; }

rg -q "withHttpPort[[:space:]]*\([[:space:]]*${port}[[:space:]]*\)" "$source_dir" || {
    echo "FAIL: expected explicit port $port" >&2
    exit 1
}
rg -q 'import[[:space:]]+jakarta\.ws\.rs\.' "$source_dir" || {
    echo "FAIL: expected jakarta.ws.rs annotations" >&2
    exit 1
}
if rg --pcre2 -q -U 'restHandler[[:space:]]*\([^)]*\.class' "$source_dir"; then
    echo "FAIL: resource classes were registered instead of application-created instances" >&2
    exit 1
fi

policy_paths=("$source_dir")
for build_file in pom.xml build.gradle build.gradle.kts; do
    [[ ! -f "$project_dir/$build_file" ]] || policy_paths+=("$project_dir/$build_file")
done
if rg -q 'javax\.ws\.rs|jakarta\.inject|javax\.inject|mu-server-rest|org\.glassfish\.jersey|resteasy|spring-boot|io\.quarkus|io\.micronaut|com\.google\.inject|jakarta\.ws\.rs:jakarta\.ws\.rs-api|<artifactId>jakarta\.ws\.rs-api</artifactId>' \
    "${policy_paths[@]}"; then
    echo "FAIL: found an unrequested REST API, DI container, or alternate framework dependency" >&2
    exit 1
fi
if rg -q '@Provider|fromApplication[[:space:]]*\(|SeBootstrap|jakarta\.ws\.rs\.core\.Application' "$source_dir"; then
    echo "FAIL: found provider discovery or a bootstrap API unavailable in mu-server 2.4.1" >&2
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
        [[ -f "$project_dir/pom.xml" ]] || { echo "FAIL: pom.xml does not exist" >&2; exit 1; }
        dependency_count=$( (rg -o '<dependency>' "$project_dir/pom.xml" || true) | wc -l )
        mu_dependency_count=$( (rg -o '<artifactId>mu-server</artifactId>' "$project_dir/pom.xml" || true) | wc -l )
        [[ "$dependency_count" == 1 && "$mu_dependency_count" == 1 ]] || {
            echo "FAIL: expected io.muserver:mu-server to be the only direct dependency" >&2
            exit 1
        }
        rg -q "<(maven\.compiler\.(release|source)|release)>$java_version</" "$project_dir/pom.xml" || {
            echo "FAIL: expected Maven Java version $java_version" >&2
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
        main_file=$(rg -l 'static[[:space:]]+void[[:space:]]+main[[:space:]]*\(' "$source_dir" | head -n 1)
        main_package=$(sed -n 's/^[[:space:]]*package[[:space:]]\+\([^;]*\);.*/\1/p' "$main_file" | head -n 1)
        main_class=$(basename "$main_file" .java)
        [[ -z "$main_package" ]] || main_class="$main_package.$main_class"
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
        mu_dependency_count=$( (rg -o 'io\.muserver:mu-server:' "$build_file" || true) | wc -l )
        runtime_dependency_count=$( (rg -o '^[[:space:]]*(implementation|runtimeOnly)[[:space:](]' "$build_file" || true) | wc -l )
        [[ "$mu_dependency_count" == 1 && "$runtime_dependency_count" == 1 ]] || {
            echo "FAIL: expected io.muserver:mu-server to be the only runtime dependency" >&2
            exit 1
        }
        rg -q "JavaLanguageVersion\.of\($java_version\)|JavaVersion\.VERSION_$java_version|sourceCompatibility[[:space:]=]+['\"]?$java_version" "$build_file" || {
            echo "FAIL: expected Gradle Java version $java_version" >&2
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
esac

base_url="http://127.0.0.1:$port"
for _ in $(seq 1 60); do
    status=$(curl --noproxy '*' --silent --max-time 1 --output /dev/null --write-out '%{http_code}' "$base_url$ready_path" || true)
    [[ "$status" == 000 ]] || break
    if ! kill -0 "$server_pid" 2>/dev/null; then
        echo "FAIL: server exited during startup" >&2
        sed -n '1,200p' "$temp_dir/server.log" >&2
        exit 1
    fi
    sleep 0.5
done
[[ "${status:-000}" != 000 ]] || { echo "FAIL: server did not become reachable" >&2; exit 1; }

request() {
    local label=$1
    local path=$2
    local expected_status=$3
    local expected_type=$4
    local expected_body=$5
    local headers="$temp_dir/$label.headers"
    local body="$temp_dir/$label.body"
    local actual_status
    actual_status=$(curl --noproxy '*' --silent --show-error --max-time 5 \
        --dump-header "$headers" --output "$body" --write-out '%{http_code}' "$base_url$path")
    [[ "$actual_status" == "$expected_status" ]] || {
        echo "FAIL: GET $path returned $actual_status instead of $expected_status" >&2
        exit 1
    }
    rg -qi "^content-type:[[:space:]]*$expected_type([;[:space:]]|$)" "$headers" || {
        echo "FAIL: GET $path did not return Content-Type $expected_type" >&2
        exit 1
    }
    if [[ -n "$expected_body" && "$(<"$body")" != "$expected_body" ]]; then
        echo "FAIL: GET $path body did not equal: $expected_body" >&2
        exit 1
    fi
}

parallel_same_body() {
    local path=$1
    local expected_body=$2
    local pids=()
    for i in $(seq 1 12); do
        curl --noproxy '*' --silent --show-error --fail --max-time 5 "$base_url$path" \
            >"$temp_dir/parallel-$i.body" &
        pids+=("$!")
    done
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    for i in $(seq 1 12); do
        [[ "$(<"$temp_dir/parallel-$i.body")" == "$expected_body" ]] || {
            echo "FAIL: concurrent GET $path returned an unexpected body" >&2
            exit 1
        }
    done
}

case "$case_id" in
    new-maven-singleton)
        [[ $( (rg -o 'new[[:space:]]+[A-Za-z][A-Za-z0-9]*Service[[:space:]]*\(' "$source_dir" || true) | wc -l ) == 1 ]] || {
            echo "FAIL: expected one application-created service" >&2; exit 1;
        }
        [[ $( (rg -o 'new[[:space:]]+[A-Za-z][A-Za-z0-9]*Resource[[:space:]]*\(' "$source_dir" || true) | wc -l ) == 1 ]] || {
            echo "FAIL: expected one application-created resource" >&2; exit 1;
        }
        rg --pcre2 -q '[A-Za-z][A-Za-z0-9]*Resource[[:space:]]*\([^)]*[A-Za-z][A-Za-z0-9]*Service' "$source_dir" || {
            echo "FAIL: the service was not constructor-wired into the resource" >&2; exit 1;
        }
        rg -q '@PathParam[[:space:]]*\([[:space:]]*"name"' "$source_dir" || {
            echo "FAIL: expected @PathParam method binding" >&2; exit 1;
        }
        request hello /hello/Daniel 200 text/plain "Hello, Daniel"
        parallel_same_body /hello/Daniel "Hello, Daniel"
        ;;
    new-gradle-problem-details)
        if ! rg -q 'ProblemDetailsExceptionMapperBuilder' "$source_dir" || \
            ! rg -q 'problemDetailsExceptionMapper[[:space:]]*\(' "$source_dir"; then
            echo "FAIL: expected ProblemDetailsExceptionMapperBuilder" >&2; exit 1;
        fi
        rg --pcre2 -q -U 'addExceptionMapper[[:space:]]*\([[:space:]]*Throwable\.class[[:space:]]*,' "$source_dir" || {
            echo "FAIL: expected explicit Throwable exception mapper registration" >&2; exit 1;
        }
        request validate /validate 422 'application/problem\+json' ""
        jq -e '.status == 422 and .title == "Validation Failed" and .detail == "Name is required"' \
            "$temp_dir/validate.body" >/dev/null || {
            echo "FAIL: /validate did not return the requested RFC 9457 fields" >&2; exit 1;
        }
        ;;
    adapt-gradle-kotlin-multiple-resources)
        rg -q 'addHandler[[:space:]]*\([[:space:]]*Method\.GET[[:space:]]*,[[:space:]]*"/health"' "$source_dir" || {
            echo "FAIL: existing direct /health handler was not preserved" >&2; exit 1;
        }
        wired_resource_count=$( (rg --pcre2 -o 'new[[:space:]]+[A-Za-z][A-Za-z0-9]*Resource[[:space:]]*\([[:space:]]*applicationService[[:space:]]*\)' "$source_dir" || true) | wc -l )
        [[ "$wired_resource_count" == 2 ]] || {
            echo "FAIL: expected two resource instances constructor-wired with the existing applicationService" >&2; exit 1;
        }
        request health /health 200 text/plain healthy
        request greeting /api/greet/Daniel 200 text/plain "Hello, Daniel"
        pids=()
        for i in $(seq 1 20); do
            curl --noproxy '*' --silent --show-error --fail --max-time 5 "$base_url/api/count" \
                >"$temp_dir/count-$i.body" &
            pids+=("$!")
        done
        for pid in "${pids[@]}"; do
            wait "$pid"
        done
        for i in $(seq 1 20); do
            rg -q '^[0-9]+$' "$temp_dir/count-$i.body" || {
                echo "FAIL: concurrent /api/count response was not an integer" >&2; exit 1;
            }
            printf '%s\n' "$(<"$temp_dir/count-$i.body")"
        done | sort -n >"$temp_dir/actual-counts"
        seq 1 20 >"$temp_dir/expected-counts"
        cmp -s "$temp_dir/actual-counts" "$temp_dir/expected-counts" || {
            echo "FAIL: concurrent /api/count responses were not the unique integers 1 through 20" >&2; exit 1;
        }
        ;;
esac

echo "PASS: $case_id compiled and satisfied its registration, dependency, and HTTP contracts"
