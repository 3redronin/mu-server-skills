# Production operation and verification

Read this reference for a public rollout, issuance or renewal failure, forced renewal, domain or CA change, multiple replicas, or verification of a real certificate.

Re-check current CA behavior in Let's Encrypt's [challenge types](https://letsencrypt.org/docs/challenge-types/), [staging environment](https://letsencrypt.org/docs/staging-environment/), [rate limits](https://letsencrypt.org/docs/rate-limits/), and [integration guide](https://letsencrypt.org/docs/integration-guide/) before a real order; these service policies can change independently of `mu-acme`.

## Preflight the public path

For every configured name:

1. Resolve A and AAAA records from outside the deployment. Remove or fix any published address that cannot reach the service; the CA may validate through it. Check that any CAA records authorize the chosen CA.
2. Confirm public TCP 80 reaches this application's exact `/.well-known/acme-challenge/` path without authentication, a generic redirect running first, a fallback response, caching, or path rewriting. HTTP-01 is validated on public port 80 even if Mu listens on another internally forwarded port.
3. Confirm public TCP 443 reaches the HTTPS listener and outbound TCP 443 reaches the ACME directory. Do not allowlist guessed CA validator IP ranges; Let's Encrypt does not publish a stable range.
4. Confirm the config directory is durable, writable by exactly the runtime identity that needs it, and unique to this staging/production environment and exact SAN set.

Let's Encrypt follows limited HTTP-01 redirects to HTTP or HTTPS on ports 80 or 443 and does not validate the certificate on an HTTPS redirect during bootstrapping. The direct Mu challenge handler is still the clearest path: keep it before the HTTPS redirector.

Use staging first. Staging creates a separate ACME account and an intentionally untrusted chain. Never copy its `cert-chain.crt` into the production config directory. More generally, changing `withDomain(...)` or the ACME server while retaining an unexpired chain will not trigger a new order: `mu-acme` 2.0.1 checks expiry, not issuer, endpoint, or SAN equality.

## Understand renewal and failure behavior

`start(server)` schedules a check immediately and then every 24 hours. In 2.0.1 source, a new order is requested when any certificate in the loaded chain expires before now plus seven days. The interface Javadocs and Mu Server integration page still say three days; the implementation and its 2019 change history establish seven days.

The manager has no health API, metrics callback, configurable schedule, or configurable renewal window. Monitor both its SLF4J logs and the certificate actually presented by the public endpoint. Alert with enough lead time to diagnose DNS, port 80, storage, account, clock, and CA failures before the seven-day window closes.

On background failure:

- a `CertificateOrderException` is logged at WARN by message only;
- other exceptions are logged at WARN with a stack trace;
- the daily scheduler remains alive, while the currently installed certificate—or first-start self-signed identity—continues to be served;
- there is no immediate general retry loop after the task returns.

The 2.0.1 `AcmeRetryAfterException` path subtracts epoch milliseconds from epoch seconds, so a CA `Retry-After` is effectively clamped to the implementation's 500 ms minimum rather than honored accurately. Treat rate-limit responses as an operational stop signal, use staging for diagnosis, and do not depend on this internal retry path.

`forceRenew()` is synchronous, requires `start(server)` to have been called, and creates a new order even when the current certificate is healthy. Use it only for a deliberate operator action after fixing the cause and checking current CA limits. Never put it in startup, readiness, request handling, or an automated retry loop.

`changeHttpsConfig` swaps the complete TLS context for new connections. Current `mu-acme` recreates that context with its certificate key manager only; protocol, cipher, client-certificate, or other settings that application code added to the initially returned builder are not reapplied by automatic renewal. Keep hardening design in `mu-server-production`, but explicitly account for this replacement limitation and regression-test the post-renewal TLS policy. An external certificate manager or a focused upstream change may be more suitable when custom TLS policy must survive every rotation.

## Design one certificate writer

An `AcmeCertManager` keeps only its current HTTP-01 token and response in process memory. Its three config files use fixed names, plain `FileWriter` updates, and no inter-process locks or change watcher. Sharing one directory among active managers does not coordinate orders or refresh the TLS contexts of replicas that did not perform the renewal.

For multiple replicas, prefer one explicitly elected issuer with stable persistent storage, route every challenge request to that issuer, then distribute the resulting certificate and private key through an intentional secret-delivery and per-replica reload mechanism. Protect that challenge route and key distribution boundary.

If each replica runs an independent manager, each needs independent durable state and challenge routing must guarantee that every CA validation request reaches the manager holding the matching in-memory token. Ordinary round-robin routing does not provide that guarantee. For a platform requiring shared challenges, leader election, atomic secret distribution, or wildcard DNS-01, choose infrastructure designed for those requirements rather than assuming `mu-acme` supplies them.

## Verify without disabling trust

Local deterministic tests can verify dependency resolution, disabled-mode startup, application routes, handler construction/order, and clean manager/server shutdown without contacting a CA. They cannot prove public DNS, CA validation, or production issuance.

For a staging issuance, verify hostname and chain using an isolated test trust store containing only the current official Let's Encrypt staging root needed for the test. Never add staging roots to an ordinary system/browser trust store; staging chains are intentionally untrusted and can change.

For production, use a fresh external connection and the normal platform trust store. For example:

```bash
curl --fail --show-error --silent https://example.com/health
openssl s_client \
  -connect example.com:443 \
  -servername example.com \
  -verify_hostname example.com \
  -verify_return_error </dev/null
```

Check the served leaf SANs, issuer and chain, `notBefore`/`notAfter`, verification result, and an application response. After renewal, force a new TCP/TLS connection and confirm the serial or validity changed. Never use `curl -k`, a permissive hostname verifier, or a trust-all manager as evidence of successful external issuance.

Report whether the check was local disabled mode, staging with scoped trust, or production with default trust; the exact public names and endpoints checked; the certificate validity; and any unverified routing, replica, or persistence assumption.
