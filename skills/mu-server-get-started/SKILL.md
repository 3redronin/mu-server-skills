---
name: mu-server-get-started
description: >-
  Create or adapt a Java application that directly embeds mu-server: add io.muserver:mu-server to Maven or Gradle, create the first route, serve static resources, and verify the app. Use for Mu Server, mu-server, muserver, io.muserver, or its lightweight Java HTTP handler API.
---

# Get started with mu-server

Create the smallest runnable application that fits the user's project.

## Choose versions and build shape

Inspect an existing build before editing it. Preserve its build system, Java toolchain, dependency versions, package names, application entry point, and run conventions unless the user asks to change them.

For a new project:

- Follow an explicit Maven or Gradle choice. If neither is specified, ask which one to use.
- For Gradle, follow an explicit or existing Groovy/Kotlin DSL choice. If a new project's DSL is unspecified, ask.
- Follow an explicit Java version. Otherwise prefer the latest stable Java version and state the choice.
- Infer ordinary project and package names from the request; ask only if there is no useful context.

Preserve a mu-server version explicitly requested or already used by the project. Otherwise determine the newest stable, non-snapshot `io.muserver:mu-server` release. Check [the mu-server download page](https://muserver.io/download) and Maven Central; if they disagree, Maven Central's published release metadata is authoritative. If neither source can be reached, use `2.4.1` as the offline fallback and say that the version was not verified online. Do not copy a snapshot version from the mu-server source repository.

Read only the matching build reference:

- [Maven](references/maven.md)
- [Gradle](references/gradle.md)

## Add the application

For a new application, use this shape, adapting the package, greeting, and port to the user's request. Use port `8080` when no port is given; keep an existing application's explicit port.

```java
package example;

import io.muserver.Method;
import io.muserver.MuServer;
import io.muserver.MuServerBuilder;
import io.muserver.handlers.ResourceHandlerBuilder;

public final class Main {
    public static void main(String[] args) {
        MuServer server = MuServerBuilder.httpServer()
            .withHttpPort(8080)
            .addHandler(Method.GET, "/hello", (request, response, pathParams) -> {
                response.write("Hello, world");
            })
            .addHandler(ResourceHandlerBuilder.fileOrClasspath(
                "src/main/resources/web", "/web"))
            .start();

        System.out.println("Started server at " + server.uri());
    }
}
```

Add `src/main/resources/web/index.html`. The resource handler uses that source directory while developing and `/web` on the runtime classpath when the directory is absent. It serves `index.html` for `GET /` directly with status `200`; do not add a redirect from `/` to `/index.html`.

Register specific routes before the resource handler so static content remains the fallback. Do not add Jakarta REST, a dependency-injection framework, a logging implementation, or another web framework unless the user asks for it.

When adapting an application, integrate the route and resource handler into its existing server lifecycle rather than creating a competing server or entry point.

## Verify the result

Use the project's documented commands. At minimum:

1. Compile or build with the selected Java version.
2. Start the application and request `GET /hello`; verify status `200` and the greeting.
3. Request `GET /` without following redirects; verify status `200`, no `Location` header, and the static page body.
4. When practical, start the built output from outside the project directory and repeat the homepage check. This proves that `fileOrClasspath` can load the packaged classpath resource instead of accidentally relying on the source tree.
5. Stop the process you started.

Report the Java and mu-server versions, how to start the application, the configured port, and the HTTP behavior verified.
