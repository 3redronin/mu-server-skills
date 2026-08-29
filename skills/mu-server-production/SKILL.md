---
name: mu-server-production
description: >-
  Use when hardening, deploying, or operating an application that directly embeds io.muserver:mu-server in production: listener exposure, HTTPS identity and mTLS, certificate rotation, HSTS, HTTP/2, limits and timeouts, rate limiting and executor overload, graceful shutdown, proxy trust, and runtime observability. Trigger for production-readiness reviews, load-balancer or container deployment, TLS incidents, capacity tuning, and shutdown, connection, or MuStats work in Mu Server 2.x or 3.x.
license: MIT
---

# Operate Mu Server in production

Make the server's externally observable behavior explicit and test it through the deployed network path. Preserve the application's handlers, framework choices, and public HTTP contract unless the user asks to change them.

## Inspect before changing

Inspect the build and resolved `io.muserver:mu-server` version, Java runtime, bootstrap code, listeners, TLS ownership, handler executor, shutdown integration, limits, proxy path, logging provider, metrics, and existing tests. Record current behavior before changing a running application's contract.

Determine the exact major line before selecting APIs. Treat Mu Server 3 as released. Preserve a selected version; if a version must be chosen, resolve the latest stable non-snapshot release for the selected major from the [Mu Server download page](https://muserver.io/download) and Maven Central. Do not infer a release number from a source snapshot or migration example.

Read [versions and deployment topology](references/versions-and-topology.md) for every production task. It contains the 2.x/3.x distinctions and listener-exposure rules.

Then load only the references needed:

- For server identity, protocols, ciphers, SNI, client certificates, redirects, HSTS, HTTP/2, or certificate rotation, read [TLS and HTTP/2](references/tls-and-http2.md).
- For request limits, timeouts, executor saturation, rate limits, connection budgets, or shutdown, read [capacity and lifecycle](references/capacity-and-lifecycle.md).
- For `Forwarded`, `X-Forwarded-*`, HAProxy PROXY protocol, logs, `MuStats`, rejection/completion listeners, active connections, or `SSLInfo`, read [proxy trust and observability](references/proxy-and-observability.md).

Keep ACME account/challenge/renewal setup in a dedicated `mu-server-acme` task, browser CORS/CSRF policy in browser security work, Murp target routing and upstream TLS in `mu-server-murp`, and authentication/business/readiness handler implementation in the application layer. This skill still verifies how those components meet the listener boundary.

## Establish the production contract

Before editing, write down or infer from deployment configuration:

- the exact bind address and fixed HTTP/HTTPS ports, including which listener is intentionally disabled;
- whether Mu Server, a trusted ingress, or both terminate TLS, and the public scheme and authority;
- server certificate names, key source, rotation owner, TLS policy, HTTP versions, and client-certificate mode;
- maximum URL, headers, body, HTTP/2 streams, request-body idle time, connection idle time, handler concurrency, queue, and shutdown drain time;
- which immediate peers are trusted to send PROXY or forwarding metadata and how spoofed values are removed;
- overload, rejection, latency, connection, TLS, certificate-expiry, and shutdown signals to export.

Do not copy arbitrary timeout or pool numbers from an example. Choose values from the application's legitimate request sizes, upload and streaming behavior, latency objective, downstream capacity, client retry behavior, replica count, and platform termination grace period. Keep a safety margin between Mu's drain timeout and the platform's forced-kill deadline.

## Implement narrowly

Use the existing `MuServerBuilder` and lifecycle. Set production-sensitive values explicitly so a library or JDK default change is not a deployment change. Do not add a framework or runtime dependency merely to hold configuration.

Keep secrets out of source, command-line arguments, logs, and generated reports. Load key material and passwords through the application's existing secret mechanism. Never replace certificate or hostname validation with a trust-all implementation.

Treat every claimed client address, original scheme, original host, and SNI name as untrusted until its transport and immediate peer have been verified. A parsed header is not an authenticated identity.

## Verify observably

Use the project's documented build and test commands on its supported Java version. Exercise only applicable checks, but do them across the same ingress and TLS path clients will use:

1. Inspect bound sockets and prove that each intended listener is reachable, each disabled listener is absent, and no test port `0` or test certificate remains.
2. Probe HTTP without following redirects and HTTPS with the real hostname. Assert exact status, `Location`, HSTS, certificate chain, hostname, negotiated TLS version/cipher, ALPN result, and an ordinary application response.
3. Test missing, trusted, and untrusted client certificates when mTLS is configured. For rotation, force a new TLS connection and prove both the new identity/policy and continued service.
4. Test values just below and above configured URL, header, and body limits; a stalled upload; handler-executor saturation; and rate-limit behavior when those controls changed.
5. From trusted and untrusted paths, send spoofed `Host`, `Forwarded`, `X-Forwarded-*`, and PROXY metadata as applicable. Prove which values the application observes and uses.
6. Start a controlled in-flight request, begin shutdown, prove new connections are refused, and test both completion within the drain window and forced termination after it.
7. Confirm metrics and logs distinguish completed exchanges, protocol-level rejections, overload, timeouts, handshake failures, active connections, and negotiated protocols without exposing secrets or request bodies.

Do not report a probe as successful if the client disabled hostname or certificate verification, silently followed a redirect, reused a pre-rotation TLS connection, or bypassed the production proxy path.

## Report the result

Report the exact Mu Server and Java versions; bind addresses and ports; TLS terminator and public authority; certificate and client-auth policy; HTTP versions; every explicit limit, timeout, executor, rate-limit, and drain value; proxy trust boundary; observability wiring; commands and wire behavior verified; and any selected-release ambiguity. Call out intentional differences between internal and external behavior.
