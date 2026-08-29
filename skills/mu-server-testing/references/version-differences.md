# Version-sensitive testing contracts

Read this when the application targets Mu Server 2.x, Mu Server 3, or both.

## Stable setup

Both 2.4.1 and Mu Server 3 use `io.muserver:mu-server`. `MuServerBuilder.httpServer()` configures HTTP on port 0, and `httpsServer()` configures HTTPS on port 0. Start first and use the returned server URI. Mu Server's own `src/test/java/scaffolding` helpers are not published application APIs in either line.

## Mu Server 3

Treat Mu Server 3 as released. It requires Java 11 or later, uses SLF4J 2, and adds JSpecify nullness annotations. Tests and application code should handle nullable results such as `httpUri()` when only HTTPS is configured and `httpsUri()` when only HTTP is configured. `uri()` returns HTTPS when available and otherwise HTTP after startup.

Mu Server 3 corrected `MuServer.stop(duration, unit)` to match its documented contract: `true` after a clean drain and `false` when requests outlive the deadline or shutdown fails.

## Mu Server 2.4.1

The timed-stop implementation returns the opposite boolean: `false` after a clean drain and `true` when in-flight requests exceed the deadline. Assert the actual request and connection outcomes as the primary contract, and isolate any version-specific boolean expectation so it changes deliberately during upgrade.

Do not select historical `io.muserver:mu3`/`0.0.3.x` artifacts when a task says Mu Server 3. Keep the application's exact selected `io.muserver:mu-server` version; if no final v3 artifact version is supplied by the project or user, avoid inventing one.
