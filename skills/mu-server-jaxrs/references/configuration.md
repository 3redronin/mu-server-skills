# Optional Jakarta REST configuration

Use only the sections needed by the request. The examples use direct `RestHandlerBuilder` registration and work on both Mu Server 2.x and 3.x unless labelled otherwise. Every resource and provider instance shown here is application-owned and should be safe for concurrent use.

## Bootstrap and component registration

Start from an initialized `MuServerBuilder`. In a new application, call `MuServerBuilder.httpServer()` before constructing JAX-RS providers or responses: loading the server builder installs Mu Server's Jakarta REST `RuntimeDelegate`. This ordering is required before `problemDetailsExceptionMapper().build()` in mu-server 2.4.1. The normal server bootstrap handles it; an application should not need to call `MuRuntimeDelegate.ensureSet()` itself.

Mu Server 2.x supports programmatic registration through `RestHandlerBuilder`; it does not support `jakarta.ws.rs.core.Application` or `SeBootstrap`.

Mu Server 3 also supports `RestHandlerBuilder.fromApplication(application)`. Instances from `Application.getSingletons()` are registered as singleton resources or providers. Supported provider classes from `getClasses()` are instantiated once with a public no-argument constructor, but resource classes in `getClasses()` are rejected because they imply a per-request lifecycle. Application properties, features, dynamic features, context resolvers, and classpath scanning remain unsupported. An application annotated with `@ApplicationPath` is rejected by `fromApplication`; use `SeBootstrap`, or use an unannotated `Application` and mount its handler explicitly.

Before using Mu Server 3's standard `SeBootstrap`, explicitly select Mu's runtime delegate:

```java
MuRuntimeDelegate.ensureSet();

SeBootstrap.Configuration configuration = SeBootstrap.Configuration.builder()
    .port(8080)
    .rootPath("/service")
    .build();

CompletionStage<SeBootstrap.Instance> started =
    SeBootstrap.start(new MyApplication(), configuration);
```

The standard system property `jakarta.ws.rs.ext.RuntimeDelegate=io.muserver.rest.MuRuntimeDelegate` is an alternative to `ensureSet()`. Classpath presence alone does not select Mu for `SeBootstrap`.

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

Provider selection differs across the major lines. In 2.x, a built-in provider can win over an applicable application provider, and a wildcard reader can win over a more specific media type. In 3.x, application providers take precedence over built-ins; compatible readers prefer the more specific media type; writers prefer the Java type nearest the runtime entity class; and generic entity types are retained more consistently. Give providers accurate `@Consumes` and `@Produces` declarations and `isReadable` or `isWriteable` checks instead of depending on 2.x selection order.

## Exception mapping and RFC 9457

Register a custom mapper instance against the exception class it handles:

```java
RestHandlerBuilder api = RestHandlerBuilder.restHandler(resources)
    .addExceptionMapper(ValidationException.class, validationExceptionMapper);
```

Mu Server 2.3.0 and later include an RFC 9457 problem-details mapper builder. In 2.4.1 the mapper is opt-in:

```java
import io.muserver.rest.ProblemDetailsExceptionMapperBuilder;

MuServerBuilder serverBuilder = MuServerBuilder.httpServer();
RestHandlerBuilder api = RestHandlerBuilder.restHandler(resources)
    .addExceptionMapper(
        Throwable.class,
        ProblemDetailsExceptionMapperBuilder.problemDetailsExceptionMapper().build());

serverBuilder.addHandler(api);
```

In 2.x, otherwise-unmapped exceptions propagate to Mu Server's standard HTML error handling. A `WebApplicationException` without an applicable mapper uses its embedded response, but a registered mapper can replace that response.

Mu Server 3 registers the problem-details mapper for `Throwable` by default. Otherwise-unhandled exceptions and malformed REST requests therefore use `application/problem+json`; application mappers for more specific exception types still take precedence. A `WebApplicationException` that already has an entity keeps its response. To restore the standard HTML fallback, remove the default mapper:

```java
RestHandlerBuilder api = RestHandlerBuilder.restHandler(resources)
    .removeExceptionMapper(Throwable.class);
```

