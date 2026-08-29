# Versions and verification

Use this reference before selecting APIs and when proving observable browser behavior.

## Mu Server 2.4.1 and 3

Keep the existing `io.muserver:mu-server` coordinates and selected major. Treat Mu Server 3 as released. If an exact release must be selected, resolve a stable non-snapshot version for the chosen major from the [Mu Server download page](https://muserver.io/download) and Maven Central; do not infer a final v3 artifact number from source tags or migration examples.

For these direct APIs, Mu Server 2.4.1 and current Mu Server 3 have the same observable behavior:

- `CORSConfigBuilder`, `CORSHandlerBuilder`, and `RestHandlerBuilder.withCORS(...)`;
- `CSRFProtectionHandlerBuilder` and its decision/order/return-value semantics; and
- `CookieBuilder.newCookie()`, `newSecureCookie()`, cookie attributes, and response serialization.

The relevant source changes are JSpecify/nullness annotations and internal accessors, not a browser-policy change. Code compiling with strict nullness tooling may need to account for annotated nullable builder values in Mu 3.

Jakarta REST response cookies are a separate path. Mu Server 3 fixes `jakarta.ws.rs.core.NewCookie` behavior so default maximum age creates a session cookie without immediate expiry, supports Jakarta REST 3.1 SameSite serialization/parsing, and avoids duplicate `Set-Cookie` fields from wrapped responses. If an application returns `NewCookie` rather than `io.muserver.CookieBuilder`, read the Mu Server 3 migration page and add exact `Set-Cookie` regression tests.

## Wire-level matrix

Use a real server on loopback with an ephemeral port unless a fixture specifies a fixed port. Always stop it. Use the project's existing HTTP client; use a browser automation test for browser-only enforcement such as CSP, credential modes, cookie acceptance, framing, and isolation.

### CORS

For each covered route, assert:

- no Origin: `Vary` contains Origin once and no access-control allow fields are emitted;
- exact allowed Origin: echoed `Access-Control-Allow-Origin`, expected credentials/exposed fields, and preserved Vary tokens;
- disallowed and `Origin: null`: no allow-origin field under an explicit allowlist;
- preflight: exact allow methods/headers/max-age, success status from the actual later direct handler or generated JAX-RS OPTIONS, and no endpoint side effect;
- unsupported method/header: a real browser refuses the CORS operation and direct raw HTTP proves the server route or authorization rejects it independently;
- errors and authentication challenges: CORS fields appear only when those responses intentionally belong to the same cross-origin API.

Test origin comparisons with scheme, default/non-default ports, suffix lookalikes, regex boundaries, repeated Origin fields, and cache behavior when the client/proxy permits them. Do not reduce a repeated-field ambiguity to an arbitrary string normalization without checking Mu and ingress behavior.

### CSRF

Exercise every branch of the exact decision table:

- GET/HEAD/OPTIONS with hostile headers pass;
- POST or another unsafe method with `same-origin` and `none` passes;
- `same-site`, `cross-site`, and an unknown value reject unless Origin is exactly trusted;
- missing Sec-Fetch-Site falls back to matching, trusted, hostile, empty, and missing Origin;
- bypass path matches exactly while encoded, slash, query, and context variations behave as designed;
- default rejection is 400, custom terminal rejection returns the selected status, and a deliberately false custom handler demonstrates downstream fallthrough;
- Host and forwarding spoof tests prove the authority trust boundary.

For high-assurance endpoints, separately prove token presence, binding, expiry, replay policy, and invalid/missing token rejection. A curl request forging browser headers should still fail authentication or other application authorization when it is not a legitimate client.

### Cookies and response headers

Inspect raw `Set-Cookie` fields rather than only a cookie jar. Assert name/value, Domain absence or exact value, explicit Path, Max-Age/session behavior, Secure, HttpOnly, SameSite, and prefix requirements. Prove rotation invalidates the old identifier and logout removes the cookie at the same scope.

Assert security headers on representative 2xx, 3xx, 4xx, and 5xx responses after the deployed proxy. Then use supported browsers to verify CSP blocks only prohibited sources, framing policy, referrer behavior, feature delegation, cross-origin credential flows, and any COOP/COEP/CORP-dependent features. Record browser/version-dependent ambiguity rather than claiming a header's presence proves enforcement.
