# Capacity and lifecycle

Use this reference for size limits, timeouts, overload, rate limiting, and shutdown.

## Set protocol limits from legitimate traffic

Configure these controls explicitly after measuring valid clients:

| Control | Current 2.4.1/3 implementation default | Observable rejection |
| --- | ---: | --- |
| `withMaxHeadersSize(...)` | 8192 bytes | `431 Request Header Fields Too Large` |
| `withMaxUrlSize(...)` | 8175 characters | `414 URI Too Long` |
| `withMaxRequestSize(...)` | 24 MiB | `413 Payload Too Large` |
| `withRequestTimeout(...)` | 2 minutes | A stalled request body is closed; `408` is sent if the response has not started |
| `withIdleTimeout(...)` | 10 minutes in the implementation | An all-idle connection is closed |
| HTTP/2 maximum concurrent streams | 200 where the setting exists | New concurrency is constrained per connection |

The `withIdleTimeout(...)` Javadoc says five minutes while the current field initialization and changelog use ten. This is a known documentation/implementation discrepancy: set the value explicitly and verify the selected release. A duration of zero disables either timeout; do that only when another enforced layer supplies the missing resource bound.

Header and URL limits protect parser allocation; increasing them for one client increases exposure for every request. The request-size limit is a total body bound, not an end-to-end execution deadline. `withRequestTimeout(...)` is an inactivity timeout while reading a body, not a maximum handler duration. Long-lived responses, SSE, WebSockets, slow valid uploads, and connection reuse must inform the connection-idle value.

Test exact boundary values plus over-limit chunked and declared-length bodies. HTTP/1.1 and HTTP/2 can reject at different parser states, so assert status/stream or connection behavior rather than requiring an identical response body.

## Bound handler work

Mu's Javadoc describes a cached default executor, while the current implementation creates a `ThreadPoolExecutor` with 8 core threads, up to 400 threads, a 60-second keepalive, and a `SynchronousQueue`. Do not make capacity plans from either description. Supply an explicit executor when concurrency is part of the production contract.

Use a bounded pool and bounded queue sized from blocking behavior, downstream limits, memory, and latency objectives. Keep `AbortPolicy`-style rejection: Mu catches `RejectedExecutionException`, sends `503 Service Unavailable`, and increments `rejectedDueToOverload`. `CallerRunsPolicy` can move blocking handler work onto an I/O thread, while discard policies can leave requests without a deterministic response.

A queue absorbs short bursts but also delays work and consumes request resources. Load-test saturation, latency, memory, downstream pressure, and recovery. Mu shuts down the executor supplied through `withHandlerExecutor(...)` when the server stops, so do not share it with unrelated application work whose lifecycle must continue.

There is no `MuServerBuilder` maximum-connection setting. Bound connection exposure with the listener network, ingress/load balancer, file-descriptor and memory limits, sensible idle timeouts, and HTTP/2 stream limits. Observe `activeConnections()` and active requests under slow-client and keep-alive load.

## Apply rate limiting at the right layer

`withRateLimiter(...)` can add one or more selectors. A selector returns a `RateLimit` bucket or null; a breached limit can send `429` or use `IGNORE` for observation. Each limiter is local to one server process and its buckets reset with that process, so it is not a distributed quota across replicas.

Use `request.remoteAddress()` for a direct peer. `request.clientIP()` accepts forwarding metadata and is safe as a security bucket only when the immediate proxy is trusted and removes spoofed input. At a public edge, prefer an ingress/WAF for globally coordinated abuse controls. Test bucket cardinality and expiry so attacker-controlled bucket names do not create unbounded state.

Rate limiting and executor rejection answer different questions: rate limits protect selected identities or traffic classes with `429`; bounded execution protects server capacity with `503`. Preserve that distinction for clients and alerts.

## Drain on shutdown

`addShutdownHook(true)` calls the no-argument `server.stop()`, which performs an immediate stop in the current API. For a controlled drain, integrate the platform lifecycle explicitly:

1. Make the instance unready or remove it from load-balancer targets.
2. Allow routing changes to propagate if the platform requires it.
3. Call the blocking `server.stop(drain, unit)`. It stops accepting new connections, waits for in-flight requests, and aborts remaining connections after the deadline.
4. Stop application resources in dependency order and exit before the platform's force-kill deadline.

Record the return value, but interpret it by major line: 2.x through 2.4.1 has the reversed result (`false` clean, `true` timed out); 3.x returns `true` clean and `false` timed out. Do not "fix" this with one expression that silently changes meaning across an upgrade.

Test two deterministic cases: one in-flight request completes inside the drain window, and one exceeds it. In both, prove that a new connection is refused once shutdown begins. Include streaming and upgraded connections if the application relies on them, because an empty ordinary-request set does not by itself describe every long-lived connection.
