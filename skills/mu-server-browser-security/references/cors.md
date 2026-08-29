# CORS behavior

Use this reference when implementing or reviewing cross-origin browser access. The [Fetch CORS protocol](https://fetch.spec.whatwg.org/#http-cors-protocol) defines browser processing; the points below describe Mu's observable server behavior.

## Build one explicit policy

`CORSConfigBuilder.corsConfig()` starts with no allowed origins, credentials disabled, no allowed or exposed headers, and a 600-second preflight max age. `disabled()` also allows no origins and leaves max age at `-1`. Both configurations still cause Mu's CORS code to add `Vary: Origin` when it runs.

Prefer exact origins:

```java
CORSConfig cors = CORSConfigBuilder.corsConfig()
    .withAllowedOrigins("https://app.example.com")
    .withAllowedHeaders("Authorization", "Content-Type")
    .withExposedHeaders("X-Request-ID")
    .withAllowCredentials(true)
    .withMaxAge(600)
    .build();
```

Mu validates that listed origins start with `http://` or `https://` and have no path, then compares the request's `Origin` as an exact string. Include a non-default port when it is part of the browser origin.

`withAllOriginsAllowed()` allows every supplied origin. Mu responds by echoing that origin rather than writing `*`, so it also passes Fetch's credentialed CORS check when `withAllowCredentials(true)` is set. That combination therefore grants any website credentialed browser access; use it only for a genuinely public, non-sensitive contract. `withAllowCredentials(true)` merely emits `Access-Control-Allow-Credentials: true`; browser fetch credentials mode and cookie rules still decide whether credentials are sent.

`withAllowedOriginRegex(...)` uses Java `Pattern.matcher(origin).matches()`, so the entire origin must match. Regexes with unescaped dots or expressions that admit arbitrary schemes, suffix lookalikes, user-controlled subdomains, or unexpected ports silently widen the trust boundary. Use exact entries unless the deployment has a narrow, escaped, and tested family of origins.

`withAllowedHeaders(...)` names non-safelisted request headers the browser may send on a cross-origin request. Include `Authorization` explicitly when needed; it is not covered by a wildcard in credentialed Fetch processing. `withExposedHeaders(...)` controls which non-safelisted response headers browser JavaScript can read. These lists do not add authentication or application validation.

Choose a max age that permits revocation within the application's risk tolerance. Browsers may cap it below the advertised value.

## JAX-RS placement

For a CORS surface wholly owned by JAX-RS:

```java
MuHandler api = RestHandlerBuilder.restHandler(apiResource)
    .withCORS(cors)
    .build();
```

The Rest handler defaults to CORS disabled. With CORS configured, ordinary allowed-origin matched responses receive `Access-Control-Allow-Methods` based on the matched resource method; GET adds HEAD and generated values are sorted. For an `OPTIONS` request to a known JAX-RS path without an explicit OPTIONS resource method, the Rest handler returns a successful generated response, sets `Allow`, and derives `Access-Control-Allow-Methods` from all resource methods matched for that path, adding `OPTIONS` and HEAD when GET exists. An explicit OPTIONS resource method is invoked normally instead.

Configured allowed headers are advertised on an allowed-origin `OPTIONS` response; Mu does not separately reject the value of `Access-Control-Request-Headers`. The Fetch client compares the response with its requested headers. Likewise, the browser evaluates `Access-Control-Request-Method`; route matching and authorization remain the server-side enforcement.

`withCORS` covers responses handled inside that Rest handler, including its generated `OPTIONS` and OpenAPI JSON. It cannot add headers to an earlier authentication handler, an earlier terminal response, or unrelated direct handlers. Use a direct CORS handler when those responses intentionally share the CORS surface.

## Direct-handler placement and fallthrough

Register the CORS handler before every direct handler whose response it should decorate:

```java
MuServer server = MuServerBuilder.muServer()
    .withHttpPort(8181)
    .addHandler(CORSHandlerBuilder.corsHandler()
        .withCORSConfig(cors)
        .withAllowedMethods(Method.GET, Method.POST))
    .addHandler(/* auth and API handlers */)
    .start();
```

`CORSConfigBuilder.corsConfig()...toHandler(Method.GET, Method.POST)` is the equivalent builder shortcut. If allowed methods are null or empty, the direct builder advertises every Mu `Method` except TRACE and CONNECT. The serialized list always adds OPTIONS, and adds HEAD when GET is present.

The direct CORS handler calls `writeHeaders(...)` and always returns `false`:

- it adds `Vary: Origin` even when `Origin` is absent or disallowed;
- for an allowed origin it writes `Access-Control-Allow-Origin`, the configured methods, exposed headers and credentials on ordinary responses;
- on any allowed-origin `OPTIONS`, it additionally writes max age and configured allowed headers;
- it does not inspect `Access-Control-Request-Method` or `Access-Control-Request-Headers` to enforce a route;
- it does not terminate an `OPTIONS` exchange and it does not implement the advertised application methods.

Therefore place a real route or a deliberately scoped terminal `OPTIONS` handler later in the chain. Test that unsupported methods cannot mutate state even when a CORS header advertises them. A browser refusing to expose a response is not server-side method enforcement.

## Cache and security boundary

Mu adds the lowercase field-name token `Vary: origin` without duplicating an existing case-insensitive Origin token. Preserve it through application handlers, compression, ingress, and caches. This follows Fetch's cache guidance when `Access-Control-Allow-Origin` varies by request origin.

CORS is enforced by conforming browsers. `curl`, backend services, malicious clients, and form/navigation cases outside CORS can still send requests. Keep authentication, authorization, input validation, and CSRF protection independent of the CORS allowlist. A trusted CORS origin is not automatically a trusted CSRF origin; align the lists only when the application's credential and action model justifies both.
