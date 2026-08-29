# Direct WebSocket protocol and lifecycle

Read this reference when implementing, hardening, troubleshooting, or reviewing a direct Mu WebSocket endpoint.

## Handler and handshake

`WebSocketHandler` returns `false` unless all of these preconditions hold:

- the method is `GET`;
- an explicit non-empty `withPath` exactly equals `request.relativePath()`; and
- `Upgrade` contains `websocket`, compared case-insensitively.

It then calls `MuWebSocketFactory.create` on Mu's handler executor. Returning `null` continues the handler chain. Returning a socket invokes the HTTP/1.1 handshaker; an unsupported version returns `426 Upgrade Required` with `Sec-WebSocket-Version: 13`. Exceptions from the factory enter Mu's ordinary HTTP exception handling, so a `ClientErrorException` can choose a rejection status before the upgrade.

The later handshaker checks `Connection: Upgrade`, `Upgrade: websocket`, key presence, and its supported versions. It does not perform all RFC 6455 syntax checks: the delegated Netty factory retains draft-version 7/8 compatibility, and the version-13 path checks that `Sec-WebSocket-Key` exists but does not decode it to confirm the required 16 bytes. For a new strictly RFC 6455 endpoint, validate one version value equal to `13` and one valid 16-byte base64 key in the factory before accepting. Preserve deliberate draft-client compatibility in an existing application and document it. In every case, treat the request as untrusted even though Mu's initial selector saw `Upgrade: websocket`.

`withPath` is relative inside `ContextHandler`. Query parameters do not participate in that path equality and can be inspected in the factory. Handler order remains ordinary Mu order: the first handler returning `true` wins.

Use request headers and connection data to apply the application's authentication, authorization, browser `Origin`, host, and TLS policy. An `Origin` allowlist is application policy protecting browser-facing endpoints; non-browser clients are allowed by RFC 6455 to omit `Origin`, so decide absence explicitly rather than assuming it means trusted.

Mu passes factory response headers to the `101`. Subprotocol selection is application-owned:

```java
private static final Pattern TOKEN =
    Pattern.compile("[!#$%&'*+.^_`|~0-9A-Za-z-]+");

