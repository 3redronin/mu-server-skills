# Annotation-driven OpenAPI with mu-swagger

Use this integration when the application needs Swagger Core v3 annotations. The authoritative project documentation and examples are in the [mu-swagger repository](https://github.com/3redronin/mu-swagger).

## Dependencies

The application owns three direct dependencies:

- its selected `io.muserver:mu-server` release;
- the selected `io.muserver:mu-swagger` release;
- a compatible `io.swagger.core.v3:swagger-jaxrs2-jakarta` release.

Use the `-jakarta` Swagger Core artifact because Mu Server 2.x and 3.x use `jakarta.ws.rs`. Do not substitute `swagger-jaxrs2`, which targets the old `javax.ws.rs` namespace. `swagger-jaxrs2-jakarta` supplies the Swagger Core v3 annotations under `io.swagger.v3.oas.annotations`; do not migrate code to the legacy `io.swagger.annotations` package.

`mu-swagger` already brings supporting libraries such as the Servlet API transitively. Do not add those implementation details directly unless the application itself imports them. Inspect dependency convergence when the application pins Jackson, SLF4J, Jakarta REST, or Swagger Core components.

## Register the document resource

Create the Mu Server builder first, retain the actual singleton resources in one collection, and give that same collection to the REST handler and document builder:

```java
MuServerBuilder serverBuilder = MuServerBuilder.httpServer()
    .withHttpPort(8080);

List<Object> resources = List.of(new GreetingResource(greetingService));

OpenAPI definition = new OpenAPI().info(
    new Info()
        .title("Greeting API")
        .description("Greeting endpoints")
        .version("1.0.0"));

MuOpenApiResource openApiResource = MuOpenApiResourceBuilder.muOpenApiResource()
    .withResources(resources)
    .withOpenApi(definition)
    .build();

RestHandlerBuilder api = RestHandlerBuilder.restHandler(resources.toArray())
    .addResource(openApiResource);

MuServer server = serverBuilder
    .addHandler(api)
    .start();
```

The added resource serves `GET /openapi.json` as `application/json` and `GET /openapi.yaml` as `application/yaml`. The URLs are defined by `MuOpenApiResource`; do not also configure Mu Server's built-in document at `/openapi.json`. If both generators must temporarily coexist during a migration, mount or configure them at distinct paths and compare their output explicitly.

`withOpenApi(...)` seeds document-level metadata such as `Info`, servers, and components; Swagger Core appends the resource paths and discovered components. When multiple Swagger OpenAPI contexts coexist in one process, give each builder a distinct `withContextId(...)` value and isolate their routes.

## Add Swagger Core v3 annotations

Jakarta REST annotations continue to define routing and runtime behavior. Swagger annotations describe that behavior; they do not implement validation, authorization, serialization, or response handling.

```java
@Path("/hello")
@Produces(MediaType.TEXT_PLAIN)
final class GreetingResource {
    @GET
    @Path("/{name}")
    @Operation(summary = "Greet a caller")
    @ApiResponse(responseCode = "200", description = "Greeting returned")
    public String greet(
        @Parameter(description = "Name to greet", required = true)
        @PathParam("name") String name) {
        return "Hello, " + name;
    }
}
```

Use `@Schema` on model types or properties and `@Content(schema = ...)` when inference is insufficient. Add only metadata the application can keep accurate. In particular, Swagger security schemes and requirements document authentication but do not enforce it; retain or implement the actual Mu Server request filters separately.

A runtime JSON reader/writer is also separate from documentation generation. Register the application's provider with `addCustomReader(...)` and `addCustomWriter(...)` when API endpoints exchange objects. `mu-swagger` does not become the application's JSON serializer.

## Connect a Swagger UI

`mu-swagger` does not bundle or serve Swagger UI assets. Point an existing, separately hosted UI at `/openapi.json` or `/openapi.yaml`.

No CORS configuration is needed when the UI and API have the same origin. For a UI on another origin, allow only the required origin and headers on the REST handler, for example:

```java
RestHandlerBuilder api = RestHandlerBuilder.restHandler(resources.toArray())
    .addResource(openApiResource)
    .withCORS(CORSConfigBuilder.corsConfig()
        .withAllowedOrigins("https://docs.example.com")
        .withAllowedHeaders("content-type", "authorization"));
```

Because this permits browser access to the API as well as its document, match the CORS policy to the UI's actual operations. Protect or disable documentation endpoints if exposing the API description would violate the application's deployment policy.
