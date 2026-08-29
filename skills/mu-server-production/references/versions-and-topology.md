# Versions and deployment topology

Use this reference for every production task. Inspect the selected artifact's Javadocs and source when it predates an API named here.

## Select the exact line

Mu Server 2.x and 3.x keep the `io.muserver:mu-server` coordinates and `io.muserver` Java packages. Preserve an application's selected version. When choosing one, check both the official download page and Maven Central for a stable non-snapshot release in the requested major; do not copy a snapshot or a version placeholder from source or migration notes.

Production-relevant differences are:

| Concern | Mu Server 2.x | Mu Server 3.x |
| --- | --- | --- |
| Minimum Java | Java 8 | Java 11 |
| Logging API | SLF4J 1.7 | SLF4J 2.0; use an SLF4J 2 provider rather than a 1.7 binding |
| Nullness | Historical annotations | JSpecify annotations can expose new Java-analysis or Kotlin findings |
| Client-certificate policy | A non-null `withClientCertificateTrustManager(...)` requests a certificate optionally. Enforce route-required certificates in a handler after checking `connection().clientCertificate()`. | `withClientCertificateAuthentication(...)` accepts `NONE`, `OPTIONAL`, or `MANDATORY` to make the handshake policy explicit. A trust manager alone remains optional for compatibility. |
| Graceful-stop result | Through 2.4.1, `stop(duration, unit)` returns `false` after a clean drain and `true` after timing out, opposite its Javadoc. | Returns `true` after a clean drain and `false` after timeout, matching the contract. |
| Supplied `SSLContext` | `HttpsConfigBuilder.withSSLContext(...)` is not public in 2.4.1. | It is public; its embedded trust managers validate client certificates. See the TLS reference before combining it with HTTP/2. |

The core production controls otherwise remain deliberately similar: explicit listeners, TLS protocols and ciphers, HTTPS certificate rotation, HTTP/2 over HTTPS, request limits and timeouts, bounded handler execution, rate limiting, HAProxy PROXY protocol, completion/rejection events, `MuStats`, and active-connection inspection.

Features added within 2.x still require an exact-version check. `addRequestRejectListener(...)` arrived in 2.3.1 and `Http2ConfigBuilder.withMaxConcurrentStreams(...)` in 2.3.2; both are present in version 3.

When the task is an upgrade rather than production hardening, use the dedicated upgrade workflow for all behavior changes. This reference covers only differences that change production configuration or operation.

## Choose one topology

### Mu terminates public TLS

Bind the HTTPS listener to the intended interface and fixed port, configure a real server identity, and either disable HTTP with `withHttpPort(-1)` or run a deliberate redirect listener. Mu owns TLS versions, ciphers, ALPN, HSTS, mTLS, and rotation.

### A trusted ingress terminates TLS

Bind Mu to a private address or network and a fixed HTTP port. The ingress owns the public certificate, external ALPN, HSTS, and HTTP-to-HTTPS redirect. Decide separately whether the ingress-to-Mu hop needs TLS. Do not configure Mu's self-signed HTTPS merely to make an internal URI look secure.

If application behavior uses the original scheme, host, or client IP, the ingress must strip untrusted forwarding headers and generate a canonical chain. Restrict direct reachability to Mu so clients cannot bypass that sanitation.

### TLS pass-through or PROXY protocol

With TLS pass-through, Mu owns the public TLS handshake. With HAProxy PROXY protocol, the proxy sends connection metadata before TLS or HTTP begins. Enable it only on a listener reachable exclusively from trusted, correctly configured senders; when enabled, ordinary clients that omit the PROXY preamble cannot connect.

## Bind intentionally

Start from `MuServerBuilder.muServer()` when enabling or disabling connectors explicitly:

```java
MuServerBuilder builder = MuServerBuilder.muServer()
    .withInterface("127.0.0.1")
    .withHttpPort(8080)
    .withHttpsPort(-1);
```

- `withHttpPort(0)` and `withHttpsPort(0)` request an ephemeral port. `httpServer()` and `httpsServer()` select such a port, so they are test conveniences unless a supervisor deliberately discovers the assigned port.
- Port `-1` disables that connector. Starting with both connectors disabled fails.
- A null interface lets the networking stack bind on available interfaces. Use an explicit loopback, private, or wildcard address that matches the deployment design; do not expose a wildcard listener by accident.
- `server.uri()`, `httpUri()`, and `httpsUri()` describe the bound server and are useful for tests and logs. They are not a source of truth for the public authority behind NAT or an ingress.

Inspect container port mappings, service definitions, firewall/security-group policy, health-probe source, and dual-stack behavior along with Java code. A safe Java bind can still be exposed by the platform, and a correct service declaration cannot repair a wildcard listener that bypasses the intended proxy.
