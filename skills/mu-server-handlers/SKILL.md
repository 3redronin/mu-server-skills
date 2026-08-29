---
name: mu-server-handlers
description: >-
  Use when creating, changing, reviewing, testing, or debugging application endpoints and middleware built directly on Mu Server's MuHandler or RouteHandler API, including MuServerBuilder.addHandler, Routes.route, and ContextHandlerBuilder. Covers ordered handled/fall-through chains, method and path routing, path parameters, contexts, request attributes, synchronous request/response access, errors, and request lifecycle. Basic bootstrap and static resources, Jakarta REST/JAX-RS, Murp reverse proxies, and asynchronous streaming, SSE, or WebSockets belong to their specialized Mu Server workflows.
license: MIT
---

# Build direct Mu Server handlers

Preserve the application's existing builder, dependency version, Java level, ports, handler order, and lifecycle unless the user asks to change them. Treat Mu Server 3 as released and keep the `io.muserver:mu-server` coordinates; the historical `io.muserver:mu3` artifact is unrelated. For a 2.x application or migration, read [Mu Server 2.x and 3.x differences](references/version-differences.md) before changing observable behavior.

Use this skill for the synchronous direct-handler model. Route Jakarta REST resources to the JAX-RS skill, Murp mappings to the Murp skill, first-project/bootstrap and static-resource work to the get-started skill, and `handleAsync()`, asynchronous body readers, SSE, WebSockets, or long-running non-blocking streams to their specialized guidance.

## Design the handler chain

Handlers are shared objects invoked concurrently on the handler executor. Keep mutable handler state thread-safe or move request-specific state onto the request.

The server calls handlers in registration order:

- `false` from `MuHandler.handle` means continue to the next handler.
- `true` means stop the chain. If it has not written a body, the response completes with the configured status and headers; an otherwise untouched response is an empty `200`.
- If every handler returns `false`, Mu Server produces its default `404` response.
- Once a handler writes or streams a body, it owns the response and must return `true`. Returning `false` after commitment lets another handler run against a response it cannot safely replace.

Use early handlers as inspectors, guards, or decorators. A guard that rejects a request sets the complete response and returns `true`; a filter that merely adds request state or response headers returns `false`:

```java
MuHandler authenticate = (request, response) -> {
    String token = request.headers().get("Authorization");
    if (!"Bearer demo".equals(token)) {
        response.status(401);
        response.headers().set(HeaderNames.WWW_AUTHENTICATE, "Bearer realm=\"api\"");
        response.contentType(ContentTypes.TEXT_PLAIN_UTF8);
        response.write("Unauthorized");
        return true;
    }
    request.attribute("example.authenticated-user", "daniel");
    return false;
};

ContextHandlerBuilder api = ContextHandlerBuilder.context("api")
    .addHandler(authenticate)
    .addHandler(Method.GET, "/users/{id : [0-9]+}", (request, response, pathParams) -> {
        String user = (String) request.attribute("example.authenticated-user");
        response.contentType(ContentTypes.TEXT_PLAIN_UTF8);
        response.write(user + ":" + pathParams.get("id"));
    });
```

Request attributes are scoped to one exchange and are visible to subsequent handlers. Use collision-resistant keys and handle absence or type mismatch explicitly. A `MuHandler` is not an around-filter: code after it returns does not wrap later handlers. Use `addResponseCompleteListener` for completion-time logging or metrics.

## Route methods and paths

Prefer `addHandler(Method, template, RouteHandler)` for a fixed route and a plain `MuHandler` when the handler itself must decide whether to fall through.

Direct routes have these contracts:

