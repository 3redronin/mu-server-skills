---
name: mu-server-acme
description: >-
  Use when adding, configuring, operating, troubleshooting, or testing io.muserver:mu-acme in an embedded Mu Server application for ACME HTTP-01 certificate issuance and automatic HTTPS renewal. Covers Let's Encrypt staging and production, challenge routing, persistent keys, startup and shutdown, certificate hot-reload, local disablement, multi-replica constraints, rate-limit-aware operation, and trusted external verification.
license: MIT
---

# Use ACME certificates with Mu Server

Integrate `mu-acme` into the application's existing Mu Server and lifecycle. Preserve its build, package, handlers, ports, shutdown model, Mu Server version, and deployment topology unless the request changes them.

## Establish the certificate boundary

Inspect the Java and Mu Server versions, resolved SLF4J API and provider, HTTP and HTTPS listeners, proxy or load-balancer path, handler order, requested DNS names, persistent storage, replicas, and tests. Determine whether the task is local-only, staging, or production.

This skill owns embedded HTTP-01 enrollment, renewal, and certificate activation. Route general protocol, cipher, HSTS, mTLS, and listener hardening to `mu-server-production`; route application authentication and fallback behavior to the relevant handler or REST work while preserving the ACME exception described below.

Read [artifact and logging compatibility](references/compatibility.md) when choosing or changing dependency versions, targeting Mu Server 3, retaining Java 8, resolving SLF4J conflicts, or building an uber JAR. Keep direct dependencies on both `io.muserver:mu-server` and `io.muserver:mu-acme`: the server dependency in `mu-acme` is `provided` and does not supply the application runtime.

## Check whether HTTP-01 fits

`mu-acme` supports HTTP-01 only. Add each exact DNS name with a separate `withDomain(...)`; the manager requests one SAN certificate and every name must validate. HTTP-01 cannot issue wildcard certificates, so a wildcard or DNS-01 requirement needs a different ACME client.

Before a real order, confirm that every configured A and AAAA record reaches this deployment, public inbound TCP 80 reaches the Mu HTTP handler, public inbound 443 reaches Mu HTTPS, and the manager can make outbound HTTPS connections to the ACME service. A private alternate HTTP listener is fine only when the public edge forwards port 80 without intercepting the challenge path.

Use `letsEncryptStaging()` while proving DNS, routing, persistence, and lifecycle. Switch deliberately to `letsEncrypt()` only for trusted production certificates. Use a different persistent config directory for staging, production, and each exact domain set; the implementation uses fixed filenames and decides renewal from expiry, not from the configured CA or SAN set.

## Preserve the lifecycle sequence

Use the current API name `createHttpsConfig()`. The repository README still contains the removed `createSSLContext()` name.

```java
AcmeCertManager certManager = (production
        ? AcmeCertManagerBuilder.letsEncrypt()
        : AcmeCertManagerBuilder.letsEncryptStaging())
    .withDomain("example.com")
    .withDomain("www.example.com")
    .withConfigDir("/var/lib/example/acme/"
        + (production ? "production" : "staging") + "-example-com")
    .disable(localMode)
    .build();

MuServer server = MuServerBuilder.muServer()
    .withHttpPort(80)
    .withHttpsPort(443)
    .withHttpsConfig(certManager.createHttpsConfig())
    .addHandler(certManager.createHandler())
    .addHandler(HttpsRedirectorBuilder.toHttpsPort(443))
    .addHandler(applicationHandler)
    .start();

certManager.start(server);
```

Keep this order:

1. Build the manager and call `createHttpsConfig()` before starting Mu Server.
2. Add `createHandler()` before redirects, authentication, and catch-all handlers so the active `/.well-known/acme-challenge/<token>` request is answered on HTTP.
3. Start Mu Server, then call `certManager.start(server)`; the manager needs the started server to install a newly issued configuration.
4. Call `start` exactly once. On application shutdown, call `certManager.stop()` before stopping the server; it waits up to 30 seconds for an in-flight renewal, so the surrounding shutdown must still account for work that outlives that wait. Build a new manager rather than trying to restart a stopped one.

Mu Server's `MuHandler` contract and current dispatcher execute handlers strictly in registration order. A stale sentence in `MuServerBuilder.addHandler` Javadocs says async handlers are reordered first; `handleAsync()` changes completion ownership, not handler position. Any earlier synchronous or asynchronous handler can consume the request, so put the ACME handler first and also verify that the ingress, WAF, and any server-level limiter allow the challenge.

On the first start, no `cert-chain.crt` exists, so `createHttpsConfig()` returns Mu Server's self-signed localhost configuration. The server becomes reachable before the immediate background order completes; normal clients must reject that temporary identity. Gate production readiness or traffic accordingly rather than weakening client trust.

After issuance or renewal, the manager calls `MuServer.changeHttpsConfig(...)`. New TLS connections use the new certificate; established TLS connections retain their negotiated session, so renewal verification must open a fresh connection. A failed HTTPS-config replacement leaves the old config in use.

## Preserve files and local behavior

The config directory contains:

- `acme-account-key.pem`: the ACME account private key;
- `domain-key.pem`: the certificate private key, reused for later orders;
- `cert-chain.crt`: the served certificate chain.

Put it on durable runtime-owned storage, outside source control and immutable images. Restrict access and back up the keys and chain together; on POSIX systems, pre-create a `0700` directory and use an effective umask that creates private-key files as `0600`. The library creates ordinary files under the process umask; it does not enforce private POSIX modes, encrypt private keys, lock files, or write them atomically.

For local mode, `.disable(true)` or `noOpManager()` returns a manager whose start, stop, and renewal methods are no-ops, whose handler is `null` (accepted by `addHandler`), and whose HTTPS config is self-signed localhost. This disables CA calls, not the HTTPS connector. Branch the listener configuration separately when the requested local mode is HTTP-only.

## Operate and verify

Read [production operation and verification](references/operations.md) when deploying publicly, diagnosing issuance or renewal, considering `forceRenew()`, changing the domain set or ACME environment, using multiple replicas, or verifying a real certificate.

For every implementation, compile on the selected Java version and inspect the resolved Mu Server, `mu-acme`, acme4j, Bouncy Castle, SLF4J API, and provider. Exercise local/disabled startup without contacting a CA; verify unchanged application routes and shutdown. For public testing, report staging and production separately and never claim an external certificate was issued unless a real default-trusting or explicitly scoped staging-trust client verified it.
