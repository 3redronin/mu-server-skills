# Application contract tests

Read this reference for ordinary endpoint, routing, error, limit, header, redirect, and packaged-process tests.

## Build a real-server fixture

Start the same builder/handler graph used by the application, with only environment-specific collaborators replaced. Prefer a factory that accepts dependencies and returns a configured builder or started server; avoid maintaining a second, test-only route graph.

For in-process tests:

- use `MuServerBuilder.httpServer()` or explicit `withHttpPort(0)` and bind to `127.0.0.1`;
- start inside setup and save `server.uri()` only after `start()` succeeds;
- construct targets with `server.uri().resolve(...)`, preserving raw encoding where that is the contract;
- use per-test latches, counters, executors, files, and directories;
- close client response bodies before teardown, then stop the server in an after hook or `finally`;
- if setup creates several resources, unwind already-created resources when a later step fails.

A shared server can shorten a large suite, but it makes state leakage and parallel order dependence easier. Use one only when startup cost warrants it, reset all application state between tests, and allocate it once per independently runnable test class or fixture.

## Assert what callers observe

For every changed route, choose the relevant checks rather than asserting only a happy-path body:

- exact method and target, including query/path encoding and a non-match;
- status and reason-independent semantics;
- content type and charset where meaningful;
- repeated header values with `allValues`/equivalent, preserving multiplicity and order only when the contract promises order;
- body bytes, including empty, non-ASCII, binary, and partial-buffer boundaries;
- `HEAD` status/headers and zero response-body bytes;
- redirect status and absolute or relative `Location`, with client redirect following disabled;
- missing, repeated, malformed, oversized, and wrong-content-type request inputs;
- handler order, guards, fall-through, the default `404`, and pre- versus post-commit errors;
- request-body and header limits at, below, and above the configured boundary;
- externally visible cleanup or side effects after success, rejection, and disconnect.

Read a body through a fully consuming handler such as `BodyHandlers.ofByteArray()`, or close an `InputStream` body with try-with-resources. For clients whose response object owns the body, close that object. Do this on error assertions too.

High-level clients may merge repeated headers, follow redirects, retry failed requests, decompress bodies, supply `Host`, or reject malformed inputs before the server sees them. Configure those behaviors explicitly and use a raw test only when the behavior under test cannot otherwise reach Mu Server.

## Test errors without coupling to implementation text

Assert the application's promised status, content type, stable headers, and safe body fields. Mu Server's generated HTML and error IDs are implementation presentation unless the application deliberately exposes them as its contract. For a late exception after response commitment, assert the observable incomplete/failing stream rather than expecting the original status and headers to be replaced.

Protocol-level rejections such as oversized headers can happen before a `MuRequest` exists. They reach `RequestRejectListener`, not `ResponseCompleteListener`; test the listener appropriate to the configured boundary.

## Test packaged startup separately

A packaged-process smoke test should build the real artifact, launch it with production-style configuration on an OS-assigned or harness-reserved port, wait on an explicit readiness condition with a deadline, call a minimal set of public endpoints, and terminate it through the supported lifecycle. Capture logs and exit state on failure. Keep these slower tests separate from per-test integration tests so local iteration remains fast and CI can assign the required network/container capabilities explicitly.
