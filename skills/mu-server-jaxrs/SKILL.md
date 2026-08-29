---
name: mu-server-jaxrs
description: >-
  Use when creating, changing, upgrading, or troubleshooting application code that hosts Jakarta REST/JAX-RS APIs with Mu Server 2.x or 3.x. Covers projects that combine io.muserver with jakarta.ws.rs resources and need RestHandlerBuilder, Application or SeBootstrap setup, singleton lifecycle, provider registration, filters, readers or writers, exception mapping, CORS, OpenAPI, or HTTP verification.
---

# Use Jakarta REST with mu-server

Build on the user's application structure and treat its public HTTP behavior as the contract.

## Inspect the application

Before editing, inspect the build, Java and mu-server versions, package names, bootstrap code, resource and provider classes, server lifecycle, and tests. Preserve explicit choices and existing conventions unless the user asks to change them.

Identify the target major line before choosing APIs or expected HTTP behavior. For a Mu Server 3 task or a 2.x-to-3 upgrade, read [Mu Server 2.x and 3.x differences](references/version-differences.md) before changing code.

For a new project, prefer the latest stable Java version unless the user specifies one. Use port `8080` when no port is given. Preserve an existing application's port and startup/shutdown model.

Preserve a mu-server version explicitly requested or already used. Otherwise determine the newest stable, non-snapshot `io.muserver:mu-server` release from [the mu-server download page](https://muserver.io/download) and Maven Central. Maven Central's published release metadata wins if the sources disagree. If neither is reachable, use `2.4.1` as the offline fallback and disclose that it was not verified online.

The `io.muserver:mu-server` dependency contains Mu Server's Jakarta REST implementation and supplies its Jakarta REST API dependency transitively. No additional dependency is needed for Jakarta REST itself.

## Own object construction

With the direct `RestHandlerBuilder` APIs, use application-created singleton objects. Initialize the `MuServerBuilder` first so Mu's Jakarta REST runtime delegate is installed. Then construct each resource, filter, interceptor, mapper, reader, writer, and converter once, wire its dependencies through constructors, and pass the instance to `RestHandlerBuilder`.

Mu Server does not inject resource constructors or fields, create a resource per request, or scan the classpath. A class is not discovered merely because it has `@Provider`. An existing dependency-injection container can construct an object, but the application still registers that singleton. Make application-owned singletons thread-safe because concurrent requests can call the same instance.

Mu Server 3 can adapt a standard `Application`, but its resources remain singletons: resource instances come from `Application.getSingletons()`, while resource classes in `getClasses()` are rejected. It can instantiate supported provider classes from `getClasses()` once through a public no-argument constructor; this is provider construction, not dependency injection.

This lifecycle rule is separate from request parameter binding. Resource method parameters such as `@PathParam`, `@QueryParam`, entity bodies, and supported `@Context` values are supplied for each request.

## Add the REST handler

For a new plain-text API, use this direct-builder shape, which works on both 2.x and 3.x, and adapt names, paths, messages, and port to the request:

```java
package example;

import io.muserver.MuServer;
import io.muserver.MuServerBuilder;
import io.muserver.rest.RestHandlerBuilder;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

public final class Main {
    public static void main(String[] args) {
        MuServerBuilder serverBuilder = MuServerBuilder.httpServer()
            .withHttpPort(8080);

        GreetingService greetingService = new GreetingService();
        GreetingResource greetingResource = new GreetingResource(greetingService);

        MuServer server = serverBuilder
            .addHandler(RestHandlerBuilder.restHandler(greetingResource))
            .start();

        System.out.println("Started server at " + server.uri());
    }
}

final class GreetingService {
    String greet(String name) {
        return "Hello, " + name;
    }
}

@Path("/hello")
@Produces(MediaType.TEXT_PLAIN)
final class GreetingResource {
    private final GreetingService greetingService;

    GreetingResource(GreetingService greetingService) {
        this.greetingService = greetingService;
    }

    @GET
    @Path("/{name}")
    public String hello(@PathParam("name") String name) {
        return greetingService.greet(name);
    }
}
```

Create one REST handler for the API. Pass multiple resource instances to `restHandler(first, second, ...)`, or create one builder and call `addResource`; do not add a separate REST handler per resource.

Use `jakarta.ws.rs` imports with Mu Server 2.x and 3.x. Add a provider dependency only when explicitly requested behavior needs one, such as converting arbitrary objects to and from JSON.

Read [optional configuration](references/configuration.md) only for a requested facility such as JSON, exception mapping, filters, interceptors, custom parameter types, CORS, OpenAPI, security, uploads, asynchronous responses, or server-sent events.

Read [Mu Server 2.x and 3.x differences](references/version-differences.md) when upgrading, targeting Mu Server 3, or diagnosing behavior involving exception responses, matching, parameters, URI encoding, providers, filters, interceptors, response construction, cookies, SSE, or graceful shutdown.

## Verify observable behavior

Use the project's documented commands and tests. At minimum:

1. Compile with the selected Java version.
2. Start the built application and request each changed endpoint.
3. Assert the relevant status, response entity, and `Content-Type`; exercise request parameter binding where used.
4. Exercise repeated or concurrent requests when a singleton holds or delegates to mutable state.
5. Confirm unrelated handlers still work when adapting an application, then stop the process.

Report the Java and mu-server versions, how to run the application, the explicit port, the resources and providers registered, and the HTTP behavior verified.
