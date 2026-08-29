#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 PROJECT_DIR" >&2
    exit 2
fi

project_dir=$(cd "$1" && pwd)
source_dir="$project_dir/src/main/java"

[[ -f "$project_dir/pom.xml" ]] || { echo "FAIL: pom.xml is missing" >&2; exit 1; }
[[ -d "$source_dir" ]] || { echo "FAIL: src/main/java is missing" >&2; exit 1; }

rg -q '<maven.compiler.release>17</maven.compiler.release>' "$project_dir/pom.xml" || {
    echo "FAIL: Java 17 compiler release changed" >&2
    exit 1
}
[[ $(rg -c '<dependency>' "$project_dir/pom.xml") == 1 ]] || {
    echo "FAIL: expected exactly one direct dependency" >&2
    exit 1
}
[[ $(rg -c '<artifactId>mu-server</artifactId>' "$project_dir/pom.xml") == 1 ]] || {
    echo "FAIL: expected exactly one mu-server dependency" >&2
    exit 1
}
rg -q '<version>2.4.1</version>' "$project_dir/pom.xml" || {
    echo "FAIL: mu-server 2.4.1 was not preserved" >&2
    exit 1
}

[[ $( (rg -o 'static[[:space:]]+void[[:space:]]+main[[:space:]]*\(' "$source_dir" || true) | wc -l ) == 1 ]] || {
    echo "FAIL: expected one entry point" >&2
    exit 1
}
[[ $( (rg -o '\.start[[:space:]]*\(' "$source_dir" || true) | wc -l ) == 1 ]] || {
    echo "FAIL: expected one server start" >&2
    exit 1
}
rg -q 'withHttpPort[[:space:]]*\([[:space:]]*8189[[:space:]]*\)' "$source_dir" || {
    echo "FAIL: expected port 8189" >&2
    exit 1
}
rg -q 'withPath[[:space:]]*\([[:space:]]*"/ws"[[:space:]]*\)' "$source_dir" || {
    echo "FAIL: expected direct WebSocket path /ws" >&2
    exit 1
}
rg -q 'withMaxFramePayloadLength[[:space:]]*\([[:space:]]*16384[[:space:]]*\)' "$source_dir" || {
    echo "FAIL: expected a 16384-byte frame limit" >&2
    exit 1
}
if rg -q 'jakarta\.websocket|javax\.websocket|spring|jetty\.websocket|undertow|vertx' "$source_dir" "$project_dir/pom.xml"; then
    echo "FAIL: direct Mu WebSocket architecture was replaced or mixed with another framework" >&2
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
    mise x java@temurin-17 -- mvn -q clean package dependency:build-classpath \
        -Dmdep.outputFile="$temp_dir/classpath.txt"
)

runtime_classpath="$project_dir/target/classes:$(<"$temp_dir/classpath.txt")"
(
    cd "$temp_dir"
    exec mise x java@temurin-17 -- java -cp "$runtime_classpath" example.Main
) >"$temp_dir/server.log" 2>&1 &
server_pid=$!

base_url=http://127.0.0.1:8189
for _ in $(seq 1 60); do
    status=$(curl --noproxy '*' --silent --max-time 1 --output /dev/null --write-out '%{http_code}' \
        "$base_url/health" || true)
    [[ "$status" == 200 ]] && break
    if ! kill -0 "$server_pid" 2>/dev/null; then
        echo "FAIL: server exited during startup" >&2
        sed -n '1,200p' "$temp_dir/server.log" >&2
        exit 1
    fi
    sleep 0.25
done
[[ "${status:-000}" == 200 ]] || { echo "FAIL: server did not become ready" >&2; exit 1; }

[[ $(curl --noproxy '*' --silent --fail --max-time 5 "$base_url/health") == healthy ]] || {
    echo "FAIL: /health changed" >&2
    exit 1
}
[[ $(curl --noproxy '*' --silent --fail --max-time 5 "$base_url/ws") == 'websocket endpoint' ]] || {
    echo "FAIL: ordinary GET /ws did not fall through to its HTTP handler" >&2
    exit 1
}

probe_source=$(cd "$(dirname "$0")" && pwd)/WebSocketProbe.java
mise x java@temurin-17 -- javac -d "$temp_dir" "$probe_source"
mise x java@temurin-17 -- java -cp "$temp_dir" WebSocketProbe ws://127.0.0.1:8189/ws

echo "PASS: bounded-chat fixture compiled and its HTTP and WebSocket wire contracts passed"
