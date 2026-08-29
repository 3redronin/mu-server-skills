# CSRF behavior

Use this reference for cookie- or ambient-credential state changes. Mu's handler implements a particular compatibility policy inspired by [Fetch Metadata Request Headers](https://www.w3.org/TR/fetch-metadata/) and an Origin fallback; it is not a general CSRF-token framework.

## Place the handler before protected work

```java
MuHandler csrf = CSRFProtectionHandlerBuilder.csrfProtection()
    .addTrustedOrigin("https://admin.example.com")
    .withRejectionHandler((request, response) -> {
        response.status(403);
        response.write("Forbidden");
        return true;
    })
    .build();

MuServer server = MuServerBuilder.muServer()
    .withHttpPort(8181)
    .addHandler(csrf)
    .addHandler(/* protected direct or JAX-RS handlers */)
    .start();
```

Allowed requests return `false` so the next handler runs. The default rejection handler throws `BadRequestException`; Mu's observed response is `400`. A custom rejection handler's return value becomes the CSRF handler's return value. It must return `true` after setting its response to reject the request. Returning `false` deliberately lets the rejected request reach later handlers.

Register the handler before every state-changing handler it protects. An earlier terminal handler bypasses it. Authentication and authorization are still required downstream.

## Apply Mu's exact decision table

Mu performs these checks in order:

1. GET, HEAD, and OPTIONS always pass. Every other Mu method continues through the checks.
2. A path in `addBypassPath(...)` passes before header inspection. Matching is exact against `request.uri().getRawPath()`: query is irrelevant, while context prefixes, trailing slashes, and percent-encoding distinctions remain observable.
3. `Sec-Fetch-Site: same-origin` and `Sec-Fetch-Site: none` pass.
4. If `Sec-Fetch-Site` is absent or empty, an absent or empty `Origin` passes for compatibility. Otherwise Mu permits an Origin whose string ends with `://` plus the effective request host and explicit port, or an exact configured trusted origin.
5. If `Sec-Fetch-Site` has any other value—including `same-site`, `cross-site`, or an unknown token—only an `Origin` exactly equal to a trusted origin passes.
6. Everything else invokes the rejection handler.

The fallback authority comparison does not compare the Origin scheme; it compares the origin string's authority suffix to the host and explicit port in `request.uri()`. Treat this as observable compatibility behavior, not a full same-origin implementation. The Fetch Metadata specification says unknown values should be ignored for forward compatibility, whereas Mu's current handler rejects them unless their Origin is trusted; preserve this stricter observable behavior unless an application explicitly implements a different policy.

`addTrustedOrigin` is an exact string allowlist. It is consulted both when Fetch Metadata reports cross-site/same-site and during the Origin fallback. A trusted origin is allowed to make unsafe credentialed requests, so keep this list minimal and independent from origins that merely need public CORS reads.

Bypass paths disable the check completely. Use them only for endpoints whose protocol supplies another CSRF defense, such as a cryptographically verified webhook or SSO callback, and test the exact raw-path variants. Health endpoints using GET do not require a bypass because safe methods already pass.

## Respect the boundary of the built-in policy

Fetch Metadata headers have a `Sec-` prefix and browser JavaScript cannot set them, which makes them useful browser context. Arbitrary HTTP clients can still forge them. Mu also allows unsafe requests with neither Fetch Metadata nor Origin so legacy and non-browser clients continue to work.

For higher-assurance cookie-authenticated actions, combine the handler with application-specific defenses appropriate to the clients:

- a synchronizer or properly bound double-submit CSRF token checked on every unsafe action;
- restrictive `SameSite` cookies where the login and navigation flows allow it;
- re-authentication or transaction confirmation for high-impact operations; and
- an explicit policy for legacy clients that omit browser headers, potentially using separate non-cookie authentication.

CORS is not a substitute: browsers can submit some cross-origin requests without granting JavaScript access to the response.

## Validate authority before relying on Origin

The fallback compares against `request.uri()`. Mu can construct that URI from client-controlled `Host` and parsed `Forwarded` or `X-Forwarded-*` fields; parsing those headers does not authenticate the proxy. A spoofed effective authority can change the CSRF decision.

At the deployed ingress boundary:

1. restrict the Mu listener to trusted ingress peers where possible;
2. require the ingress to strip inbound forwarding fields and emit one canonical set;
3. validate the immediate socket peer before accepting forwarded scheme/authority;
4. allowlist the public authorities before the CSRF handler; and
5. test spoofed Host and forwarding values both through ingress and on attempted direct connections.

Use `request.connection().remoteAddress()` and `request.serverURI()` for connection-local evidence; use `request.uri()` only after the forwarding boundary is established. Fetch Metadata recommends an appropriate `Vary` field when cacheable response behavior depends on its headers. State-changing responses normally should not be shared-cacheable; make any exception explicit.
