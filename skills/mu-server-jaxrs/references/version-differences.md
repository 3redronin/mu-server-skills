# Mu Server 2.x and 3.x differences

Read this reference when targeting Mu Server 3, upgrading a 2.x application, or diagnosing behavior that changes with the major line. These distinctions come from the [Mu Server 3 release and migration notes](https://muserver.io/changelog/mu-server-3). Check the selected release's Javadocs for any later changes.

Mu Server 3 moves from Java 8 to Java 11 minimum, Jakarta REST 3.0 to 3.1, and SLF4J 1.7 to 2.0. Its public APIs carry JSpecify nullness annotations. The Maven coordinates and Java package names do not change. An SLF4J 1.7 binding is not an SLF4J 2 provider and therefore will not be discovered after the upgrade.

Mu Server 3 passes the Jakarta REST 3.1 TCK tests applicable to the features it supports. This is not a claim that every Jakarta REST feature is implemented: notably, `EntityPart`, per-request resources, dependency injection, classpath scanning, application properties, features, dynamic features, and context resolvers remain unsupported.

## Registration and bootstrap

| Concern | Mu Server 2.x | Mu Server 3.x |
| --- | --- | --- |
| Direct registration | Register application-created singleton resources and providers with `RestHandlerBuilder`. | The same direct API remains supported. |
| `Application` | Unsupported. | `RestHandlerBuilder.fromApplication` accepts resource and provider instances from `getSingletons()` and constructs supported provider classes from `getClasses()` once with a public no-argument constructor. Resource classes from `getClasses()` are rejected. |
| `@ApplicationPath` | Unsupported. | Honored by `SeBootstrap`; an annotated application is rejected by `RestHandlerBuilder.fromApplication`, so an unannotated application must be mounted explicitly. |
| Java SE bootstrap | Unsupported. | `SeBootstrap` supports HTTP, HTTPS, dynamic ports, root paths, `@ApplicationPath`, and asynchronous shutdown. Call `MuRuntimeDelegate.ensureSet()` first or set the standard runtime-delegate system property. |

The singleton contract does not change. Mu Server 3's ability to construct provider classes does not add injection and does not allow per-request resource classes.

## Behavior to retest

| Area | Mu Server 2.x | Mu Server 3.x |
| --- | --- | --- |
| Unhandled REST exceptions | Fall through to Mu Server's standard HTML error response unless the application opts into a mapper. | A default `Throwable` mapper returns RFC 9457 `application/problem+json`, with `Cache-Control: no-store`, a UUID instance for unexpected errors, and no exception-message disclosure. Remove the mapper for the HTML fallback. |
| `WebApplicationException` with an entity | A registered mapper can replace the carried response. | The carried response and entity are preserved; more-specific application mappers still take precedence for other exceptions. |
| Invalid URI parameter conversion | Returns `400`; an invalid enum has the 2.x error response. | The default mapper returns a `400` problem document with parameter details. If that default mapper is removed, the underlying Jakarta REST result is `404`. `UriParameterConversionException` is available for custom mapping. |
| Object-array parameters | Unsupported. | Supported for `@QueryParam`, `@HeaderParam`, `@MatrixParam`, `@FormParam`, and `@CookieParam`; not supported for `@PathParam` or primitive arrays. |
| Non-public annotated methods | Ignored silently. | Still ignored because resource methods must be public, with a startup warning. |
| Bodyless request with `@Consumes` | The resource method may not match. | Missing content type is treated as a wildcard, so the method can match. |
| Relative `Location` | From `/app/items/123`, `URI.create("next")` resolves to `/app/items/next`. | It resolves against the application base URI, producing `/app/next`. |
| Repeated and empty path captures | Repeated captures can lose values; an empty capture can trigger `@DefaultValue`. | Repeated captures are retained and affect ranking; an empty capture remains empty, while only an absent value triggers the default. |
| Inherited annotations and generic types | An annotation can be missed or a generic type reduced to `Object`. | Inherited declarations and their concrete generic entity types are retained. |

## URI and form encoding

Do not preserve 2.x output merely because an encoded string changed. Mu Server 3 separates HTML form encoding from URI-component encoding:

- Writing `application/x-www-form-urlencoded` changes a space from `%20` to `+`; a literal plus remains `%2B`.
- `@Encoded @FormParam` preserves an encoded space as `+` in 3.x rather than rewriting it as `%20`.
- A literal `+` in path and matrix components stays a plus in 3.x; 2.x can decode it as a space.
- URI builders apply component-specific encoding in 3.x. `UriInfo.getAbsolutePath()` preserves the request authority and an encoded `%2F` instead of treating that slash as a path delimiter.

Test raw and decoded forms separately when the application signs URLs, compares exact strings, proxies requests, or accepts plus signs and encoded slashes.

## Providers, filters, and interceptors

| Concern | Mu Server 2.x | Mu Server 3.x |
| --- | --- | --- |
| Application provider versus built-in | A built-in provider can win. | An applicable application provider wins. |
| Reader selection | A wildcard media-type reader can win over a specific one. | The more specific compatible media type wins. |
| Writer selection | Selection can follow the declared type, such as `Object`. | Selection prefers the provider nearest the entity's runtime Java type. |
| Generic entities | Providers can receive a raw type or `Object`. | Declared generic types are retained through inherited methods, `CompletionStage`, and `GenericEntity`. |
| Ordering | `@Priority` is not enforced; ordering is registration-dependent, and reader interceptors can run in reverse addition order. | Request filters and reader/writer interceptors use ascending `@Priority`; response filters use descending priority; unannotated components use `Priorities.USER`. |
| `abortWith` | Later request filters can run, and exception mapping can replace the supplied response. | The request-filter chain stops and the supplied response bypasses exception mapping. |
| Entity-stream replacement | Request decompression can truncate; creating a response wrapper can commit metadata too early. | Replaced request streams and wrapped response streams retain the correct body, status, and headers. |

Mu Server 3 also continues past a skipped non-matching name-bound interceptor, rejects request mutation from a response filter with `IllegalStateException`, and reliably sends header changes made by filters or interceptors.

## Responses, cookies, SSE, and shutdown

- A Mu Server 3 `ResponseBuilder` with no explicit status defaults to `200` when it has an entity and `204` when it does not. Do not assume 2.x derives those statuses.
- Mu Server 3 session cookies omit `Max-Age` and `Expires`, supports Jakarta REST 3.1 `SameSite`, serializes cookie comments safely, and avoids duplicate cookies on wrapped responses. Retest exact `Set-Cookie` output.
- Mu Server 3 supports `Reader` response entities, makes `Response.getStringHeaders()` a live view, and corrects variant selection.
- Mu Server 3 fixes SSE closed-state reporting, cascading broadcaster close, and duplicate callbacks under concurrent close, disconnect, broadcast, and shutdown.
- `MuServer.stop(...)` returns `false` after a clean shutdown and `true` after a timeout in 2.x, contrary to its documented contract. Mu Server 3 corrects this to `true` for a clean shutdown and `false` for a timeout. Update callers that compensated for the 2.x result.

Exercise the observable cases an application actually relies on. In particular, verify status, media type, response entity, exact `Location` and cookie headers, raw URI values, provider choice, filter/interceptor order, and shutdown result rather than treating successful compilation as sufficient evidence.
