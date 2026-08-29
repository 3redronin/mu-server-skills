# Proxy trust and observability

Use this reference for inbound proxy metadata, logging, metrics, and live connection inspection. Murp's target selection, upstream connection, and target TLS are a separate proxy-handler concern.

## Treat forwarding headers as claims

Mu parses RFC 7239 `Forwarded` and legacy `X-Forwarded-*` values. If `Forwarded` is present it takes precedence; otherwise Mu combines compatible `X-Forwarded-For`, `-Host`, `-Port`, and `-Proto` values. The first usable element affects:

- `request.clientIP()` through its `for` value; and
- `request.uri()` through forwarded scheme and host values.

These APIs do not authenticate the sender or apply a trusted-proxy allowlist. A direct client can supply the same headers. `request.serverURI()` and `request.connection().remoteAddress()` retain connection-local facts and are the safer basis for establishing the immediate peer.

At an ingress boundary:

1. Restrict Mu's listener so only trusted ingress addresses can connect.
2. Configure that ingress to remove inbound forwarding headers and emit one canonical policy-defined chain.
3. Validate the immediate socket peer before using forwarded values for authentication, authorization, rate-limit identity, security logging, redirects, or absolute links.
4. Send a spoofed chain both through the ingress and directly to the listener during verification.

`Host` is also client-controlled and participates in URI construction when no trusted forwarded host overrides it. Allowlist the public authorities used for redirects and generated URLs.

## Use PROXY protocol only on a closed listener

Mu Server 2.1+ and 3 support HAProxy PROXY protocol v1/v2:

```java
.withHAProxyProtocolEnabled(true)
```

The PROXY preamble is parsed before HTTP and before TLS. When enabled, every connection to that listener must provide it; a normal client without the preamble fails. The preamble is not cryptographically authenticated, so expose this listener only to the trusted load balancer over a protected network path.

Read the supplied addresses with `request.connection().proxyInfo()`. The immediate peer remains available from `remoteAddress()`. Verify source and destination address/port for both plaintext and TLS if used, rejection without a preamble, and inability to bypass the trusted sender. Forwarding headers and PROXY metadata are independent channels; define which one is authoritative rather than merging them opportunistically.

## Export the available signals

`server.stats()` exposes process-lifetime counters and gauges:

- active/completed connections and requests;
- bytes read and sent;
- invalid HTTP requests;
- TLS/connect failures; and
- requests counted by `rejectedDueToOverload()`.

Despite that counter's name and Javadoc, the current 2.4.1/3 implementation increments it for both rate-limit `429` and handler-executor `503` rejections. Use `addRequestRejectListener(...)` and record its status when those causes must be distinguished; do not label the aggregate counter as executor saturation alone.

Poll counters monotonically and calculate rates in the monitoring system. Alert on sustained overload/rejection, handshake failures, active-request or connection saturation, error latency, and certificate-expiry margins rather than a single absolute sample.

`addResponseCompleteListener(...)` supplies duration, final request/response, and `completedSuccessfully()`. A fully delivered `500` is transport-successful, so record HTTP status separately. Keep the callback fast, non-blocking, non-throwing, and bounded; do not read or log request/response bodies.

Protocol-level rejections occur before a normal exchange and do not invoke response-completion listeners. In 2.3.1+ and 3, `addRequestRejectListener(...)` exposes best-effort method/URI, status, reason, and connection for cases such as `431`, `413`, `429`, or executor `503`. Method or URI can be absent when decoding failed early. Treat attacker-controlled values as untrusted and cap log cardinality.

`server.activeConnections()` and `request.connection()` expose:

- HTTP protocol and whether HTTPS is used;
- negotiated TLS protocol and cipher;
- start time, completed/rejected counts, and active requests;
- remote socket address;
- optional client certificate, SNI hostname, and PROXY information; and
- active WebSockets.

Use aggregated or sampled views. Do not expose the raw connection set, client certificates, addresses, headers, or request objects on a public diagnostics endpoint.

`server.sslInfo()` reports configured provider, protocols, ciphers, and a discovered default certificate chain. Check certificate expiry, but also perform hostname-specific external TLS probes because certificate discovery can return empty and does not enumerate every SNI identity.

## Configure logging deliberately

Mu Server supplies the SLF4J API, not a production logging backend. Use one application-selected provider compatible with the major line: SLF4J 1.7 for Mu 2.x and SLF4J 2.0 for Mu 3.x. Check the resolved dependency graph for old bindings, multiple providers, and application-pinned Netty or logging artifacts.

Log startup/shutdown outcome, listener addresses, artifact/Java version, safe configuration values, response status/latency, and aggregate rejection/TLS events. Redact authorization, cookies, client certificates, key material, passwords, request bodies, and sensitive query values. Keep health and metrics surfaces private and distinguish liveness, readiness, and diagnostics in the surrounding application/platform design.