- A non-matching method or path returns `false` from the route wrapper. A matching route calls its `RouteHandler` and then always stops the chain; `RouteHandler` has no fall-through result.
- Matching is registration-ordered, not ranked by specificity. Register specific or constrained routes before overlapping general routes and keep catch-alls last.
- The method match is exact. `null` accepts any supported method. Direct GET routes do not automatically handle HEAD, and direct routing does not synthesize OPTIONS, `405 Method Not Allowed`, or an `Allow` header for a known method on the wrong path route. Add those contracts explicitly when required.
- Templates match the whole context-relative path and ignore the query string. A declared trailing slash is normalized, and `/items` also matches `/items/`; test this compatibility behavior rather than assuming strict slash distinction.
- Use `{name}` for one segment and `{id : [0-9]+}` for a constrained segment. Values in `pathParams` are URI-path decoded. In Mu Server 3 a literal `+` remains `+`, while `%20` becomes a space and `%2B` becomes `+`.
- Matrix parameters do not prevent a route match and are omitted from the string path value. Use `UriPattern`/`PathMatch` only when the application actually needs matrix `PathSegment` details.

Validate and parse path values as untrusted input even when a regex constrains them. Avoid repeating the same parameter name in one direct template when code must work on both 2.x and 3.x; their matching and retained-value behavior differs.

## Scope handlers with contexts

`ContextHandlerBuilder.context("api")` applies only to the path segment prefix `/api`; child routes match `request.relativePath()`. Contexts can nest, and `request.contextPath()` accumulates the URL-encoded context while `request.relativePath()` contains the remaining encoded path.

A request for the bare context path, such as `/api`, receives a `302` redirect to `/api/` with its query string preserved. Decide whether that redirect is acceptable to clients and tests. Empty contexts are transparent. Without a context, the established implementation and `ContextHandlerTest` return an empty string from `contextPath()`, despite older Javadoc and site documentation saying `/`.

When every child falls through, the original context and relative path are restored before the next outer handler runs. Put a guard inside a context when it should protect only that subtree; put it before the context when it should protect later handlers globally.

## Use the synchronous request and response model

Read [Synchronous request and response contracts](references/request-response.md) before implementing query/form/header/cookie/body parsing, uploads, redirects, streamed output, content-length handling, or response commitment behavior.

Set status, headers, content type, and cookies before choosing a response body API. Use one body-writing family per response. Prefer `write(String)` for a complete small text body; use `writer()` or `outputStream()` for APIs that require those abstractions. Keep asynchronous streaming out of this workflow.

## Handle failures and completion

An exception before response commitment goes through `withExceptionHandler`, if configured, and then Mu Server's default handling when the custom handler returns `false` or throws. A Jakarta `WebApplicationException` supplies its status; an ordinary unhandled exception becomes a generic HTML `500` with an error ID and does not expose the original message. If the response already started, its status and headers cannot be replaced; the connection or HTTP/2 stream may end with an incomplete body.

Custom exception handlers return `true` only after creating the intended response. Check `response.hasStartedSendingData()` before attempting a replacement, and set the intended error status explicitly—the status carried by a thrown exception is not applied before the custom handler runs. Test status, content type, body, important headers, and the post-commit failure path separately.

`addResponseCompleteListener` observes normal exchanges after successful or unsuccessful transport completion. Its `completedSuccessfully()` means the request was fully read and the response fully sent, so a fully delivered HTTP `500` can still be `true`. Protocol-level rejections that occur before a `MuRequest`/`MuResponse` exists are reported only to `addRequestRejectListener`.

For shutdown, prefer the application's established lifecycle and a bounded graceful `stop(duration, unit)` when in-flight work matters. On Mu Server 3 it returns `true` after clean shutdown and `false` when requests outlive the timeout; 2.x implemented this result in reverse.

## Verify observable contracts

Use the project's documented Java version and build commands. Review existing call sites and tests before changing handler order or fall-through. Then run focused HTTP checks for:

1. every changed route's method, exact path, trailing slash, path parameters, and one non-match;
2. each guard's allow and reject paths, proving rejected requests do not reach later handlers;
3. context bare-path redirect and scoped `contextPath()`/`relativePath()` behavior when used;
4. repeated query/form/header values, relevant encoding, missing and malformed inputs, cookies, body content types, and size limits;
5. response status, content type, body, headers, cookies, empty-body rules, and any explicit content length;
6. pre-commit and post-commit failures, completion/rejection listeners, concurrency for shared state, and graceful shutdown when changed.

Report the Mu Server major line, handler order and fall-through decisions, route/context contracts, request and response cases exercised, error behavior, and build and HTTP commands run.