private static List<String> offeredProtocols(Headers headers) {
    List<String> result = new ArrayList<>();
    Set<String> unique = new HashSet<>();
    for (String raw : headers.getAll(HeaderNames.SEC_WEBSOCKET_PROTOCOL)) {
        for (String part : raw.split(",", -1)) {
            String token = part.trim();
            if (!TOKEN.matcher(token).matches() || !unique.add(token)) {
                throw new ClientErrorException(400);
            }
            result.add(token);
        }
    }
    return result;
}
```

Select one supported token from this list and use `responseHeaders.set(HeaderNames.SEC_WEBSOCKET_PROTOCOL, selected)`. RFC 6455 requires the response value to be one the client offered, permits multiple request-header occurrences, and permits only one response occurrence. Mu constructs its Netty handshaker with extensions disabled, so do not advertise `Sec-WebSocket-Extensions` from application code.

## Threads and callback completion

The factory is an ordinary handler call on the configured Mu handler executor. After a successful handshake, `onConnect` and inbound socket callbacks are dispatched on the connection's NIO event loop. They must not block.

Normal asynchronous send completions are delivered by the channel future, normally on its event loop. If the session is already closed or closing, Mu can call the completion synchronously from the thread that attempted the send. A callback that throws is logged and can trigger a `1011` close. Keep callbacks short, thread-safe, and independent of a particular executor.

Mu issues one channel read at a time. Completing an inbound callback requests the next read. The callback accepts an error: passing a non-null error enters WebSocket error handling before read completion. Invoke it exactly once on every asynchronous success, failure, rejection, and cancellation path.

For text, Mu has already made a `String`; completion controls demand but not that String's lifetime. For binary, ping, and pong, the `ByteBuffer` views retained Netty storage. The three-argument completion releases it. The four-argument binary callback separates these concerns:

- `doneAndPullData.onComplete(error)` permits the next frame to be read;
- `releaseBuffer.run()` releases the current storage.

The default four-argument method delegates to the three-argument method and combines release with demand. Override it only to retain a buffer while accepting later frames, and put a hard bound on that retained storage.

Mu's binary sends wrap the supplied `ByteBuffer` without copying. Do not mutate its remaining bytes or backing memory until the send callback. Passing an inbound completion directly to `sendBinary` or `sendPong` transfers the lifetime through the outbound write safely.

## Fragmentation and limits

Each data callback corresponds to a data frame or continuation frame. `isLast=true` is the FIN bit for the final fragment. Mu does not assemble a logical message for the application. It rejects an invalid continuation sequence in the frame decoder and tracks whether the current inbound message is text or binary.

For outgoing fragments, the two-argument send overloads produce a final single-frame message. The three-argument overloads with `isLastFragment=false` start or continue a fragmented message. Mu prevents switching between text and binary while the other type is unfinished, but its continuation state is not an application outbox and does not make racing multi-threaded producers a valid serialization strategy.

`withMaxFramePayloadLength` defaults to 65,536 bytes and rejects values below 1,024. It configures the incoming frame decoder. It does not cap:

- the sum of fragments in a logical message;
- the number or duration of fragments;
- outbound frame or message sizes; or
- application queues and retained buffers.

Set an application logical-message limit and close with `1009` when it is exceeded. Decide whether to accumulate text by characters or encoded UTF-8 bytes, then make the limit and tests match. Mu decodes each text frame to a `String` separately instead of decoding the complete fragmented message as one UTF-8 sequence. A code point split across frame boundaries therefore cannot be faithfully reconstructed through the direct text callback. If arbitrary RFC 6455 fragmentation must interoperate for such text, use a binary application protocol or resolve the limitation in Mu itself; an application test with a split multi-byte code point should expose the boundary rather than assuming string concatenation repairs it.

A decoder-level frame-size violation is transport/parser behavior, not the same path as an application logical-message limit. In Mu 2.4.1 with its resolved Netty line, a peer can observe an immediate transport close instead of receiving the decoder's intended `1009` Close frame. Application-detected logical oversize can send `1009` reliably before closing. Test the observable frame-limit behavior with the exact resolved Mu/Netty version and avoid making the Close frame itself a portable application contract unless that combination proves it.

RFC 6455 permits control frames between data fragments but forbids fragmented control frames. Ping, pong, and Close payloads are at most 125 bytes. Keep ping/pong payloads within that limit and keep a Close reason within 123 UTF-8 bytes after the two-byte status code.

## Output serialization and backpressure

All session sends enqueue an asynchronous channel write. Mu's channel backpressure handler defers writes while the channel is not writable, but that internal queue is not an application admission limit. A fast producer can otherwise retain unbounded messages and buffers.

Use a per-session bounded single-writer outbox. A robust design records each immutable text payload or owned binary buffer, its byte cost, fragment metadata, and a completion. It has these transitions:

1. Atomically reject, drop under an explicit disposable-update policy, or enqueue within count/byte limits.
2. If no write is active, submit the head entry.
3. From the send completion, release that entry, record success or error, and pump the next entry. Make the pump reentrancy-safe because a closed-session send can complete synchronously.
4. On close or first terminal write failure, reject new entries and drain queued ownership/completions exactly once.

Serialize an entire fragmented message, not merely individual fragments. A control frame may be sent between fragments by the protocol, but application data messages cannot be interleaved. For broadcasts, maintain one queue and overload decision per client so one slow client does not hold up all peers.

`DoneCallback.NoOp` is suitable only when the application truly ignores the result and no ownership or state transition depends on completion. It does not make a mutable `ByteBuffer` safe to reuse early.

## Ping and idle behavior

`withIdleReadTimeout` defaults to five minutes. Zero disables it. When no frame is read before the interval, Mu calls `onError` with `TimeoutException`. `BaseWebSocket` responds by closing with `1001` and reason `TIMED_OUT`.

`withPingSentAfterNoWritesFor` defaults to 30 seconds. Zero disables it. On writer-idle, Mu sends a Ping with payload `mu`. A received Pong counts as input for the read timeout. These settings are transport liveness controls, not application authentication, presence, or end-to-end latency guarantees.

RFC 6455 requires a Pong response as soon as practical with the Ping's application data. `BaseWebSocket.onPing` calls `sendPong(payload, onComplete)` and therefore preserves both payload and buffer lifetime. Its `onPong` simply completes demand.

## Close, error, cleanup, and shutdown

`session.close()` uses `1000` and reason `Server`. `close(code, reason)` rejects calls once the state is terminal and rejects numeric values outside 1000 through 4999; Netty applies additional RFC validity checks. Mu changes its state to closing before constructing the Netty Close frame, so a value that passes Mu's broad range check but fails Netty's RFC check can leave the session in a closing state without a sent frame. Validate and choose a defined or valid private-use code before calling `close`.

When the peer sends Close, `BaseWebSocket.onClientClosed` sends a matching Close and Mu closes the channel after that write. A server-initiated close also closes the channel after the Close write. There is no separate application `onClosed` callback for a clean server-initiated close.

`onError` can report `ClientDisconnectedException`, `TimeoutException`, invalid/corrupt frames, exceptions from application callbacks, and transport failures. `BaseWebSocket.onError` maps timeout to `1001`, Netty `CorruptedFrameException` to `1008`, and other errors to `1011`, unless the session is already terminal. Throwing from `onError` makes Mu close the connection.

Treat callback order as racy at terminal boundaries. A failed inbound completion can enter error handling and then propagate another connection event; a write can fail while the peer is closing; and abrupt channel loss calls `onError(ClientDisconnectedException)` when no terminal state was recorded. Use an atomic once-only cleanup gate and do not require one exact last callback ordering.

Track accepted sockets/sessions in application-owned concurrent state. Add only after `onConnect`, and remove on peer close, error/disconnect, application close, and failed setup. Ensure application-initiated close also triggers removal because no server-side `onClosed` callback follows it.

`MuServer.stop(duration, unit)` stops accepting connections and waits on `MuStats.activeRequests()`. An upgraded WebSocket is exposed through `HttpConnection.activeWebsockets()` rather than `activeRequests()`, so that grace period does not drain WebSocket sessions. Closing worker event loops can surface as abrupt disconnect. Perform an application WebSocket drain first, with a bounded deadline, then stop the server.

## HTTP version and specification boundaries

Mu's direct WebSocket implementation is the RFC 6455 HTTP/1.1 GET Upgrade path. `HttpConnection` documents a one-to-one WebSocket-to-HTTP/1.1-connection mapping. An HTTPS listener may support HTTP/2 for ordinary traffic while a WebSocket client negotiates HTTP/1.1 on that same listener.

[RFC 8441](https://www.rfc-editor.org/rfc/rfc8441.html) defines HTTP/2 WebSockets using extended `CONNECT` and `:protocol=websocket`, without HTTP/1.1 `Connection` or `Upgrade` headers. Mu's direct handler does not implement that path. Verify that clients, reverse proxies, ingress, and ALPN policies permit HTTP/1.1 end to end.

The normative wire contract is [RFC 6455](https://www.rfc-editor.org/rfc/rfc6455.html), especially sections 4.2 (server handshake), 5.4 (fragmentation), 5.5 (control frames), and 7 (closing). Mu defaults and callback behavior described above are implementation contracts or conventions rather than WebSocket requirements.
