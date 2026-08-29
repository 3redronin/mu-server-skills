#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 PROJECT_DIR" >&2
    exit 2
fi

project_dir=$(cd "$1" && pwd)

rg -q '<maven.compiler.release>17</maven.compiler.release>' "$project_dir/pom.xml" || {
    echo "FAIL: Java 17 compiler release changed" >&2
    exit 1
}
[[ $(rg -c '<artifactId>mu-server</artifactId>' "$project_dir/pom.xml") == 1 ]] || {
    echo "FAIL: expected one mu-server dependency" >&2
    exit 1
}
[[ $(rg -c '<artifactId>murp</artifactId>' "$project_dir/pom.xml") == 1 ]] || {
    echo "FAIL: expected one murp dependency" >&2
    exit 1
}
rg -q '<version>2.4.1</version>' "$project_dir/pom.xml" || {
    echo "FAIL: mu-server 2.4.1 was not preserved" >&2
    exit 1
}
rg -q '<version>1.2.2</version>' "$project_dir/pom.xml" || {
    echo "FAIL: expected Murp 1.2.2" >&2
    exit 1
}
if rg -q 'spring|jersey|resteasy|slf4j-simple|logback-classic|log4j-core' "$project_dir/pom.xml"; then
    echo "FAIL: found an unrelated framework or logging implementation" >&2
    exit 1
fi

temp_dir=$(mktemp -d)
target_pid=
proxy_pid=
reset_target_pid=
cleanup() {
    if [[ -n "$proxy_pid" ]]; then
        kill "$proxy_pid" 2>/dev/null || true
        wait "$proxy_pid" 2>/dev/null || true
    fi
    if [[ -n "$target_pid" ]]; then
        kill "$target_pid" 2>/dev/null || true
        wait "$target_pid" 2>/dev/null || true
    fi
    if [[ -n "$reset_target_pid" ]]; then
        kill "$reset_target_pid" 2>/dev/null || true
        wait "$reset_target_pid" 2>/dev/null || true
    fi
    find "$temp_dir" -depth -delete
}
trap cleanup EXIT

(
    cd "$project_dir"
    mise x java@temurin-17 -- mvn -q clean package dependency:build-classpath \
        -Dmdep.outputFile="$temp_dir/classpath.txt"
)

runtime_classpath="$project_dir/target/classes:$(<"$temp_dir/classpath.txt")"
(
    cd "$temp_dir"
    exec mise x java@temurin-17 -- java -cp "$runtime_classpath" example.TargetMain
) >"$temp_dir/target.log" 2>&1 &
target_pid=$!
(
    cd "$temp_dir"
    exec mise x java@temurin-17 -- java -cp "$runtime_classpath" example.Main
) >"$temp_dir/proxy.log" 2>&1 &
proxy_pid=$!

wait_for_url() {
    local url=$1
    local pid=$2
    local log_file=$3
    for _ in $(seq 1 60); do
        if curl --noproxy '*' --silent --fail --max-time 1 "$url" >/dev/null 2>&1; then
            return
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "FAIL: process exited during startup" >&2
            sed -n '1,200p' "$log_file" >&2
            exit 1
        fi
        sleep 0.25
    done
    echo "FAIL: timed out waiting for $url" >&2
    exit 1
}

wait_for_url http://127.0.0.1:9191/ready "$target_pid" "$temp_dir/target.log"
wait_for_url http://127.0.0.1:8187/health "$proxy_pid" "$temp_dir/proxy.log"

[[ $(curl --noproxy '*' --silent --fail http://127.0.0.1:8187/health) == healthy ]] || {
    echo "FAIL: /health changed" >&2
    exit 1
}

outside_status=$(curl --noproxy '*' --silent --output /dev/null --write-out '%{http_code}' \
    http://127.0.0.1:8187/outside)
[[ "$outside_status" == 404 ]] || {
    echo "FAIL: unmatched request returned $outside_status rather than 404" >&2
    exit 1
}

get_body=$(curl --noproxy '*' --path-as-is --silent --fail \
    -H 'Forwarded: for=203.0.113.9;proto=https;host=spoofed.example' \
    'http://127.0.0.1:8187/backend/a%20b?q=x%20y')
rg -q '^method=GET$' <<<"$get_body"
rg -q '^rawPath=/backend/a%20b$' <<<"$get_body"
rg -q '^rawQuery=q=x%20y$' <<<"$get_body"
rg -q '^host=127.0.0.1:9191$' <<<"$get_body"
rg -q '^via=\[HTTP/1.1 edge-proxy\]$' <<<"$get_body"
rg -q '^xForwardedFor=null$' <<<"$get_body"
if rg -q '203\.0\.113\.9|spoofed\.example' <<<"$get_body"; then
    echo "FAIL: untrusted Forwarded input reached the target" >&2
    exit 1
fi

post_body=$(curl --noproxy '*' --silent --fail -X POST --data-binary 'streamed payload' \
    http://127.0.0.1:8187/backend/upload)
rg -q '^method=POST$' <<<"$post_body"
rg -q '^body=streamed payload$' <<<"$post_body"

timeout_dir="$temp_dir/timeout"
mkdir "$timeout_dir"
timeout_status=$(curl --noproxy '*' --silent --max-time 5 --output "$timeout_dir/body" \
    --write-out '%{http_code}' http://127.0.0.1:8187/backend/slow)
[[ "$timeout_status" == 504 ]] || {
    echo "FAIL: slow target returned $timeout_status rather than 504" >&2
    exit 1
}
[[ $(<"$timeout_dir/body") == '504 Gateway Timeout' ]] || {
    echo "FAIL: unexpected 504 body" >&2
    exit 1
}

kill "$target_pid"
wait "$target_pid" 2>/dev/null || true
target_pid=
(
    cd "$temp_dir"
    exec mise x java@temurin-17 -- java -cp "$runtime_classpath" example.ResetTargetMain
) >"$temp_dir/reset-target.log" 2>&1 &
reset_target_pid=$!
sleep 0.5
if ! kill -0 "$reset_target_pid" 2>/dev/null; then
    echo "FAIL: reset target exited before the failure check" >&2
    sed -n '1,200p' "$temp_dir/reset-target.log" >&2
    exit 1
fi
failure_status=$(curl --noproxy '*' --silent --max-time 5 --output "$temp_dir/failure-body" \
    --write-out '%{http_code}' http://127.0.0.1:8187/backend/unavailable)
[[ "$failure_status" == 502 ]] || {
    echo "FAIL: target transport failure returned $failure_status rather than 502" >&2
    exit 1
}
[[ $(<"$temp_dir/failure-body") == '502 Bad Gateway' ]] || {
    echo "FAIL: unexpected 502 body" >&2
    exit 1
}
kill "$reset_target_pid" 2>/dev/null || true
wait "$reset_target_pid" 2>/dev/null || true
reset_target_pid=

echo "PASS: selective Murp proxy preserved data and enforced routing, headers, timeout, and failure semantics"
