---
name: mu-server-swagger
description: >-
  Use when a Mu Server Jakarta REST application needs Swagger Core v3 annotations from io.swagger.v3.oas.annotations, the io.muserver:mu-swagger or MuOpenApiResourceBuilder integration, help diagnosing why those annotations are absent from its generated document, or a Swagger UI hosted with Mu Server 3's WebJar handler. Integrates annotation metadata into OpenAPI JSON and YAML and connects either Mu OpenAPI generator to Swagger UI while preserving resource registration.
license: MIT
---

# Use Swagger annotations and Swagger UI with Mu Server

Use `mu-swagger` only when Swagger Core annotations are part of the requested documentation contract. Preserve the application's existing Mu Server bootstrap, REST resources, providers, routes, and runtime behavior.

## Choose the documentation path deliberately

| Requirement | Use |
| --- | --- |
| OpenAPI JSON, or a document for Swagger UI, without Swagger Core annotations | Mu Server's built-in `RestHandlerBuilder.withOpenApiJsonUrl(...)`; it adds no Swagger dependency. The optional `withOpenApiHtmlUrl(...)` exposes Mu's small read-only HTML view. |
| `@Operation`, `@Schema`, `@ApiResponse`, or other `io.swagger.v3.oas.annotations` metadata | `io.muserver:mu-swagger` with Swagger Core's Jakarta integration. |
| An interactive browser UI hosted by the application on Mu Server 3 | The `org.webjars:swagger-ui` WebJar served by `ResourceHandlerBuilder.webjarHandler(...)`, pointed at either generator's OpenAPI URL. |
| An externally hosted interactive browser UI | A separate Swagger UI pointed at either generator's OpenAPI URL. |

When the user asks only for OpenAPI output or Swagger UI, prefer Mu Server's built-in generator. When the user explicitly wants Swagger Core annotations or already maintains them, retain that choice and use `mu-swagger`. Mu Server's built-in generator does not interpret Swagger Core annotations.

## Inspect compatibility before editing

Inspect the build tool, Java and Mu Server versions, existing REST handler and singleton resources, current OpenAPI configuration, Swagger annotation imports, JSON providers, context path, authentication, CORS, and tests.

Preserve user-selected versions. Otherwise verify the newest stable `io.muserver:mu-swagger` and `io.swagger.core.v3:swagger-jaxrs2-jakarta` releases in Maven Central. When hosting the UI, also verify the newest stable `org.webjars:swagger-ui` release. If release metadata is unavailable, use `mu-swagger` `0.1.1`, Swagger Core `2.2.41`, and Swagger UI WebJar `5.32.14` as disclosed offline fallbacks.

Check the selected artifact's Java level. `mu-swagger` 0.1.1 is compiled for Java 21, so an application using it must compile and run on Java 21 or later even when its Mu Server version supports an older Java runtime. It is a 0.x library; pin an exact release and expect its API to evolve.

The application must keep its own direct `io.muserver:mu-server` dependency. The Mu Server version in `mu-swagger` is provided compile-time metadata, not a request to downgrade or replace the application's chosen version.

## Implement and verify

Read [annotation-driven integration](references/integration.md) before adding dependencies, annotations, the document resource, metadata, or Swagger UI connectivity.

Keep resource objects application-owned singletons. Pass the same resource instances to `RestHandlerBuilder` and `MuOpenApiResourceBuilder`; `mu-swagger` documents them but does not change their lifecycle or discover application dependencies.

After editing:

1. Run the clean build on the required Java version and inspect the resolved dependency graph for the selected Mu Server, `mu-swagger`, the Jakarta Swagger Core artifact, and one Jakarta REST API generation.
2. Start the application and call an unchanged API endpoint to prove documentation work did not alter runtime behavior.
3. Fetch `/openapi.json` and `/openapi.yaml`. Assert `200`, their media types, parseability, metadata, paths, operations, parameters, responses, schemas, and security declarations that the application intentionally documents.
4. If a browser UI is in scope, load its entry page, confirm it fetches the intended document rather than the WebJar's example document, and verify one real request. Test CORS only when the UI has a different origin.

Report the generator chosen and why, exact dependency and Java versions, registered resource instances, document URLs, how the UI is hosted, and the build and HTTP checks performed.
