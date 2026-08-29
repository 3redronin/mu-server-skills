# TLS and HTTP/2

Use this reference when Mu terminates TLS or when HTTPS behavior is being diagnosed. ACME enrollment and renewal mechanics are outside this skill; consume their resulting identity through the same TLS contract.

## Configure a production server identity

An HTTPS listener without `withHttpsConfig(...)` uses `HttpsConfigBuilder.unsignedLocalhost()`. That certificate is explicitly test-only. Always supply production identity material:

```java
HttpsConfigBuilder tls = HttpsConfigBuilder.httpsConfig()
    .withKeystoreType("PKCS12")
    .withKeystore(new File(keyStorePath))
    .withKeystorePassword(keyStorePassword)
    .withKeyPassword(keyPassword)
    .withProtocols("TLSv1.3", "TLSv1.2");
```

Prefer `char[]` password overloads and the application's secret loader. Do not commit a private-key store or password. Loading from a file or stream reads the keystore into the builder; it does not watch the file for later changes.

Mu defaults to TLS 1.2 and 1.3 and ignores a requested protocol unsupported by the current JDK, failing startup if none remain. Its default cipher selection follows the active TLS provider. Use `withCipherFilter(...)` only to implement a concrete organizational or interoperability policy, start from the provider's default ciphers, and verify the effective result through `server.sslInfo()` and real handshakes. A hard-coded list can break when the JDK/provider changes, and TLS 1.3 cipher configuration is provider-sensitive.

Certificates must contain subject alternative names for every public hostname. With multiple key entries, Mu maps DNS SAN values to aliases for SNI selection; `withDefaultAlias(...)` selects the fallback when SNI is absent or does not match. It does not reject an unknown SNI name or prove hostname coverage. Test every hostname with SNI, including the fallback case, rather than inspecting the keystore alone.

## Choose client-certificate policy

Trust validation authenticates a presented certificate chain; application authorization still decides what that identity may do.

In Mu Server 3, choose a mode explicitly:

```java
tls.withClientCertificateTrustManager(clientTrustManager)
    .withClientCertificateAuthentication(
        ClientCertificateAuthentication.MANDATORY);
```

- `NONE` does not request a certificate and cannot be combined with a non-null builder trust manager.
- `OPTIONAL` accepts a missing certificate but rejects a presented untrusted certificate.
- `MANDATORY` rejects missing and untrusted certificates during the TLS handshake.
- If Mu builds the context from a keystore or key-manager factory, `OPTIONAL` and `MANDATORY` require a builder trust manager.
- With `withSSLContext(...)`, trust managers embedded in that context perform validation. Supplying a builder trust manager retains the historical optional-request switch when no explicit mode is set; it does not replace the context's embedded trust managers.

In Mu Server 2.x, setting `withClientCertificateTrustManager(...)` is optional client authentication. If a route requires a certificate, an earlier application handler must deny a request whose `request.connection().clientCertificate()` is empty. This is an HTTP denial, not a mandatory-certificate TLS handshake. Do not claim 2.x provides `ClientCertificateAuthentication`.

For either line, cast the returned `Certificate` to `X509Certificate` only after checking its type. Authorize stable SAN or fingerprint identities according to application policy, and never log full certificates, private keys, or derived sensitive identity data.

## Redirect HTTP and set HSTS deliberately

When Mu owns both connectors, put `HttpsRedirectorBuilder` before application handlers:

```java
.addHandler(HttpsRedirectorBuilder.toHttpsPort(443)
    .withHSTSExpireTime(180, TimeUnit.DAYS))
```

The supplied handler:

- sends `301` for HTTP `GET` and `HEAD` to the same request authority/path on the configured HTTPS port;
- sends `400` for other HTTP methods rather than replaying a possibly unsafe body;
- adds `Strict-Transport-Security` only to HTTPS responses when an expiry is configured; and
- leaves HTTPS processing to later handlers.

The redirect authority comes from `request.uri()`, which can be influenced by `Host` and forwarding headers. Validate the public authority and proxy trust boundary before using it. If an ingress terminates TLS, prefer the ingress for redirect and HSTS so policy is based on the authenticated external connection.

Enable `includeSubDomains` only when every current and future subdomain is HTTPS-capable. Enable preload only after satisfying and accepting the external preload program's long-lived consequences. These are deployment decisions, not harmless header formatting.

## Enable HTTP/2 with ALPN

HTTP/2 is off unless enabled with a config. In the 2.x/3.x Netty-based implementation it is served only on HTTPS and negotiated with ALPN, with HTTP/1.1 as the fallback:

```java
.withHttp2Config(Http2ConfigBuilder.http2Enabled()
    .withMaxConcurrentStreams(maxConcurrentStreams))
```

Mu Server 2.x requires Java 9 or later for HTTP/2; Mu Server 3's Java minimum already satisfies this. `http2EnabledIfAvailable()` is a Java-version heuristic, not a handshake capability test, so prefer an explicit production choice. `withMaxConcurrentStreams(...)` is available from 2.3.2 and defaults to 200 where present. Size it with the handler concurrency and per-request memory budget; it is per HTTP/2 connection, not a server-wide request cap.

The current `withSSLContext(...)` path builds a JDK Netty context with application-protocol negotiation disabled. Do not assume HTTP/2 works merely because `http2Enabled()` was set; prefer the keystore or key-manager-factory path for ALPN, or prove the selected release's supplied-context behavior with a real `h2` negotiation before deployment.

## Rotate and verify

Build a complete new TLS configuration, then call:

```java
server.changeHttpsConfig(newTlsConfig);
```

If building the replacement fails, Mu retains the old configuration. The replacement applies to new TLS connections; existing keep-alive connections do not renegotiate their established session. Force a fresh connection when verifying the new certificate, cipher policy, or client-auth mode.

Check all of the following from the actual client path:

- certificate chain, SAN hostname validation, expiry, and SNI selection for every name;
- acceptance of intended TLS protocols/ciphers and rejection of disabled ones;
- ALPN selection of `h2` and fallback to HTTP/1.1;
- missing, trusted, and untrusted client-certificate cases; and
- a normal application response before and after rotation.

`SSLInfo.certificates()` discovers a chain by connecting to the server's bound HTTPS URI (normally `localhost` when no interface was supplied), with internal trust and hostname checks disabled, and can return an empty list on failure. It is useful evidence for the default identity, not proof for every SNI name or public-path validation. Monitor the authoritative certificate inventory as well as external handshakes.
