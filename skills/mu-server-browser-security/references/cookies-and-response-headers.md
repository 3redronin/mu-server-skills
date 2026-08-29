# Cookies and response headers

Use this reference when browser credentials or document security policy are in scope. Cookie production and user-agent processing are standardized by [RFC 10025](https://www.rfc-editor.org/rfc/rfc10025.html), the July 2026 HTTP State Management Mechanism that obsoletes RFC 6265; Mu constructs the `Set-Cookie` field but does not manage sessions or tokens.

## Select every cookie attribute deliberately

`CookieBuilder.newCookie()` creates a session cookie with `Secure=false`, `HttpOnly=false`, `SameSite=None`, no Domain, and no Path. It serializes `SameSite=None`; this is not the browser's historical omitted-attribute default. Modern browsers require `Secure` for a `SameSite=None` cookie to be accepted in cross-site contexts.

`CookieBuilder.newSecureCookie()` and `Cookie.builder()` create a session cookie with `Secure`, `HttpOnly`, and `SameSite=Strict`, with no Domain or Path:

```java
Cookie session = CookieBuilder.newSecureCookie()
    .withName("__Host-session")
    .withValue(opaqueSessionId)
    .withPath("/")
    .withMaxAgeInSeconds(1800)
    .build();
response.addCookie(session);
```

No Domain produces a host-only cookie. Prefer that narrower scope; `withDomain(...)` makes a cookie available to matching subdomains and only checks that the supplied string has no colon. Omitting Path causes the user agent to derive a default from the setting request's path. This is true despite `withPath(null)` Javadoc describing null as applying to all paths: Mu omits the attribute and RFC 10025's default-path algorithm governs the browser. Set `/` explicitly for an application-wide cookie or a narrower stable path intentionally.

The `__Host-` prefix is useful for a host-bound session cookie, but Mu does not enforce its browser contract: the cookie must be set from a secure origin, include `Secure`, include `Path=/`, and omit Domain. Test the complete wire field and browser acceptance.

Choose SameSite from the actual flow:

- `Strict` gives the narrowest cross-site sending policy and is the secure-builder default;
- `Lax` can support intended top-level navigation flows while reducing ambient cross-site requests;
- `None` supports intentional cross-site cookie use and requires `Secure`, strong CORS/origin policy, and independent CSRF defenses.

`Secure` limits cookie transmission to secure contexts; `HttpOnly` denies script access. Neither prevents a browser from attaching the cookie to a request, and neither repairs XSS or CSRF by itself. Keep tokens opaque, unpredictable, short-lived as risk requires, and invalidatable server-side; avoid putting sensitive plaintext or authorization claims in an unsigned cookie.

Rotate the session identifier after authentication and privilege changes, invalidate the prior identifier server-side, and define absolute and idle expiry. On logout, invalidate server state and send the same cookie name, Domain, and Path with an empty value and `withMaxAgeInSeconds(0)`. Match the original scope so the browser removes the intended cookie; retain secure attributes on the deletion response.

Mu rejects illegal cookie names and raw values. Use `withUrlEncodedValue(...)` for arbitrary text and decode it symmetrically, or generate a cookie-safe opaque encoding. Treat inbound cookies as untrusted and handle missing, repeated, stale, and invalid values explicitly.

## Add security headers as ordinary middleware

Mu has header-name constants for CSP, `X-Content-Type-Options`, `X-Frame-Options`, and HSTS; use literal lowercase names for other fields. Register a non-terminal handler before the responses it should cover:

```java
MuHandler browserHeaders = (request, response) -> {
    response.headers().set(HeaderNames.CONTENT_SECURITY_POLICY,
        "default-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'");
    response.headers().set(HeaderNames.X_FRAME_OPTIONS, "DENY");
    response.headers().set(HeaderNames.X_CONTENT_TYPE_OPTIONS, "nosniff");
    response.headers().set("referrer-policy", "strict-origin-when-cross-origin");
    response.headers().set("permissions-policy", "camera=(), microphone=(), geolocation=()");
    return false;
};
```

The shown CSP is only a starting shape. Derive `script-src`, `style-src`, `connect-src`, `img-src`, `font-src`, `form-action`, and other directives from the application's real assets and integrations. Prefer hashes or per-response nonces where inline content is required. Deploy `Content-Security-Policy-Report-Only` first when an existing application needs telemetry before enforcement, then enforce and monitor reports. A copied restrictive policy that breaks login, payments, or asset loading is not a successful hardening change.

Use CSP `frame-ancestors` as the primary framing policy. Add `X-Frame-Options: DENY` for compatibility when the CSP is `frame-ancestors 'none'`, or `SAMEORIGIN` for the corresponding self-only policy. X-Frame-Options cannot express a general origin allowlist. The [CSP specification](https://www.w3.org/TR/CSP3/) defines browser enforcement.

Set `X-Content-Type-Options: nosniff` and send accurate Content-Type values. Select an explicit [Referrer-Policy](https://www.w3.org/TR/referrer-policy/) based on required referrer data. Use [Permissions-Policy](https://www.w3.org/TR/permissions-policy/) to disable or delegate powerful features according to actual page and iframe needs.

Set `Cross-Origin-Opener-Policy`, `Cross-Origin-Embedder-Policy`, and `Cross-Origin-Resource-Policy` only when the application needs their isolation or resource-sharing semantics. Cross-origin isolation commonly needs compatible COOP and COEP across a document and all loaded resources; it can break OAuth popups, third-party widgets, downloads, and cross-origin assets. Test those workflows in supported browsers before enforcement.

HSTS is an HTTPS deployment contract, not merely another application header. Configure and verify it with the production listener/ingress owner, including redirect behavior, public authority, `includeSubDomains`, preload intent, certificate validity, and proxy stripping. Do not derive any security header, redirect, cookie Domain, or absolute URL from unvalidated Host/forwarding metadata.

Apply the header middleware to the intended successful pages, redirects, and errors. Earlier terminal handlers and proxy-generated responses need their own equivalent policy. Verify the final headers after compression, static handling, ingress, and CDN caching; test actual browser behavior in addition to curl-level presence.
