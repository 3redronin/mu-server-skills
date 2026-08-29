# Optional Jakarta REST configuration

Use only the sections needed by the request. Every resource and provider shown here is an application-owned singleton and should be safe for concurrent use.

Start from an initialized `MuServerBuilder`. In a new application, call `MuServerBuilder.httpServer()` before constructing JAX-RS providers or responses: loading the server builder installs Mu Server's Jakarta REST `RuntimeDelegate`. This ordering is required before `problemDetailsExceptionMapper().build()` in mu-server 2.4.1. The normal server bootstrap handles it; an application should not need to call `MuRuntimeDelegate.ensureSet()` itself.

## Multiple resources

Attach all API resources to one REST handler:

```java
GreetingResource greetings = new GreetingResource(greetingService);
StatusResource status = new StatusResource(statusService);

RestHandlerBuilder api = RestHandlerBuilder.restHandler(greetings, status);
serverBuilder.addHandler(api);
```

`RestHandlerBuilder.restHandler(greetings).addResource(status)` is equivalent.

## JSON readers and writers

After adding a compatible Jackson Jakarta REST provider dependency, register the same provider instance for the directions the API uses:

```java
JacksonJsonProvider json = new JacksonJsonProvider();
RestHandlerBuilder api = RestHandlerBuilder.restHandler(resources)
    .addCustomReader(json)
    .addCustomWriter(json);
```

Register only a reader or writer when only one direction is required. Mu Server does not discover the provider from `@Provider` or the classpath.

## Exception mapping and RFC 9457

Register a custom mapper instance against the exception class it handles:

```java
RestHandlerBuilder api = RestHandlerBuilder.restHandler(resources)
    .addExceptionMapper(ValidationException.class, validationExceptionMapper);
```

mu-server 2.3.0 and later include an RFC 9457 problem-details mapper. In mu-server 2.4.1 it is opt-in:

```java
import io.muserver.rest.ProblemDetailsExceptionMapperBuilder;

MuServerBuilder serverBuilder = MuServerBuilder.httpServer();
RestHandlerBuilder api = RestHandlerBuilder.restHandler(resources)
    .addExceptionMapper(
        Throwable.class,
        ProblemDetailsExceptionMapperBuilder.problemDetailsExceptionMapper().build());

serverBuilder.addHandler(api);
```

A `WebApplicationException` without a custom mapper uses its embedded response. Other unmapped exceptions propagate to the surrounding Mu Server error handling.

## Filters and interceptors

Create and register server-side JAX-RS components explicitly:

```java
RestHandlerBuilder api = RestHandlerBuilder.restHandler(resources)
    .addRequestFilter(requestFilter)
    .addResponseFilter(responseFilter)
    .addReaderInterceptor(readerInterceptor)
    .addWriterInterceptor(writerInterceptor);
```

Registration order is execution order; JAX-RS priorities are not applied. `@PreMatching` on a request filter is honored. A filter or interceptor can get the selected `ResourceInfo` and underlying `MuRequest` from context properties named by `MuRuntimeDelegate.RESOURCE_INFO_PROPERTY` and `MuRuntimeDelegate.MU_REQUEST_PROPERTY`.

## Custom parameter types

Method-level `@PathParam`, `@QueryParam`, `@HeaderParam`, and `@FormParam` binding does not depend on resource construction. Built-in conversion covers strings, primitives, enums, and the standard string factory or constructor patterns. For another type, register an instance:

```java
RestHandlerBuilder api = RestHandlerBuilder.restHandler(resources)
    .addCustomParamConverter(AccountId.class, accountIdConverter);
```

Use `addCustomParamConverterProvider` only when a provider needs to select among multiple raw or generic types.

## CORS

Enable CORS only when a browser client actually calls the API from another origin. Grant the narrow set of required origins:

```java
import static io.muserver.rest.CORSConfigBuilder.corsConfig;

RestHandlerBuilder api = RestHandlerBuilder.restHandler(resources)
    .withCORS(corsConfig().withAllowedOrigins("https://app.example.com"));
```

## Built-in OpenAPI output

Mu Server can expose its generated OpenAPI document and a small read-only HTML view without adding Swagger:

```java
RestHandlerBuilder api = RestHandlerBuilder.restHandler(resources)
    .withOpenApiJsonUrl("/openapi.json")
    .withOpenApiHtmlUrl("/api.html");
```

Use `withOpenApiDocument`, `addCustomSchema`, or `addSchemaObjectCustomizer` only when the requested schema needs more detail. Mu Server does not interpret Swagger annotations.

## Security, uploads, async responses, and SSE

- Security: register an application-created `ContainerRequestFilter`, such as Mu Server's `BasicAuthSecurityFilter`, with `addRequestFilter`. Use authentication over TLS and preserve the application's existing security model.
- Multipart uploads: bind `@FormParam` method parameters to `io.muserver.UploadedFile`, arrays, or supported collections. Apply application limits and treat filenames and content as untrusted input.
- Async: use the supported JAX-RS server API with `@Suspended AsyncResponse`, including explicit timeout and completion behavior.
- Server-sent events: use the supported `jakarta.ws.rs.sse` method parameters such as `@Context SseEventSink`; keep lifecycle and disconnect handling in the application-owned resource.

Check the selected mu-server release's Javadocs before using a less common facility. mu-server 2.4.1 implements a server-side subset of Jakarta REST 3.0; it does not provide the JAX-RS client API, classpath scanning, or `jakarta.ws.rs.core.Application` bootstrap.
