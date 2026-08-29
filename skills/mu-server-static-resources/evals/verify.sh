#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 PROJECT_DIR" >&2
    exit 2
}

[[ $# == 1 ]] || usage
project_dir=$(cd "$1" && pwd)
main_file="$project_dir/src/main/java/example/Main.java"

[[ -f "$project_dir/pom.xml" && -f "$main_file" ]] || {
    echo "FAIL: expected the Maven fixture with example.Main" >&2
    exit 1
}

rg -q '<maven.compiler.release>11</maven.compiler.release>' "$project_dir/pom.xml" || {
    echo "FAIL: expected Java 11" >&2
    exit 1
}
[[ $( (rg -o '<artifactId>mu-server</artifactId>' "$project_dir/pom.xml" || true) | wc -l ) == 1 ]] || {
    echo "FAIL: expected exactly one mu-server dependency" >&2
    exit 1
}
rg -q '<mu-server.version>2\.4\.1</mu-server.version>|<version>2\.4\.1</version>' "$project_dir/pom.xml" || {
    echo "FAIL: expected mu-server 2.4.1 to be preserved" >&2
    exit 1
}
rg -q 'withHttpPort[[:space:]]*\([[:space:]]*8192[[:space:]]*\)' "$project_dir/src/main/java" || {
    echo "FAIL: expected port 8192" >&2
    exit 1
}
[[ $( (rg --pcre2 -o '\.start\s*\(\s*\)' "$project_dir/src/main/java" || true) | wc -l ) == 1 ]] || {
    echo "FAIL: expected exactly one server start" >&2
    exit 1
}

temp_dir=$(mktemp -d)
server_pid=
target_existed=false
[[ -d "$project_dir/target" ]] && target_existed=true
cleanup_server() {
    if [[ -n "$server_pid" ]]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
        server_pid=
    fi
}
cleanup() {
    cleanup_server
    if [[ "$target_existed" == false && -d "$project_dir/target" ]]; then
        find "$project_dir/target" -depth -delete
    fi
    find "$temp_dir" -depth -delete
}
trap cleanup EXIT

(
    cd "$project_dir"
    mise x java@temurin-11 -- mvn -q -DskipTests package \
        dependency:build-classpath -Dmdep.outputFile="$temp_dir/classpath.txt"
)
runtime_classpath="$project_dir/target/classes:$(<"$temp_dir/classpath.txt")"
base_url=http://127.0.0.1:8192

request() {
    local method=$1
    local path=$2
    local headers=$3
    local body=$4
    shift 4
    curl --noproxy '*' --http1.1 --silent --show-error --max-time 5 \
        --request "$method" --dump-header "$headers" --output "$body" \
        --write-out '%{http_code}' "$@" "$base_url$path"
}

header_value() {
    local name=$1
    local file=$2
    sed -n "s/^${name}:[[:space:]]*//Ip" "$file" | tail -n 1 | tr -d '\r'
}

assert_mode() {
    local mode=$1
    local run_dir=$2
    local mode_dir="$temp_dir/$mode"
    mkdir -p "$mode_dir"

    (
        cd "$run_dir"
        exec mise x java@temurin-11 -- java -cp "$runtime_classpath" example.Main
    ) >"$mode_dir/server.log" 2>&1 &
    server_pid=$!

    local status=000
    for _ in $(seq 1 60); do
        status=$(curl --noproxy '*' --http1.1 --silent --max-time 1 --output /dev/null \
            --write-out '%{http_code}' "$base_url/api/health" || true)
        [[ "$status" != 000 ]] && break
        if ! kill -0 "$server_pid" 2>/dev/null; then
            echo "FAIL: $mode server exited during startup" >&2
            sed -n '1,200p' "$mode_dir/server.log" >&2
            exit 1
        fi
        sleep 0.5
    done
    [[ "$status" == 200 ]] || { echo "FAIL: $mode /api/health was not ready" >&2; exit 1; }
    [[ "$(curl --noproxy '*' --http1.1 --silent --show-error --fail --max-time 5 "$base_url/api/health")" == healthy ]] || {
        echo "FAIL: $mode /api/health body changed" >&2
        exit 1
    }

    status=$(request GET /app "$mode_dir/bare.headers" "$mode_dir/bare.body")
    [[ "$status" == 302 ]] || { echo "FAIL: $mode GET /app returned $status, expected 302" >&2; exit 1; }
    [[ "$(header_value location "$mode_dir/bare.headers")" == */app/ ]] || {
        echo "FAIL: $mode GET /app Location did not end in /app/" >&2
        exit 1
    }

    status=$(request GET /app/ "$mode_dir/index.headers" "$mode_dir/index.body")
    [[ "$status" == 200 ]] || { echo "FAIL: $mode GET /app/ returned $status" >&2; exit 1; }
    cmp -s "$mode_dir/index.body" "$project_dir/src/main/resources/public/index.html" || {
        echo "FAIL: $mode GET /app/ did not return index.html bytes" >&2
        exit 1
    }
    rg -qi '^content-type:[[:space:]]*text/html' "$mode_dir/index.headers" || {
        echo "FAIL: $mode index did not have an HTML Content-Type" >&2
        exit 1
    }
    index_cache=$(header_value cache-control "$mode_dir/index.headers")
    [[ "$index_cache" != *immutable* ]] || { echo "FAIL: $mode index was marked immutable" >&2; exit 1; }
    [[ "$index_cache" == *no-cache* || "$index_cache" == *max-age=0* || "$index_cache" == *must-revalidate* ]] || {
        echo "FAIL: $mode index was not revalidatable: $index_cache" >&2
        exit 1
    }

    last_modified=$(header_value last-modified "$mode_dir/index.headers")
    [[ -n "$last_modified" ]] || { echo "FAIL: $mode index had no Last-Modified" >&2; exit 1; }
    status=$(request GET /app/ "$mode_dir/conditional.headers" "$mode_dir/conditional.body" \
        --header "If-Modified-Since: $last_modified")
    [[ "$status" == 304 ]] || { echo "FAIL: $mode conditional index returned $status" >&2; exit 1; }
    [[ ! -s "$mode_dir/conditional.body" ]] || { echo "FAIL: $mode 304 had a body" >&2; exit 1; }

    status=$(request GET /app/app.a1b2c3.js "$mode_dir/js.headers" "$mode_dir/js.body")
    [[ "$status" == 200 ]] || { echo "FAIL: $mode GET JavaScript returned $status" >&2; exit 1; }
    cmp -s "$mode_dir/js.body" "$project_dir/src/main/resources/public/app.a1b2c3.js" || {
        echo "FAIL: $mode JavaScript bytes differed" >&2
        exit 1
    }
    rg -qi '^content-type:[[:space:]]*application/javascript' "$mode_dir/js.headers" || {
        echo "FAIL: $mode JavaScript Content-Type was incorrect" >&2
        exit 1
    }
    js_cache=$(header_value cache-control "$mode_dir/js.headers")
    [[ "$js_cache" == *public* && "$js_cache" == *max-age=31536000* && "$js_cache" == *immutable* ]] || {
        echo "FAIL: $mode fingerprinted cache policy was incorrect: $js_cache" >&2
        exit 1
    }
    [[ "$(header_value x-content-type-options "$mode_dir/js.headers")" == nosniff ]] || {
        echo "FAIL: $mode JavaScript did not have nosniff" >&2
        exit 1
    }

    status=$(curl --noproxy '*' --http1.1 --silent --show-error --max-time 5 --head \
        --dump-header "$mode_dir/head.headers" --output /dev/null --write-out '%{http_code}' \
        "$base_url/app/app.a1b2c3.js")
    [[ "$status" == 200 ]] || { echo "FAIL: $mode HEAD JavaScript returned $status" >&2; exit 1; }
    [[ "$(header_value content-length "$mode_dir/head.headers")" == "$(wc -c < "$project_dir/src/main/resources/public/app.a1b2c3.js")" ]] || {
        echo "FAIL: $mode HEAD Content-Length differed from GET representation" >&2
        exit 1
    }

    status=$(request POST /app/index.html "$mode_dir/post.headers" "$mode_dir/post.body" --data '')
    [[ "$status" == 405 ]] || { echo "FAIL: $mode POST static file returned $status, expected 405" >&2; exit 1; }
    allow=$(header_value allow "$mode_dir/post.headers")
    [[ "$allow" == *GET* && "$allow" == *HEAD* ]] || {
        echo "FAIL: $mode 405 Allow did not include GET and HEAD: $allow" >&2
        exit 1
    }

    status=$(request GET /app/orders/42 "$mode_dir/spa.headers" "$mode_dir/spa.body")
    [[ "$status" == 200 ]] || { echo "FAIL: $mode SPA route returned $status" >&2; exit 1; }
    cmp -s "$mode_dir/spa.body" "$project_dir/src/main/resources/public/index.html" || {
        echo "FAIL: $mode SPA route did not return index.html" >&2
        exit 1
    }
    status=$(request GET /app/missing.a1b2c3.js "$mode_dir/missing-asset.headers" "$mode_dir/missing-asset.body")
    [[ "$status" == 404 ]] || { echo "FAIL: $mode missing asset returned $status" >&2; exit 1; }
    status=$(request GET /api/missing "$mode_dir/missing-api.headers" "$mode_dir/missing-api.body")
    [[ "$status" == 404 ]] || { echo "FAIL: $mode missing API returned $status" >&2; exit 1; }

    status=$(request GET /app/docs/ "$mode_dir/directory.headers" "$mode_dir/directory.body")
    [[ "$status" == 200 || "$status" == 404 ]] || {
        echo "FAIL: $mode directory policy returned unexpected $status" >&2
        exit 1
    }
    if rg -q 'internal-note\.txt' "$mode_dir/directory.body"; then
        echo "FAIL: $mode exposed a directory listing" >&2
        exit 1
    fi

    status=$(request GET /app/app.a1b2c3.js "$mode_dir/range.headers" "$mode_dir/range.body" \
        --header 'Range: bytes=0-9')
    [[ "$status" == 206 ]] || { echo "FAIL: $mode single range returned $status" >&2; exit 1; }
    cmp -s <(head -c 10 "$project_dir/src/main/resources/public/app.a1b2c3.js") "$mode_dir/range.body" || {
        echo "FAIL: $mode range bytes differed" >&2
        exit 1
    }
    rg -qi '^content-range:[[:space:]]*bytes 0-9/' "$mode_dir/range.headers" || {
        echo "FAIL: $mode range had no expected Content-Range" >&2
        exit 1
    }

    status=$(request GET /app/app.a1b2c3.js "$mode_dir/multi.headers" "$mode_dir/multi.body" \
        --header 'Range: bytes=0-1,4-5')
    [[ "$status" == 200 ]] || { echo "FAIL: $mode multiple range returned $status, expected 200" >&2; exit 1; }
    cmp -s "$mode_dir/multi.body" "$project_dir/src/main/resources/public/app.a1b2c3.js" || {
        echo "FAIL: $mode ignored multiple range did not return full body" >&2
        exit 1
    }

    cleanup_server
}

assert_mode filesystem "$project_dir"
assert_mode classpath "$temp_dir"

echo "PASS: file and packaged classpath modes satisfied method, cache, index, SPA, conditional, and range contracts"
