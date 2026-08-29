---
name: mu-server-upgrade
description: >-
  Use when upgrading an application's io.muserver:mu-server dependency, planning a Mu Server major-version migration, or investigating a regression after a version change. Covers exact changelog analysis, dependency and Java compatibility, the 1.x-to-2.x javax-to-jakarta transition, the 2.x-to-3.x platform and behavior changes, and focused verification.
license: MIT
---

# Upgrade a Mu Server application

Upgrade the application with the smallest change set that preserves its intended public HTTP behavior.

## Establish the exact upgrade range

Inspect the declared and resolved Mu Server versions, Java compiler and runtime versions, build files and dependency constraints, bootstrap and shutdown code, handlers, Jakarta REST resources and providers, TLS and HTTP/2 configuration, WebSockets or SSE, and relevant tests. A property, version catalog, parent build, lockfile, or dependency-management section may control the resolved version instead of the nearest declaration.

Preserve a target version chosen by the user. Otherwise select the newest stable `io.muserver:mu-server` release after checking the [Mu Server download page](https://muserver.io/download) and Maven Central.

Read every [official changelog](https://muserver.io/changelog) entry after the resolved source version through the target version. Extract only changes that intersect features the application uses, plus dependency, Java, security, protocol, or default-behavior changes that apply without an explicit API call. Distinguish required source changes from behavior to regression-test and optional new capabilities.

## Route major upgrades

- For 1.x to 2.x, read [1.x to 2.x](references/1-to-2.md).
- For 2.x to 3.x, read [2.x to 3.x](references/2-to-3.md).
- For 1.x to 3.x, read both references in order. Establish compiling Jakarta-based source before diagnosing the Java, logging, and behavior changes introduced by version 3.
- For an upgrade within one major line, use the exact intervening changelog entries rather than applying unrelated major-migration work.

## Make the migration evidence-driven

Before editing, run the existing build and the most relevant tests when the old application can still run. Capture observable contracts that the application or its clients may depend on: status, media type, entity, important headers, exact redirect and `Location` values, cookies, URI decoding, filter or interceptor order, and shutdown results.

Then:

1. Update the Mu Server version and any required Java or logging platform settings.
2. Inspect the resolved dependency graph for application-pinned Netty, SLF4J, Jakarta REST, JSON-provider, or annotation artifacts that override or conflict with Mu Server's transitive versions.
3. Make mechanical namespace or provider changes required by the crossed boundary, then compile early so errors identify remaining affected modules and generated sources.
4. Change application behavior only when the changelog, a failing contract test, or the target API requires it. Keep the existing direct-handler or `RestHandlerBuilder` architecture when it remains supported.
5. Re-run the dependency report, clean build, focused tests, and live HTTP probes. Exercise concurrency or protocol-specific paths when the changed code uses shared singleton state, streaming, HTTP/2, WebSockets, or SSE.

Do not add a direct Jakarta REST API dependency merely to fix missing imports: `io.muserver:mu-server` supplies its supported API transitively. Add or change another dependency only when the application actually uses it and its current artifact is incompatible with the target major line.

## Verify and report

Verify in proportion to the application:

- clean compilation and tests on the target Java version;
- one running-server request for every changed handler or REST contract;
- JSON read and write paths when a provider changed;
- exception, malformed-input, redirect, URI, cookie, and content-negotiation behavior the application exposes;
- TLS, HTTP/2 stream concurrency, WebSocket, upload, async, or SSE behavior when used;
- graceful shutdown and any code that interprets its result;
- the final resolved dependency graph, with no unintended old `javax.ws.rs`, SLF4J binding, or duplicate provider left behind.

Report the source and target Mu Server versions, Java change, dependency and source changes, behavior intentionally preserved or updated, commands and HTTP cases verified, and any changelog item that remains ambiguous for this application.
