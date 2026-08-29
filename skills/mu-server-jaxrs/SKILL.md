---
name: mu-server-jaxrs
description: Build, extend, or diagnose Jakarta REST applications hosted by mu-server. Use for JAX-RS resources, providers, registration, dependency setup, and HTTP-level tests on mu-server.
---

# Use Jakarta REST with mu-server

Integrate Jakarta REST with the user's existing project rather than replacing its build or application structure.

Inspect the Java version, mu-server version, Jakarta REST imports, dependencies, bootstrap code, and tests before editing. Treat `javax.ws.rs` and `jakarta.ws.rs` as incompatible generations; do not migrate between them unless the user asks or the selected mu-server integration requires it. Confirm artifact names and compatible versions from the project or an authoritative source rather than inventing them.

Implement the smallest complete change, including resource or provider registration and lifecycle handling where required. Preserve the project's conventions for dependency injection, serialization, error handling, and shutdown.

Validate behavior through an HTTP-level test when practical. Cover the externally observable status, headers, and entity relevant to the request, then run the project's documented tests.

Explain any version or namespace compatibility decision in the result, especially when historical JAX-RS and Jakarta REST behavior differs.