To configure the Mu Server 3 default behavior, replace the `Throwable` registration with a mapper built by `ProblemDetailsExceptionMapperBuilder`. By default, instance IDs are logged for 5xx responses but not for 4xx responses.

## Filters and interceptors

Create and register server-side JAX-RS components explicitly:

```java
RestHandlerBuilder api = RestHandlerBuilder.restHandler(resources)
    .addRequestFilter(requestFilter)
    .addResponseFilter(responseFilter)
    .addReaderInterceptor(readerInterceptor)
    .addWriterInterceptor(writerInterceptor);
```

`@PreMatching` on a request filter is honored in both major lines. A filter or interceptor can get the selected `ResourceInfo` and underlying `MuRequest` from context properties named by `MuRuntimeDelegate.RESOURCE_INFO_PROPERTY` and `MuRuntimeDelegate.MU_REQUEST_PROPERTY`.

In 2.x, `@Priority` is not applied. Request filters, response filters, and writer interceptors are registration-dependent, while reader interceptors can run in reverse addition order. Preserve and test the existing observed order when maintaining a 2.x application.

In 3.x, JAX-RS priority ordering is applied: request filters run in ascending priority, response filters in descending priority, and reader and writer interceptors in ascending priority; an unannotated component uses `Priorities.USER`. `abortWith(...)` stops the remaining request-filter chain and its supplied response bypasses exception mapping.

## Custom parameter types

Method-level `@PathParam`, `@QueryParam`, `@HeaderParam`, and `@FormParam` binding does not depend on resource construction. Built-in conversion covers strings, primitives, enums, and the standard string factory or constructor patterns. For another type, register an instance:

```java
RestHandlerBuilder api = RestHandlerBuilder.restHandler(resources)
    .addCustomParamConverter(AccountId.class, accountIdConverter);
```

Use `addCustomParamConverterProvider` only when a provider needs to select among multiple raw or generic types.

Mu Server 2.x does not support object-array resource parameters; use a supported `List`, `Set`, or `SortedSet` when a parameter can repeat. Mu Server 3 supports object arrays for `@QueryParam`, `@HeaderParam`, `@MatrixParam`, `@FormParam`, and `@CookieParam`: repeated values become elements, a missing value becomes an empty array, and `@DefaultValue` supplies one element. `@PathParam` arrays and primitive arrays such as `int[]` are unsupported. Cookie arrays use `jakarta.ws.rs.core.Cookie[]`.

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

The generated JSON can be rendered by a separately hosted Swagger UI. Add `mu-swagger` only when the application specifically needs Swagger Core v3 annotations such as `io.swagger.v3.oas.annotations.Operation`; a Swagger UI by itself does not require it.

## Security, uploads, async responses, and SSE

- Security: register an application-created `ContainerRequestFilter`, such as Mu Server's `BasicAuthSecurityFilter`, with `addRequestFilter`. Use authentication over TLS and preserve the application's existing security model.
- Multipart uploads: in 2.x bind `@FormParam` to `io.muserver.UploadedFile` or a supported collection; 3.x also supports `UploadedFile[]`. Mu Server 3 does not implement Jakarta REST 3.1's `EntityPart` multipart API. Apply application limits and treat filenames and content as untrusted input.
- Async: use the supported JAX-RS server API with `@Suspended AsyncResponse`, including explicit timeout and completion behavior.
- Server-sent events: use the supported `jakarta.ws.rs.sse` method parameters such as `@Context SseEventSink`; keep lifecycle and disconnect handling in the application-owned resource. Mu Server 3 corrects closed-state reporting, broadcaster cascading close, and duplicate concurrent callbacks, so exercise those cases explicitly when upgrading from 2.x.

Check the selected Mu Server release's Javadocs before using a less common facility. Mu Server 2.4.1 implements a server-side subset of Jakarta REST 3.0. Mu Server 3 implements a server-side subset of Jakarta REST 3.1 and passes the applicable TCK tests for supported features. Neither line provides a JAX-RS client implementation, classpath scanning, dependency injection, or per-request resource construction.
