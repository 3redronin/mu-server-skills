---
name: mu-server-testing
description: >-
  Use when creating, reviewing, or debugging integration and black-box tests for applications built on Mu Server, including ephemeral real-server fixtures, observable HTTP contracts, raw HTTP/1 wire cases, HTTPS and HTTP/2, async or streaming lifecycle, disconnects, concurrency, cleanup, and graceful shutdown. Applies to application test suites and packaged-service smoke tests; Mu Server library implementation and TCK work follows the library repository's own engineering workflow.
license: MIT
---

# Test Mu Server applications

Preserve the project's test framework, HTTP client, Java level, Mu Server dependency, and build commands unless the user asks to change them. Treat current `io.muserver:mu-server` master as released Mu Server 3; the historical `io.muserver:mu3` artifact is unrelated. For a 2.x suite or an upgrade, read [version-sensitive contracts](references/version-differences.md).

## Start at the public boundary

Identify the application contract being changed: method and target, status, repeated headers, exact body bytes, redirect policy, failure response, body limits, completion/cleanup, and supported protocols. Inspect the production builder and handler order before creating the fixture. Prefer real network requests to a real `MuServer`; reserve direct unit tests for application code that is genuinely independent of HTTP.

Create an isolated server per test or fixture:

```java
MuServer server = MuServerBuilder.httpServer() // HTTP on port 0
    .withInterface("127.0.0.1")
    .addHandler(applicationHandler)
    .start();

try {
    URI endpoint = server.uri().resolve("/health");
    // Exercise endpoint through the project's HTTP client.
} finally {
    server.stop();
}
```

`httpServer()` already selects a system-assigned port. Bind to loopback for tests, and derive every request URI from the started server's `uri()`, `httpUri()`, or `httpsUri()` rather than predicting the port. Give every test its own mutable state and temporary directory so concurrent test execution cannot collide. Always stop the server in `finally`, an after hook, or an equivalent resource owner, including after setup failures.

Read [application contract tests](references/application-contract-tests.md) when adding ordinary endpoint, routing, error, body-limit, redirect, header, or packaged-process coverage. A runnable Java 11/JUnit fixture is in [evals/files/application-contract-harness](evals/files/application-contract-harness).

## Use supported test dependencies

There is no supported public Mu Server test-helper artifact. `ServerUtils`, `ClientUtils`, `MuAssert`, `RawClient`, and other classes under Mu Server's `src/test/java/scaffolding` are internal source-test conveniences, not application APIs. Their package is absent from `io.muserver:mu-server`; some also change global TLS/logging/leak-detection state. Use them as implementation examples only, without importing them or copying them wholesale.

Reuse the application's current test framework and HTTP client. Java 11's `java.net.http.HttpClient` is a dependency-free default when the project has no test client. Keep OkHttp, Jetty, WebSocket clients, or assertion libraries in test scope. Configure finite connect/read/operation deadlines and disable automatic redirects when asserting redirect status and `Location`.

Fully consume response bodies and close body streams or client response objects on every path. This matters for connection reuse, completion listeners, shutdown, and leak-free parallel tests. Assert repeated headers through the client's all-values API rather than a comma-joined convenience accessor.

## Escalate to protocol-specific fixtures only when needed

Use a normal HTTP client for statuses, headers, bodies, redirects, HEAD, and ordinary failures. Read [wire, TLS, and HTTP/2 tests](references/wire-tls-http2.md) when a high-level client would normalize or refuse the input, or when the deployed contract includes TLS, ALPN, HTTP/2, or client certificates.

Read [async, concurrency, and shutdown tests](references/async-concurrency-and-shutdown.md) for `handleAsync`, SSE, WebSockets, streaming uploads/downloads, delayed readers, disconnects, response-complete listeners, resource cleanup, bounded graceful shutdown, or race reports.

## Keep layers intentional

Use fast per-test servers for application contract coverage. Add a smaller packaged-process or container smoke layer when startup configuration, classpath packaging, signal handling, reverse proxies, container networking, or the deployed TLS boundary is itself part of the contract. Let the operating system assign ports in both layers unless an external harness requires a fixed port.

Keep protocol conformance claims proportionate to the test. An application test can prove its observed response and interoperability case; it does not replace Mu Server's own RFC, HTTP/2, Jakarta REST TCK, or implementation test suite.

## Verify and report

Run the project's focused tests, then its documented broader build where practical. Check that failures leave no server process, executor, open body, socket, temporary directory, or tracked session behind. For sensitive changes, repeat relevant tests in parallel and on each supported protocol.

Report the Mu Server major/version, Java version, client and redirect policy, actual bound URI strategy, observable contracts tested, raw/TLS/HTTP versions exercised, concurrency or disconnect technique, completion/cleanup evidence, shutdown result interpretation, and commands run. Call out any network boundary or timing condition that the local environment could not reproduce.
