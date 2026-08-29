---
name: mu-server-browser-security
description: >-
  Use when building, configuring, reviewing, or testing browser-facing security in an io.muserver:mu-server application: CORS and preflight for direct Mu handlers or JAX-RS, CSRFProtectionHandlerBuilder, credential cookies, and browser security response headers. Trigger for cross-origin SPA APIs, cookie-authenticated forms, origin or proxy-authority checks, CSP and clickjacking policy, MIME sniffing, referrer or permissions policy, cross-origin isolation, and Mu Server 2.x or 3.x browser-hardening work.
license: MIT
---

# Secure browser-facing Mu Server applications

Preserve the application's intended browser origins, authentication model, routes, embedding requirements, and proxy topology. Treat CORS, CSRF, cookies, and response headers as separate controls with different trust boundaries.

## Inspect the application first

Inspect the resolved `io.muserver:mu-server` major version, server bootstrap and handler order, direct versus JAX-RS routes, public scheme and authorities, trusted ingress, browser origins, credential transport, state-changing methods, cookies, caches, and existing wire tests.

Determine which resources actually need cross-origin browser access. An origin is scheme, host, and port; it is not merely a domain. Confirm whether browser credentials must cross origins and whether any pages must be framed or use cross-origin isolation.

Read only the relevant references:

- For CORS config, preflight, direct-handler versus JAX-RS placement, and origin policy, read [CORS behavior](references/cors.md).
- For `CSRFProtectionHandlerBuilder`, bypass and rejection semantics, Fetch Metadata, and proxy authority, read [CSRF behavior](references/csrf.md).
- For `CookieBuilder`, session rotation/deletion, CSP, clickjacking, MIME, referrer, permissions, and isolation headers, read [cookies and response headers](references/cookies-and-response-headers.md).
- For 2.x/3.x differences and an observable verification matrix, read [versions and verification](references/versions-and-verification.md).

Route public TLS, HSTS, certificates, listener exposure, limits, overload, and graceful shutdown to production-hardening work. Route static-file MIME/cache/range behavior to static-resource work. Still verify that browser controls survive the deployed proxy and cache path.

## Establish the browser contract

Write down or infer:

- each browser origin allowed to read responses, whether credentials are included, and the exact methods and non-safelisted request headers it needs;
- which unsafe endpoints use ambient credentials, which legacy or non-browser clients omit `Origin` and Fetch Metadata, and which narrowly defined callback paths need exceptions;
- every session cookie's host, path, lifetime, `Secure`, `HttpOnly`, and `SameSite` policy, including login rotation and logout invalidation;
- the CSP sources, framing policy, referrer exposure, powerful features, and any deliberate cross-origin isolation requirements;
- the public authority and the immediate peers authorized to supply forwarding metadata.

## Compose handlers deliberately

Mu handlers run in registration order. An earlier handler that returns `true`, throws, or starts an async response prevents later handlers from running. A security middleware normally writes or checks policy and returns `false`; a rejection handler must terminate the exchange.

A typical global order is:

1. validate the immediate proxy peer and public authority;
2. add applicable browser response headers and, when non-JAX-RS responses also need it, direct CORS headers;
3. apply CSRF protection before all protected state-changing handlers;
4. run authentication/authorization and the application routes.

For a JAX-RS-only CORS surface, prefer `RestHandlerBuilder.withCORS(...)`; it derives allowed methods from matched resources and terminates generated `OPTIONS` responses. Use a direct `CORSHandlerBuilder` before the covered handler chain when direct handlers, middleware responses, or non-JAX-RS errors also require CORS. Choose one scope intentionally rather than layering duplicate CORS policies.

Keep authorization on every protected operation. CORS controls which responses conforming browsers expose; it does not authenticate clients or stop arbitrary HTTP requests. Mu's CSRF handler is a browser-request filter with deliberate compatibility allowances; it does not authenticate callers either.

## Verify behavior, not configuration shape

Use the project's supported Java version and real loopback HTTP requests. Verify allowed, disallowed, missing, malformed, and repeated values where applicable. Assert exact statuses and headers without letting the client silently follow redirects or hide failed preflights.

Exercise at least:

- a simple allowed-origin request, a disallowed origin, and a response without `Origin`, including exact `Vary: Origin` behavior;
- preflights for one allowed method/header combination and over-advertised or unsupported combinations, followed by proof that route matching and authorization still enforce the operation;
- unsafe requests with `Sec-Fetch-Site` values `same-origin`, `none`, `same-site`, and `cross-site`; trusted and untrusted `Origin`; no browser headers; every bypass path; and custom rejection behavior;
- spoofed `Host`, `Forwarded`, and `X-Forwarded-*` values through trusted and untrusted network paths when `request.uri()` influences CSRF decisions;
- complete `Set-Cookie` attributes, host/path scope, session fixation rotation, logout deletion, and rejection of stale credentials;
- security headers on successful HTML, errors, redirects, and cached responses, plus real-browser functional tests for CSP, framing, credentialed CORS, and cross-origin isolation when enabled.

Report the exact Mu major/version, public and browser origins, direct or JAX-RS CORS placement, handler order, proxy trust boundary, CSRF compatibility exceptions, cookie scope, response-header policy, tests run, and unresolved browser or deployment ambiguity.
