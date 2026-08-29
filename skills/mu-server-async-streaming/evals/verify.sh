#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 PROJECT_DIR" >&2
    exit 2
}

[[ $# == 1 ]] || usage
project_dir=$(cd "$1" && pwd)
source_dir="$project_dir/src/main/java"
main_file="$source_dir/example/Main.java"

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
rg -q '<version>2\.4\.1</version>' "$project_dir/pom.xml" || {
    echo "FAIL: expected mu-server 2.4.1 to be preserved" >&2
    exit 1
}
rg -q 'withHttpPort[[:space:]]*\([[:space:]]*8184[[:space:]]*\)' "$source_dir" || {
    echo "FAIL: expected port 8184" >&2
    exit 1
}
[[ $( (rg --pcre2 -o '\.start\s*\(\s*\)' "$source_dir" || true) | wc -l ) == 1 ]] || {
    echo "FAIL: expected exactly one server start" >&2
    exit 1
}

rg --pcre2 -q -U 'handle[[:space:]]*\.[[:space:]]*write[[:space:]]*\([[:space:]]*buffer[[:space:]]*,[[:space:]]*doneCallback[[:space:]]*\)' "$main_file" || {
    echo "FAIL: /mirror must keep request-buffer demand outstanding until the response write completes" >&2
    exit 1
}
if rg -q 'response[[:space:]]*\.[[:space:]]*(writer|outputStream|sendChunk)[[:space:]]*\(' "$main_file"; then
    echo "FAIL: found a blocking response-body API in the async fixture" >&2
    exit 1
fi
rg -q 'AsyncSsePublisher[[:space:]]*\.[[:space:]]*start' "$main_file" || {
    echo "FAIL: expected direct AsyncSsePublisher use" >&2
    exit 1
}
rg -q 'thenCompose[[:space:]]*\(' "$main_file" || {
    echo "FAIL: /events must serialize publisher operations from completion stages" >&2
    exit 1
}
if rg -q 'new[[:space:]]+Thread[[:space:]]*\(' "$main_file"; then
    echo "FAIL: a per-request thread was introduced" >&2
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

(
    cd "$project_dir"
    mise x java@temurin-11 -- mvn -q -DskipTests package \
        dependency:build-classpath -Dmdep.outputFile="$temp_dir/classpath.txt"
)
runtime_classpath="$project_dir/target/classes:$(<"$temp_dir/classpath.txt")"
(
    cd "$temp_dir"
    exec mise x java@temurin-11 -- java -cp "$runtime_classpath" example.Main
) >"$temp_dir/server.log" 2>&1 &
server_pid=$!

base_url=http://127.0.0.1:8184
for _ in $(seq 1 60); do
    status=$(curl --noproxy '*' --http1.1 --silent --max-time 1 --output /dev/null \
        --write-out '%{http_code}' "$base_url/health" || true)
    [[ "$status" != 000 ]] && break
    if ! kill -0 "$server_pid" 2>/dev/null; then
        echo "FAIL: server exited during startup" >&2
        sed -n '1,200p' "$temp_dir/server.log" >&2
        exit 1
    fi
    sleep 0.5
done
[[ "${status:-000}" == 200 ]] || { echo "FAIL: /health was not ready" >&2; exit 1; }
[[ "$(curl --noproxy '*' --http1.1 --silent --show-error --fail --max-time 5 "$base_url/health")" == healthy ]] || {
    echo "FAIL: /health body changed" >&2
    exit 1
}

dd if=/dev/urandom of="$temp_dir/input.bin" bs=65536 count=32 status=none
pids=()
for i in $(seq 1 4); do
    curl --noproxy '*' --http1.1 --silent --show-error --fail --max-time 30 \
        --header 'Content-Type: application/octet-stream' --data-binary @"$temp_dir/input.bin" \
        "$base_url/mirror" >"$temp_dir/mirror-$i.bin" &
    pids+=("$!")
done
for pid in "${pids[@]}"; do
    wait "$pid"
done
for i in $(seq 1 4); do
    cmp -s "$temp_dir/input.bin" "$temp_dir/mirror-$i.bin" || {
        echo "FAIL: /mirror response $i was not byte-for-byte identical" >&2
        exit 1
    }
done

curl --noproxy '*' --http1.1 --silent --show-error --max-time 10 --no-buffer \
    --dump-header "$temp_dir/events.headers" --output "$temp_dir/events.body" "$base_url/events"
rg -qi '^HTTP/1\.[01][[:space:]]+200([[:space:]]|$)' "$temp_dir/events.headers" || {
    echo "FAIL: /events did not return 200" >&2
    exit 1
}
rg -qi '^content-type:[[:space:]]*text/event-stream([;[:space:]]|$)' "$temp_dir/events.headers" || {
    echo "FAIL: /events did not return text/event-stream" >&2
    exit 1
}
rg -qi '^cache-control:.*no-cache.*no-transform' "$temp_dir/events.headers" || {
    echo "FAIL: /events did not disable caching and transformation" >&2
    exit 1
}
printf ':ready\n\nretry: 2000\nid: 1\nevent: tick\ndata: value-1\n\nid: 2\nevent: tick\ndata: value-2\n\nid: 3\nevent: tick\ndata: value-3\n\n' \
    >"$temp_dir/events.expected"
cmp -s "$temp_dir/events.expected" "$temp_dir/events.body" || {
    echo "FAIL: /events bytes were not the expected ordered SSE stream" >&2
    sed -n '1,120l' "$temp_dir/events.body" >&2
    exit 1
}

echo "PASS: fixture compiled; /health, parallel binary mirror, and serialized SSE contracts passed"
