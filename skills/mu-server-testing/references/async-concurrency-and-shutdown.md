# Async, concurrency, and shutdown tests

Read this reference for asynchronous handlers, streaming bodies, SSE, WebSockets, uploads, disconnects, cleanup, concurrency, and graceful shutdown.

## Coordinate observable phases

Use `CountDownLatch`, `CompletableFuture`, barriers, or the test framework's eventual assertion with explicit deadlines. Coordinate the event that matters—for example request accepted, first chunk written, client disconnected, response-complete listener called, file deleted, or producer stopped. A sleep can widen a race window for stress but is not proof that a phase occurred and should not be correctness synchronization.

The client receiving all response bytes can precede the server's `ResponseCompleteListener` or asynchronous cleanup. Await the server-side completion/cleanup signal before asserting it. Remember that `completedSuccessfully()` means the request was fully read and the response fully sent; a completely delivered HTTP `500` is transport-successful.

For asynchronous routes, verify every terminal path exactly once:

- normal completion after the last acknowledged read/write;
- producer, request-read, and response-write failure;
- client disconnect before and after response commitment;
- timeout and cancellation;
- executor, subscription, stream, temporary-file, and tracked-session cleanup.

## Apply real pressure

Use bodies larger than one buffer, a deliberately delayed reader/writer, and bounded queues. Assert exact bytes and order, including an empty input and final partial buffer. A slow-client test should demonstrate the application's in-flight/queued bound, not merely finish eventually.

For SSE and WebSockets, wait for open/message/close callbacks with deadlines, verify ordered frames/events and cleanup, and disconnect clients deliberately. For uploads, use per-test temporary directories, include malformed/truncated multipart or raw bodies as appropriate, and verify persistence or deletion after the exchange completes. Keep temporary roots unique and remove them in teardown even after failures.

Exercise concurrent requests against shared handler state and resource limits. Use enough overlap to reach the guarded phase deterministically, then release all waiters in `finally` so a failed assertion cannot strand handler threads.

## Test drain and stop

For graceful shutdown, block a known in-flight request on a latch, invoke `stop(duration, unit)` from another thread when necessary, verify the listener socket stops accepting new connections, then either release the request inside the deadline or deliberately exceed it. Put finite timeouts on the client, stop future, and latch waits.

Interpret the return value by major version:

- Mu Server 3 follows the public contract: `true` means clean shutdown; `false` means in-flight requests exceeded the timeout or shutdown failed.
- Mu Server 2.4.1 has a known reversed-result defect: a clean drain returns `false`, while a timeout with in-flight requests returns `true`.

Do not encode the 2.x inversion as desired application behavior. During an upgrade, make the expected value version-aware or update it with the dependency; keep the stronger observable assertions about completed/aborted requests and stopped listeners on both versions.

Applications with WebSocket sessions or external producers may need an application-level drain before `MuServer.stop`: stop admission, close sessions/subscriptions, await their cleanup with a deadline, then stop the HTTP server. Test that lifecycle in its real order.
