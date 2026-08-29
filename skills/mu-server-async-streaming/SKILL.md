---
name: mu-server-async-streaming
description: >-
  Use when implementing, reviewing, or debugging Mu Server direct-handler asynchronous HTTP streaming or direct server-sent events: MuRequest.handleAsync, AsyncHandle, RequestBodyListener, DoneCallback, ByteBuffer writes, backpressure, completion, disconnects, SsePublisher, AsyncSsePublisher, or browser EventSource behavior.
license: MIT
---

# Build direct asynchronous streams with Mu Server

Keep the user's existing server, build, Java version, Mu Server version, executor ownership, routes, and public HTTP contract unless the request changes them.

## Route the task

This skill owns direct `MuHandler` and `RouteHandler` code that calls `MuRequest.handleAsync()`, plus direct `SsePublisher` and `AsyncSsePublisher` use.

- For Jakarta REST resources using `@Suspended`, `Sse`, `SseEventSink`, or `SseBroadcaster`, use `mu-server-jaxrs` if it is available. Do not assume that skill is installed; otherwise follow the application's Jakarta REST setup and authoritative Mu Server documentation.
- For an ordinary direct handler that completes before returning and uses `write`, `sendChunk`, `writer`, or `outputStream`, use `mu-server-handlers` if it is available. Do not assume that skill is installed.
- For bidirectional messages, binary messages, or a WebSocket protocol already chosen by the user, keep WebSocket architecture. Read [direct SSE](references/direct-sse.md) when deciding between SSE and WebSocket.

## Inspect before changing code

Identify the Mu Server major line, direct-handler registration, response metadata, request-body reader, producer and executor, write concurrency, terminal paths, response-completion listeners, HTTP versions in use, idle/proxy timeouts, and tests. Reproduce corruption, hangs, memory growth, premature completion, or disconnect leaks with observable HTTP behavior before editing when practical.

For any `handleAsync`, response-stream, upload, or cancellation work, read [async lifecycle and flow control](references/async-lifecycle.md). For direct SSE implementation, formatting, reconnect, keepalive, or lifecycle work, also read [direct SSE](references/direct-sse.md).

## Preserve the ownership contracts

- Calling `handleAsync()` transfers response completion to the application. Every path must eventually call `complete()` or `complete(Throwable)`, unless disconnect or timeout has already ended the exchange. A general `MuHandler` must then return `true`; a matched `RouteHandler` is already terminal.
- Set status, content type, cookies, and headers before the first asynchronous write. That write commits the response. Omit `Content-Length` for an open-ended stream; if it is set, send exactly that many bytes.
- Keep at most a small, explicit number of writes in flight—one is the safe default. Start the next read or production step from the previous write's callback or completed future. Queuing unbounded writes only moves backpressure into memory.
- Mu wraps the supplied `ByteBuffer`; it does not promise to copy its remaining bytes. Do not clear, refill, mutate, or otherwise reuse a buffer until that write's callback or future completes.
- Treat a failed write as terminal: stop the upstream producer, release resources, and finish once. `complete(error)` can produce an error response only before commitment; after commitment the client can receive only a failed or truncated stream.
- A `RequestBodyListener` callback runs on an I/O thread. Do not block it. Call its `DoneCallback` exactly once, only after the buffer is no longer needed. This returns demand for the next HTTP/1 chunk and HTTP/2 flow-control credit.
- Register response-completion handling before starting upstream work. Use `ResponseInfo.completedSuccessfully()` to distinguish a fully read request and fully sent response from disconnect, timeout, or transport failure; cancel application work in either case when it is no longer useful.

## Verify behavior

Use the project's documented build and test commands. Exercise the changed stream with content larger than one buffer and a deliberately slow reader or writer. Assert bytes and order, not just status. Also test empty input, the final partial buffer, producer/read/write failure, early client disconnect, and exactly-once resource cleanup. Run both HTTP/1.1 and HTTP/2 when the application supports both because their framing and flow control differ.

For SSE, verify `200`, `Content-Type: text/event-stream`, cache headers, exact blank-line-delimited UTF-8 event bytes, multiline data, IDs, reconnect behavior, keepalive cancellation, and disconnect cleanup. Report the Mu Server/Java versions, ownership model, maximum writes in flight, terminal paths, protocols tested, and any proxy timeout or reconnect assumption that could not be tested locally.
