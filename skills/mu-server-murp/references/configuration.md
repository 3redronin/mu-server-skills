# Murp configuration and behavior

Murp is a reverse-proxy handler for Mu Server. Its authoritative documentation is [muserver.io/murp](https://muserver.io/murp), with source and tests in the [Murp repository](https://github.com/3redronin/murp).

## Dependencies and compatibility

Applications need direct dependencies on both their selected `io.muserver:mu-server` release and an exact `io.muserver:murp` release. Murp 1.2.2 is the current stable release as of 29 August 2026 and is compiled for Java 11. Its POM marks Mu Server 2.2.10 as `provided`, so it does not choose or supply the application's Mu Server runtime. Compile and integration-test the exact pair selected by the application, especially when their major versions differ.

Murp uses the JDK `java.net.http.HttpClient` for target connections and SLF4J for logging. Let the application retain its chosen SLF4J provider; do not add a logging implementation solely because Murp uses the API. Inspect dependency convergence so the selected SLF4J API and provider generations remain compatible, particularly in a Mu Server 2.x application.

## Proxy all requests to a fixed origin

`UriMapper.toDomain(...)` preserves the incoming raw path and query but ignores any path and query on the supplied target URI. Give it an origin, not a base-path URI:

```java
URI targetOrigin = URI.create("http://127.0.0.1:9090");

MuServer server = MuServerBuilder.httpServer()
    .withHttpPort(8080)
    .addHandler(ReverseProxyBuilder.reverseProxy()
        .withUriMapper(UriMapper.toDomain(targetOrigin))
        .withViaName("edge-proxy")
        .withTotalTimeout(30, TimeUnit.SECONDS))
    .start();
```

The proxy is a handler, so earlier handlers may satisfy local routes. A handler that mutates a request or response and returns `false` also lets Murp continue processing it.

## Route selectively

A mapper returns a target `URI` to proxy or `null` to fall through. Preserve raw encoding and query strings explicitly. This example proxies only `/backend` and descendants while retaining that prefix at the target:

```java
URI targetOrigin = URI.create("http://127.0.0.1:9090");

UriMapper backendOnly = request -> {
    String rawPath = request.uri().getRawPath();
    if (!(rawPath.equals("/backend") || rawPath.startsWith("/backend/"))) {
        return null;
    }
    URI target = targetOrigin.resolve(Murp.pathAndQuery(request.uri()));
    if (!targetOrigin.getScheme().equalsIgnoreCase(target.getScheme())
        || !targetOrigin.getRawAuthority().equals(target.getRawAuthority())) {
        throw new IllegalArgumentException("Mapped target escaped the allowed origin");
    }
    return target;
};

MuServer server = MuServerBuilder.httpServer()
    .withHttpPort(8080)
    .addHandler(ReverseProxyBuilder.reverseProxy()
        .withUriMapper(backendOnly))
    .addHandler(Method.GET, "/health", (request, response, pathParams) ->
        response.write("healthy"))
    .start();
```

Keep the target origin fixed or select it from an application-owned allowlist. Never turn a query parameter, arbitrary `Host`, or client-supplied absolute URI directly into the target. For prefix stripping or base-path addition, construct the new raw path intentionally and test root, trailing-slash, encoded-separator, dot-segment, and query cases; `URI.resolve(...)` with a leading slash replaces the target's existing path.

Handler order and mapper rules are both observable contracts. In the example, `/health` reaches the later local handler because the mapper returns `null`; a broad `toDomain(...)` mapper placed first would consume it.

## Configure target TLS and connection timeout

If no client is supplied, Murp builds one with `createHttpClientBuilder(true)`, which trusts target certificates. For production HTTPS targets, supply a validating client:

```java
HttpClient targetClient = ReverseProxyBuilder.createHttpClientBuilder(false)
    .connectTimeout(Duration.ofSeconds(5))
    .build();

ReverseProxyBuilder proxy = ReverseProxyBuilder.reverseProxy()
    .withUriMapper(UriMapper.toDomain(URI.create("https://service.internal")))
    .withHttpClient(targetClient)
    .withTotalTimeout(30, TimeUnit.SECONDS);
```

The helper also disables automatic redirect following, so target redirects are returned to the client. If the application supplies another `HttpClient`, retain certificate and hostname verification, redirect policy, proxy selection, authenticator, executor, and HTTP-version choices deliberately.

`withTotalTimeout(...)` covers the full exchange, including body streaming, and defaults to five minutes. The HTTP client controls connection establishment timeout. DNS and lower-level connection behavior depend on the JDK and platform; Murp does not expose a separate idle-timeout setting.

## Handle client certificates on both TLS legs

A Murp deployment can have two independent mutual-TLS relationships:

| TLS connection | Client certificate presented by | Configuration point |
| --- | --- | --- |
| External client to Mu Server | The external client | Mu Server's `HttpsConfigBuilder` |
| Murp to an HTTPS target | The proxy application | The JDK `HttpClient` supplied with `withHttpClient(...)` |

Murp terminates the first TLS connection and creates the second. It cannot pass the original TLS session through, and the proxy never receives the external client's private key. Give the proxy its own client certificate when the target requires mTLS.

### Authenticate clients at the Mu Server listener

Load the CA certificates that may issue client identities into a `TrustManager`, following the [Mu Server client-certificate guide](https://muserver.io/client-certs), and attach it to the server's existing HTTPS configuration.

Mu Server 3 makes the handshake policy explicit:

```java
HttpsConfigBuilder httpsConfig = existingServerHttpsConfig
    .withClientCertificateTrustManager(partnerTrustManager)
    .withClientCertificateAuthentication(
        ClientCertificateAuthentication.MANDATORY);

MuServer server = MuServerBuilder.httpsServer()
    .withHttpsPort(8443)
    .withHttpsConfig(httpsConfig)
    .addHandler(proxy)
    .start();
```

Use `MANDATORY` when every client must present a trusted certificate: a missing or untrusted certificate fails the TLS handshake before a request reaches Murp. Use `OPTIONAL` only when the same listener intentionally serves clients with and without certificates; a presented but untrusted certificate is still rejected. `NONE` does not request a certificate. Merely setting `withClientCertificateTrustManager(...)` without an explicit mode remains optional for compatibility.

This example assumes Mu Server builds the server-side `SSLContext` from the builder's key-store or key-manager configuration. If the application uses `withSSLContext(...)`, initialize that context with the client-certificate trust managers itself; `withClientCertificateTrustManager(...)` does not replace trust managers embedded in a supplied context. In Mu Server 3, set `MANDATORY` or `OPTIONAL` explicitly. In Mu Server 2.x, a non-null builder trust-manager setting enables optional client authentication while the supplied context's embedded trust managers perform the validation.

Mu Server 2.x has no explicit authentication-mode method. Setting `withClientCertificateTrustManager(...)` requests client certificates optionally. If a Mu Server 2.x route requires a certificate, place a handler before Murp that checks `request.connection().clientCertificate()`, returns an application-appropriate denial such as `403` when it is empty, and otherwise returns `false` so Murp runs. This rejects the HTTP request rather than rejecting the TLS handshake.

`request.connection().clientCertificate()` exposes the first peer certificate as an `Optional<Certificate>`. Cast it to `X509Certificate` only after checking its type. Trust validation authenticates that the certificate satisfies the configured trust manager; it does not decide whether that identity may use a particular route. Perform application authorization against stable, application-owned identity rules such as an allowlisted SAN or certificate fingerprint. Keep CA keys, trust stores, client keys, passwords, certificate contents, and derived identities out of logs.

### Present the proxy's certificate to an mTLS target

Initialize the target client's `SSLContext` with both key managers for the proxy identity and trust managers that validate the target. Load the key stores and passwords from the application's secret-management mechanism rather than embedding them in source:

```java
KeyManagerFactory proxyIdentity = KeyManagerFactory.getInstance(
    KeyManagerFactory.getDefaultAlgorithm());
proxyIdentity.init(proxyClientKeyStore, proxyClientKeyPassword);

TrustManagerFactory targetTrust = TrustManagerFactory.getInstance(
    TrustManagerFactory.getDefaultAlgorithm());
targetTrust.init(targetTrustStore); // use null here only to select the JDK's default roots

SSLContext targetTls = SSLContext.getInstance("TLS");
targetTls.init(
    proxyIdentity.getKeyManagers(),
    targetTrust.getTrustManagers(),
    null);

HttpClient targetClient = ReverseProxyBuilder.createHttpClientBuilder(false)
    .sslContext(targetTls)
    .connectTimeout(Duration.ofSeconds(5))
    .build();

ReverseProxyBuilder proxy = ReverseProxyBuilder.reverseProxy()
    .withUriMapper(UriMapper.toDomain(URI.create("https://service.internal")))
    .withHttpClient(targetClient)
    .withTotalTimeout(30, TimeUnit.SECONDS);
```

The identity key store must contain the proxy's private key and certificate chain. The target trust store must contain suitable trust anchors for the target server; it is a different role from the partner CA trust used on the public listener. Supplying a custom `SSLContext` makes its trust managers responsible for target validation. Retain JDK hostname verification and do not substitute a trust-all manager.

### Forward an authenticated downstream identity only when needed

The HTTPS target sees the proxy's mTLS certificate, not the external client's certificate. If it also needs the external identity, authorize that certificate in a handler before Murp, store a minimal derived identity in a request attribute, and overwrite an application-specific header in the request interceptor:

```java
.withRequestInterceptor((clientRequest, targetRequest) ->
    targetRequest.setHeader(
        "X-Authenticated-Partner",
        (String) clientRequest.attribute("authenticated-partner")))
```

`setHeader(...)` replaces any caller-supplied value already copied by Murp; `header(...)` would append and could leave a spoofed value. Ensure the attribute can only be set after successful authentication and authorization, and ensure the target accepts this header only from the authenticated proxy or a protected network path. Prefer a short opaque identity over forwarding an entire certificate. If a certificate must be forwarded, define its encoding and size limit, treat it as sensitive data, and test duplicate and oversized inputs.

## Set forwarding and Host policy

Murp filters standard hop-by-hop headers and names listed by a `Connection` header in both directions. It appends `Via` and an RFC 7239 `Forwarded` element. Choose a meaningful `withViaName(...)`; its default is `private`.

By default, existing client `Forwarded` values are retained before Murp's value. At an internet-facing or otherwise untrusted edge, use:

```java
.discardClientForwardedHeaders(true)
```

This prevents a caller from supplying a false earlier hop. Preserve incoming forwarding values only when the immediate upstream is trusted and their chain is part of the application's security model.

Legacy `X-Forwarded-Proto`, `X-Forwarded-Host`, and `X-Forwarded-For` are disabled by default. Enable them only for a target that requires them:

```java
.sendLegacyForwardedHeaders(true)
```

The original client `Host` is proxied by default where the JDK permits it. Keep that when the target routes by the public host. Use `.proxyHostHeader(false)` when the target expects its own authority, commonly with a different HTTPS virtual host. Verify the target-observed value; do not infer it from the client-side request.

## Customize and observe

`withRequestInterceptor(...)` can change the prepared target request's headers. It cannot inspect or replace the streamed request body. An unhandled request-interceptor exception results in a `500` response.

`withResponseInterceptor(...)` can change the as-yet-unsent client status or headers after target headers arrive. It cannot inspect or replace the streamed response body. An exception is logged and the target response continues.

Use `addProxyCompleteListener(...)` for completion timing and final status, or `Slf4jResponseLogger` for the supplied access-style log. `withProxyListener(...)` exposes request and response body chunk lifecycle and error callbacks. Chunk buffers are valid for synchronous observation only; copy bytes before retaining them or passing them to asynchronous work, and avoid body logging unless data sensitivity and volume are explicitly acceptable.

## Preserve streaming and failure semantics

Murp streams request and response bodies asynchronously rather than buffering them for transformation. It supports ordinary HTTP/1.1 and HTTP/2 proxy combinations and streaming responses such as server-sent events. Request and response interceptors are therefore header/status hooks, not body filters.

Before the client response starts, a target transport failure produces `502 Bad Gateway` and a total timeout produces `504 Gateway Timeout`. If headers or body bytes have already been sent, Murp terminates the client response or HTTP/2 stream because the status can no longer be replaced. Tests should distinguish these state transitions.

Murp is an HTTP reverse proxy, not a WebSocket or `CONNECT` tunnel. Connection-specific `Upgrade` headers are filtered as hop-by-hop headers.
