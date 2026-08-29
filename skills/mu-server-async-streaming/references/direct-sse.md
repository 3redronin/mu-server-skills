# Direct server-sent events

Read this reference for direct `SsePublisher` or `AsyncSsePublisher` handlers, manual event-stream debugging, reconnect design, keepalives, or an SSE-versus-WebSocket decision. Jakarta REST SSE belongs to `mu-server-jaxrs` when that skill is available.

## Choose the transport

Prefer SSE for UTF-8 server-to-client notifications where normal HTTP authentication, browser `EventSource` reconnects, event IDs, and a separate HTTP request for client commands fit the protocol. Prefer WebSocket when the application needs messages in both directions on one channel, binary messages, or a WebSocket subprotocol. Do not replace a requested transport merely because both can remain open.

## Prefer Mu's publisher

`SsePublisher.start(request, response)` and `AsyncSsePublisher.start(request, response)` switch the request to async mode and set:

```text
Content-Type: text/event-stream
Cache-Control: no-cache, no-transform
```

Set any additional status, CORS, or application headers before the first send. Do not manually set `Connection: keep-alive` or `Transfer-Encoding`; connection-specific HTTP/1 fields are invalid in HTTP/2, and Mu owns protocol framing.

Use `SsePublisher` when a dedicated application worker may block for each client and simple sequential sends are acceptable. A send waits for the transport write and throws `IOException` on failure. Always close it in `finally`.

Use `AsyncSsePublisher` for non-blocking publication, especially with many subscribers. Its completion stage is the backpressure/error signal. It does not turn concurrent producers into a bounded queue: serialize sends and call `close()` only after the final stage completes. A simple continuation chain or per-client bounded queue is safer than calling `send` in a fast loop.

Install `setResponseCompleteHandler` before scheduling events. On completion, cancel subscriptions, timers, and queued work. `AsyncSsePublisher.isClosed()` becomes true when the application closes it or the exchange completion handler detects that the client/server ended the stream, but serialize send/close decisions instead of treating a concurrent check as an atomic reservation.

## Respect the event-stream format

The WHATWG HTML Standard defines `text/event-stream` and requires UTF-8. Each event is a sequence of fields terminated by a blank line:

```text
id: 42
event: price
data: {"symbol":"MU","value":12}

```

Each physical line of multiline data needs its own `data:` field. A comment starts with `:` and is ignored by the client. `retry:` contains milliseconds and changes the browser's reconnection delay; it is advisory. Mu's publisher methods create this framing, split multiline data, reject CR/LF in event names and IDs, and express reconnect time in milliseconds. Validate application IDs as well: `Last-Event-ID` cannot contain NUL, LF, or CR.

Do not hand-format events unless the application has a concrete requirement the publishers cannot express. If manual formatting is necessary, test exact UTF-8 bytes, the final blank line, multiline and empty data, and injection through names or IDs.

## Design reconnect and liveness

Browser `EventSource` normally reconnects after the stream ends. Server-side `publisher.close()` therefore does not tell a browser to stop permanently. The client must call `EventSource.close()`, or the server must return HTTP `204 No Content` to a subsequent connection when reconnecting should stop.

Give replayable events stable IDs and inspect `request.headers().get("Last-Event-ID")` on a reconnect. Define whether the ID is inclusive or exclusive, how long replay history is retained, and what happens when the requested ID has expired. `setClientReconnectTime` changes retry delay but does not implement replay or overload control.

For infrequent events, schedule comment keepalives on a shared application scheduler and pass them through the same serialized send path as data. The HTML Standard's non-normative authoring note suggests a comment about every 15 seconds for legacy proxies, but the correct interval depends on the shortest verified proxy/load-balancer/server idle timeout. Cancel the timer on every terminal path. A keepalive also creates network activity that can reveal a disconnect; no HTTP API can immediately detect every silent dead peer.

## Version boundary

The direct publishers and their wire format are substantially the same in Mu Server 2.4.1 and 3. Mu Server 3's documented SSE lifecycle/concurrency corrections concern Jakarta REST `SseEventSink`, `Response`, and `SseBroadcaster`: closed-state reporting, cascading broadcaster close, and at-most-once close/error callbacks under races. Do not claim those changes add transactional concurrent-send behavior to the direct publishers. Route Jakarta REST migration or broadcaster work to `mu-server-jaxrs` when available.

Evidence: [Mu SSE documentation](https://muserver.io/sse), [`AsyncSsePublisher` source](https://github.com/3redronin/mu-server/blob/master/src/main/java/io/muserver/AsyncSsePublisher.java), [WHATWG Server-sent events](https://html.spec.whatwg.org/multipage/server-sent-events.html), and [Mu Server 3 migration notes](https://muserver.io/changelog/mu-server-3).
