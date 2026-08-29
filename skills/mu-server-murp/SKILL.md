---
name: mu-server-murp
description: >-
  Use when adding, configuring, troubleshooting, or testing the io.muserver:murp HTTP reverse-proxy handler in a Mu Server application. Covers ReverseProxyBuilder, UriMapper routing and fall-through, upstream TLS and timeouts, client certificates and mTLS on either proxy leg, Host/Forwarded/Via policy, streaming listeners, interceptors, and upstream 502 or 504 failures.
license: MIT
---

# Add a Murp reverse proxy to Mu Server

Treat Murp as an asynchronous `MuHandler` inside the application's existing Mu Server. Preserve its server builder, ports, TLS, HTTP/2 settings, local routes, handler order, and lifecycle unless the request changes them.

## Inspect before editing

Inspect the build system, Java and Mu Server versions, handler order, local paths that must remain local, upstream origins and base paths, path-prefix behavior, request methods and body sizes, downstream and upstream client-certificate requirements, target TLS requirements, trusted proxy boundary, timeout expectations, HTTP versions, observability, and existing integration tests.

Keep the application's direct `io.muserver:mu-server` dependency and add a direct `io.muserver:murp` dependency. Murp's Mu Server dependency is provided metadata, not a transitive server runtime. Preserve selected versions; otherwise verify the newest stable releases in Maven Central and on [the Murp documentation page](https://muserver.io/murp). If release metadata is unavailable, use Murp `1.2.2` as a disclosed offline fallback. Murp 1.2.2 has Java 11 bytecode; the selected Mu Server or application may require a newer Java version. Prefer the latest stable Java for a new application.

## Design the proxy boundary

Read [Murp configuration and behavior](references/configuration.md) before implementing routing, upstream HTTP clients, header policy, interceptors, listeners, or failure handling.

Use `UriMapper.toDomain(...)` when every accepted request keeps its original raw path and query at one fixed target origin. Use a custom `UriMapper` when routing selectively, stripping a prefix, adding a base path, or choosing among an allowlisted set of targets. Returning `null` means Murp did not handle the request and the next handler may run.

Keep the target scheme and authority application-controlled. When any part of routing depends on client input, constrain it to explicit schemes, hosts, ports, and path rules so the proxy cannot become an open proxy or SSRF primitive.

Set header trust deliberately. Murp emits `Forwarded` and `Via`; legacy `X-Forwarded-*` headers are opt-in. Discard client-supplied forwarding headers at an untrusted edge, but preserve them when an authenticated upstream proxy is intentionally part of the trust chain. Decide whether the target needs the original `Host` header or its own authority.

For production HTTPS targets, supply a certificate-validating `HttpClient`. Murp's implicit default client trusts target certificates, so relying on it is not an acceptable production TLS policy.

Treat client-to-Mu TLS and Murp-to-target TLS as independent connections. Configure downstream client-certificate authentication on Mu Server's `HttpsConfigBuilder`; configure a proxy-owned client identity for an mTLS target on the JDK `HttpClient`. Murp terminates downstream TLS and cannot pass that TLS session or the downstream client's private key through to the target. If the target needs the authenticated downstream identity, authorize it before Murp and forward only an application-defined identity through an overwritten header on a protected proxy-to-target boundary.

## Verify observable behavior

After editing:

1. Run the clean build on the project's Java version and inspect the resolved `mu-server`, `murp`, SLF4J, and JDK HTTP client setup.
2. Start a controlled target and the proxy. Verify an unchanged local route and each proxied method with raw encoded paths, query strings, headers, request bodies, response bodies, status codes, cookies, and streaming behavior that the application uses.
3. Observe the target to verify the exact target URI, `Host`, `Forwarded`, `Via`, optional `X-Forwarded-*`, and removal of hop-by-hop headers. Test spoofed forwarding headers at the configured trust boundary.
4. Test a deterministic pre-response target transport failure and a total timeout, expecting `502 Bad Gateway` and `504 Gateway Timeout`. If the target fails after the response starts, verify connection or stream termination rather than expecting a replacement status.
5. For HTTPS targets, test a valid certificate and a certificate or hostname failure. Where client certificates are used, test missing, trusted, and untrusted certificates independently on both TLS legs; also test identity-header spoofing if downstream identity is forwarded. For selective mappings, verify non-matching requests fall through rather than proxying.

Report exact dependency and Java versions, listener and target addresses, URI mapping and fall-through rules, the authentication and identity policy for each TLS leg, forwarding and Host policy, timeout values, interceptor or listener behavior, and the build and HTTP checks performed.
