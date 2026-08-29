---
name: mu-server-websockets
description: >-
  Use when building, changing, reviewing, or troubleshooting direct server-side WebSocket endpoints in Mu Server 2.x or 3.x with WebSocketHandlerBuilder, MuWebSocketFactory, MuWebSocket, BaseWebSocket, or MuWebSocketSession. Covers upgrade routing and handshake policy, callback flow control and buffer ownership, fragmented messages, bounded asynchronous sends, ping and idle controls, close behavior, errors, cleanup, shutdown, and HTTP/1.1 deployment.
license: MIT
---

# Build direct WebSockets with Mu Server

Preserve the application's chosen direct Mu WebSocket architecture and its existing server, handler order, routes, ports, TLS, Java level, Mu version, executors, and shutdown model unless the request changes them.

## Inspect the contract

Inspect the build and bootstrap, handler chain and any `ContextHandler`, endpoint path and query policy, factory authentication and origin checks, requested subprotocols, message and frame limits, concurrency model, outbound producers, error policy, application-owned resources, active-session tracking, and tests.

Use the existing `io.muserver:mu-server` dependency; direct WebSockets need no additional Mu artifact. Preserve a selected Mu version. For a new dependency version, verify the current stable release from Maven Central and [the Mu Server download page](https://muserver.io/download); never derive a release number from a source-tree snapshot.

Create a new `BaseWebSocket` for each accepted upgrade. A `BaseWebSocket` holds one session and supplies Mu's ping, peer-close, timeout, protocol-error, and general-error defaults. Implement `MuWebSocket` directly only when the application deliberately owns all those callbacks.

## Route the upgrade deliberately

Register middleware that must inspect every request before the WebSocket handler. Register the WebSocket handler before a broad HTTP or static fallback that would consume the endpoint. `withPath` is an exact match against `request.relativePath()`; inside a `ContextHandler`, use a context-relative path. Without `withPath`, select on `request.uri()` or `relativePath()` in the factory.

Mu calls the factory only for a GET whose `Upgrade` header contains `websocket`. Returning `null` declines the request so later handlers run; ordinary HTTP requests also fall through. A returned socket commits this handler to attempting the upgrade, although the handshaker can still reject it. Inspect authentication, authorization, `Origin`, query parameters, TLS/client-certificate information, and requested subprotocols before returning it. Throw the application's normal HTTP exception when a candidate upgrade must be rejected with an HTTP response rather than falling through.

The factory's `responseHeaders` are added to the `101` response. For subprotocol negotiation, parse and validate every comma-separated token from every `Sec-WebSocket-Protocol` request-header occurrence, select exactly one value actually offered by the client, and set exactly one `Sec-WebSocket-Protocol` response value. Reject malformed or duplicate offers. Omit the response header when no protocol is selected; reject when the application requires one and no supported offer exists. Mu's handshaker does not enable WebSocket extensions.

For detailed handler, handshake, fragmentation, callback, sending, close, and error behavior, read [protocol and lifecycle](references/protocol-and-lifecycle.md) before implementing anything beyond a simple endpoint or when reviewing correctness.

## Respect demand and ownership

Socket event callbacks run on an NIO event-loop thread. Keep them nonblocking; offload blocking or CPU-heavy work to an application executor with bounded admission. Safely publish the session from `onConnect` before other threads use it.

Call every inbound `DoneCallback` exactly once. It is both demand control and, for the three-argument binary callback, the lifetime boundary for Mu-owned storage. Until it completes, Mu does not read the next frame. When sending an inbound buffer back unchanged, pass that callback as the send callback so the buffer stays valid through the asynchronous write.

Override the four-argument `onBinary` only when pull demand and storage release genuinely need different timing. Call `doneAndPullData` exactly once when more input may arrive and `releaseBuffer` exactly once when the buffer is no longer accessed. Bound retained buffers if pulling resumes before release. Copy bytes into application-owned memory before releasing when work may outlive Mu's buffer.

`isLast` describes the final fragment of one text or binary message. Process fragments incrementally or assemble them in order with a cumulative byte/character and fragment-count limit. `withMaxFramePayloadLength` limits each incoming frame, not the total fragmented message.

## Bound and serialize output

Treat every `sendText`, `sendBinary`, `sendPing`, and `sendPong` as asynchronous. Observe its callback, including failures after disconnect. Keep any sent `ByteBuffer` and its backing storage unchanged until that callback runs.

Give each session a single-writer, bounded outbox, measured by count and preferably bytes. Admit or reject before enqueueing; send one entry, then advance from its completion callback. This preserves ordering, prevents same-session producers from racing Mu's fragment state, and limits application memory even when the channel's internal backpressure queue grows. Keep every fragmented message contiguous from its first `isLastFragment=false` send through its final fragment; never interleave another data message.

Choose and test an overload policy appropriate to the application: reject the producer, drop an explicitly disposable update, or close the slow session. On a send error, release the queued entry's resources and terminate or fail the remaining queue deterministically.

## Close and clean up once

Use RFC 6455 close codes and keep the UTF-8 reason within the Close frame's remaining 123-byte payload. Prefer `1000` for normal completion, `1001` for a server going away, `1008` for an application policy violation, `1009` for an application message limit, and `1011` for an unexpected server failure. After starting close, stop admitting data sends.

Make cleanup idempotent because peer close, `onError`, send failure, application cancellation, and connection loss can race. Remove the socket from registries and release subscriptions, timers, queued buffers, executor tasks, and domain resources exactly once. When overriding `onClientClosed` or `onError`, retain the applicable `BaseWebSocket` behavior, normally with `try/finally` around application cleanup.

Track active application sessions. Before `MuServer.stop(...)`, stop admission, initiate close on each session with `1001`, wait only for a bounded application deadline, clean remaining resources, and then stop the server. Mu's graceful-stop wait covers HTTP requests rather than upgraded WebSocket sessions.

Read [version differences](references/version-differences.md) when targeting Mu Server 3, maintaining a 2.4.1 application, or reviewing an upgrade.

## Verify the wire behavior

Use the project's documented Java and build commands. Add focused tests that observe:

1. Exact path and context routing, non-upgrade fall-through, factory-decline fall-through, and a rejected candidate upgrade.
2. Authentication/origin policy, malformed or repeated key/version fields, all offered subprotocol header forms including malformed and duplicate tokens, the selected `101` response header, strict version 13 or preserved draft compatibility, unsupported version `426`, and ordinary response headers requested by the application.
3. Unfragmented and fragmented text and binary, continuation ordering, cumulative message limits, frame-limit violations, and non-ASCII text at a fragment boundary when relevant.
4. Delayed inbound completion, separate binary demand/release where used, buffer reuse only after send completion, concurrent producers, queue saturation, write failure, and disconnect during a queued or fragmented send.
5. Ping payload echo, automatic ping and idle-read settings, peer- and server-initiated close code/reason, malformed frames, callback exceptions, unexpected disconnect, cleanup exactly once, and application-led shutdown.
6. An HTTP/1.1 `ws` or `wss` client through every deployed proxy/load balancer path; Mu's direct WebSockets do not implement RFC 8441 extended CONNECT over HTTP/2.

Report the Java and Mu versions, route and fall-through order, handshake policy, subprotocol, frame and logical-message limits, inbound ownership decisions, outbox bounds and overload policy, ping/idle settings, close and cleanup policy, HTTP version observed, and exact tests run.

## Route adjacent work

Use the Mu getting-started workflow for a first ordinary HTTP server, the Jakarta REST workflow for annotated resources or server-sent events, and the Murp workflow for HTTP reverse-proxy tasks and its WebSocket-upgrade boundary. Use a Mu Server library-development workflow for changes to the WebSocket parser, state machine, transport, or public API. Browser-only WebSocket client work belongs with the application's frontend workflow.
