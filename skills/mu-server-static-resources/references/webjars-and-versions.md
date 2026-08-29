# WebJars and Mu Server versions

Read this reference when hosting a WebJar or when static-resource behavior crosses Mu Server 2.x and 3.x.

## Mu Server 3 WebJar handlers

Mu Server 3 adds two `ResourceHandlerBuilder` factories:

```java
ContextHandlerBuilder.context("/docs")
    .addHandler(ResourceHandlerBuilder.webjarHandler("swagger-ui", swaggerUiVersion));
```

`webjarHandler(artifactId, version)` serves:

```text
/META-INF/resources/webjars/<artifactId>/<version>
```

The artifact ID and version must each be a nonblank single path segment. The explicit overload is deterministic and is the best choice when dependency convergence, shading, or multiple versions could make discovery ambiguous.

The one-argument overload reads `pom.properties` from these official WebJar Maven groups:

```text
META-INF/maven/org.webjars.npm/<artifactId>/pom.properties
META-INF/maven/org.webjars/<artifactId>/pom.properties
```

It fails during handler construction when metadata is absent, malformed, or exposes more than one distinct version. It does not search arbitrary group IDs. Use the explicit version overload when inference is unavailable or when selecting among multiple resolved versions.

The WebJar must be a runtime dependency. For Swagger UI, the standard coordinates are:

```xml
<dependency>
    <groupId>org.webjars</groupId>
    <artifactId>swagger-ui</artifactId>
    <version>${swagger-ui.version}</version>
</dependency>
```

Resolve and pin `${swagger-ui.version}` in the application. Verify the selected artifact's actual filenames and any application-specific initializer/configuration; serving the files does not configure an OpenAPI document URL by itself.

## Mu Server 2.x fallback

Mu Server 2.4.1 has no `webjarHandler` factory. It can serve the standard layout directly:

```java
ContextHandlerBuilder.context("/docs")
    .addHandler(ResourceHandlerBuilder.classpathHandler(
        "/META-INF/resources/webjars/swagger-ui/" + swaggerUiVersion));
```

Keep the version synchronized with dependency resolution. Avoid serving the parent artifact directory without a version when stable public URLs and unambiguous upgrades matter.

## Other 2.x and 3.x differences

The core `fileHandler`, `classpathHandler`, `fileOrClasspath`, default-file, listing, resource-customizer, conditional, range, and method behavior remains the same across 2.4.1 and 3.x.

Relevant migration details:

- Mu Server 3 adds JSpecify nullness metadata to the public API. JVM signatures remain compatible, while strict Java tooling and Kotlin can reveal nullable values that 2.x did not annotate.
- Mu Server 2.x's resource-path decoding uses form-style decoding, so a literal `+` in the URL path is treated as a space. Mu Server 3 uses URI path decoding, preserving a literal `+`; `%20` is a space and `%2B` is a plus. Test filenames containing these characters when upgrading.
- Mu Server 3 lowercases resource extensions with `Locale.ROOT`; 2.x used the platform default locale. This removes locale-dependent MIME lookup for unusual runtime locales.

Keep `io.muserver:mu-server` when moving to 3.x. Historical `io.muserver:mu3` and `mu3-*` tags are not the released Mu Server 3 line.
