#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 PROJECT_DIR" >&2
    exit 2
}

[[ $# == 1 ]] || usage
project_dir=$(cd "$1" && pwd)
pom="$project_dir/pom.xml"
test_file="$project_dir/src/test/java/example/AppContractTest.java"

[[ -f "$pom" && -f "$test_file" ]] || {
    echo "FAIL: expected the application-contract-harness Maven fixture" >&2
    exit 1
}

rg -q '<maven.compiler.release>11</maven.compiler.release>' "$pom" || {
    echo "FAIL: expected Java 11" >&2
    exit 1
}
rg -q '<artifactId>mu-server</artifactId>' "$pom" || {
    echo "FAIL: expected the io.muserver:mu-server dependency" >&2
    exit 1
}
rg -q '<version>2\.4\.1</version>' "$pom" || {
    echo "FAIL: expected Mu Server 2.4.1 in the fixture" >&2
    exit 1
}
rg -q 'MuServerBuilder\.httpServer\(\)' "$test_file" || {
    echo "FAIL: expected an ephemeral HTTP server" >&2
    exit 1
}
rg -q 'withInterface\("127\.0\.0\.1"\)' "$test_file" || {
    echo "FAIL: expected an explicit loopback bind" >&2
    exit 1
}
if rg -q 'withHttpPort\([[:space:]]*[1-9][0-9]*[[:space:]]*\)' "$test_file"; then
    echo "FAIL: found a fixed non-zero test port" >&2
    exit 1
fi
rg -q 'server\.uri\(\)' "$test_file" || {
    echo "FAIL: expected requests to derive from the started server URI" >&2
    exit 1
}
rg -q 'HttpClient\.Redirect\.NEVER' "$test_file" || {
    echo "FAIL: redirect assertions require automatic following to be disabled" >&2
    exit 1
}
rg -q 'CountDownLatch' "$test_file" || {
    echo "FAIL: expected deadline-based response completion coordination" >&2
    exit 1
}
rg -q 'new Socket\(\)' "$test_file" || {
    echo "FAIL: expected a bounded raw HTTP/1 wire probe" >&2
    exit 1
}
if rg -q 'import scaffolding\.' "$project_dir/src"; then
    echo "FAIL: internal Mu Server source-test scaffolding was imported" >&2
    exit 1
fi

(
    cd "$project_dir"
    mise x java@temurin-11 -- mvn -q test
)

report="$project_dir/target/surefire-reports/TEST-example.AppContractTest.xml"
[[ -f "$report" ]] || {
    echo "FAIL: JUnit report was not produced" >&2
    exit 1
}
test_count=$(rg -o 'tests="[0-9]+"' "$report" | head -1 | tr -dc '0-9')
[[ -n "$test_count" && "$test_count" -ge 7 ]] || {
    echo "FAIL: expected at least the seven bundled contract tests to run" >&2
    exit 1
}
if ! rg -q 'failures="0"' "$report" || ! rg -q 'errors="0"' "$report"; then
    echo "FAIL: JUnit reported a failure or error" >&2
    exit 1
fi

echo "PASS: $test_count real-server HTTP contract tests passed on Java 11 and Mu Server 2.4.1"
