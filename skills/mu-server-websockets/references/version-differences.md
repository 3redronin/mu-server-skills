# Mu Server 2.4.1 and 3.x WebSocket differences

Read this reference when the project targets Mu Server 3, remains on 2.4.1, or is being upgraded between them.

## Dependency and platform

- Both lines use the single direct coordinate `io.muserver:mu-server`; there is no separate WebSocket artifact.
- Mu Server 2.4.1 targets Java 8 bytecode and SLF4J 1.7. Mu Server 3 requires Java 11 or newer and uses SLF4J 2. Preserve a compatible application logging provider when upgrading.
- Both lines expose these WebSocket APIs in `io.muserver`. Factory HTTP exceptions use `jakarta.ws.rs` in 2.4.1 and 3.x.
- Mu Server 3 is a released major line. Preserve an existing exact 3.x version or obtain the current stable version from release metadata; source-tree snapshot versions are not release coordinates.

## Direct WebSocket behavior

A comparison of tag `mu-server-2.4.1` with current master found no intentional behavior change in `WebSocketHandlerBuilder`, `WebSocketHandler`, `MuWebSocket`, `BaseWebSocket`, `MuWebSocketFactory`, `MuWebSocketSession`, or `MuWebSocketSessionImpl`. The current line adds JSpecify nullness annotations and related null-safe source cleanup:

- `MuWebSocketFactory.create` explicitly declares its fall-through `null` return nullable.
- `withPath(null)` and the optional close reason are explicitly nullable.
- `BaseWebSocket.onClientClosed` obtains the captured session through `session()`.

The established behavior remains: HTTP/1.1 GET Upgrade only, exact relative-path matching, response headers from the factory, callback-driven inbound demand, unassembled fragments, asynchronous sends, the same ping/idle defaults, and the same session state/close/error machinery.

## Shutdown return-value distinction

Both versions wait for active HTTP requests rather than upgraded WebSockets, so applications should drain tracked WebSocket sessions before server shutdown.

There is a separate 2.4.1 shutdown-result defect relevant to code that checks `MuServer.stop(duration, unit)`: its implementation returns `true` when HTTP requests remain after the grace period, opposite the public Javadoc. Current master returns `true` when the HTTP request drain completed and `false` when requests remained, and focused `StopTest` cases cover that contract. This does not add WebSocket draining in either line. Avoid using the 2.4.1 boolean as proof that WebSockets closed cleanly.
