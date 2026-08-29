# Artifact, Java, and logging compatibility

Read this reference only when selecting or changing versions, targeting Mu Server 3, retaining Java 8, resolving logging, or packaging a bundled JAR.

## Select published artifacts

Preserve versions selected by the user or an existing application when they satisfy the requested Java and logging line. Otherwise verify [Maven Central publication data](https://central.sonatype.com/) and matching official source tags; do not copy snapshot versions from repository POMs.

As verified on 2026-08-29:

| Artifact | Release facts | Runtime implications |
| --- | --- | --- |
| `io.muserver:mu-acme:2.0.1` | Latest published `mu-acme`; source tag `mu-acme-2.0.1` | Java 11 bytecode, SLF4J 2.0.17 API, acme4j 3.5.1 and Bouncy Castle transitively; Mu Server 2.1.18 is `provided`. |
| `io.muserver:mu-acme:1.0.0` | Last Java 8 line | Java 8 bytecode, SLF4J 1.7.36 and acme4j 2.16. Retain only when the application must stay on Java 8, after reviewing the older dependency line. |

Mu Server 3 is released and keeps the `io.muserver:mu-server` coordinates and `io.muserver` packages. Its product major is not a Maven version to guess: never substitute an invented `3.0.0`, change the artifact to `mu3`, or derive the final version from legacy tags. Preserve an existing or user-selected exact v3 version. For a new v3 project without one, resolve the stable version from the official Mu Server 3 release notes and published artifacts; if an exact artifact version still cannot be established, report selection as unresolved rather than naming one.

`mu-acme` 2.0.1 was compiled against Mu Server 2.1.18 as a provided dependency, but the integration APIs it calls—`HttpsConfigBuilder`, `MuHandler`, `MuServer.changeHttpsConfig`, and the builder listener/handler methods—remain in the Mu Server 3 release source. Compile and run the application's local disabled path against the exact selected Mu Server artifact rather than treating the provided version as a forced downgrade or an unbounded compatibility guarantee.

## Resolve logging deliberately

`mu-acme` logs acquisition and renewal through SLF4J and does not ship a runtime provider; its `slf4j-simple` dependency is test scope.

- With `mu-acme` 2.x or Mu Server 3, resolve one SLF4J 2.x API and one application-chosen SLF4J 2 provider.
- Mu Server 2.x was compiled against SLF4J 1.7. Adding `mu-acme` 2.x commonly resolves SLF4J API 2.x; an old 1.7 binding is not a 2.x provider and may leave renewal logs unbound. Upgrade or replace the binding, then prove startup and renewal messages are visible.
- With a deliberately retained Java 8 / `mu-acme` 1.0.0 application, keep one compatible SLF4J 1.7 binding unless a broader logging migration is requested.

Inspect the actual dependency graph. Avoid adding `slf4j-simple` merely because it appears in `mu-acme` tests; use the application's existing provider when compatible.

## Preserve the small dependency boundary

Declare only Mu Server and `mu-acme` for the integration itself. `mu-acme` already supplies acme4j and its Bouncy Castle dependencies, and its manager constructor registers `BouncyCastleProvider`; the old README's explicit provider registration is unnecessary.

When an uber JAR strips dependency signatures, exclude only invalidated `META-INF/*.SF`, `*.DSA`, and `*.RSA` signature files as required by the chosen packaging plugin. First prefer the project's existing packaging convention and verify the built JAR starts; do not add a shading plugin to an application that already has a working distribution format.
