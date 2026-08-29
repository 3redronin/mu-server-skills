---
name: mu-server-static-resources
description: >-
  Use when creating, changing, reviewing, testing, or debugging delivery of application-owned read-only static assets with Mu Server's ResourceHandlerBuilder. Covers fileHandler, classpathHandler, fileOrClasspath, context paths, GET and HEAD policy, index and directory behavior, SPA fallbacks, MIME and cache headers, gzip, conditional and range responses, packaged resources, and Mu Server 3 WebJars. Trigger for Mu Server 2.x or 3.x applications hosting HTML, JavaScript, CSS, images, downloads, or Swagger UI, including unexpected static-response methods, statuses, paths, or headers.
license: MIT
---

# Serve static resources with Mu Server

Preserve the application's selected `io.muserver:mu-server` version, Java level, server lifecycle, context paths, and public HTTP behavior unless the user asks to change them. Determine whether the application uses Mu Server 2.x or 3.x from its resolved build. Treat Mu Server 3 as released, keep the `io.muserver:mu-server` coordinates, and never infer a final 3.x artifact number from a source snapshot or the historical `io.muserver:mu3` artifact.

Use `ResourceHandlerBuilder` for application-owned static assets. Keep uploads, generated tenant content, secrets, and arbitrary file downloads in application handlers with their own authorization, validation, and storage boundaries.

## Select the resource source deliberately

- `fileHandler(Path|File|String)` reads a filesystem tree. Its inventory and metadata are live, so additions, removals, and edits can be observed without rebuilding the handler.
- `classpathHandler("/web")` scans the classpath root and caches its inventory and metadata when the handler is built. Treat packaged resources as immutable; rebuild the handler or restart after changing an exploded classpath tree.
- `fileOrClasspath("src/main/resources/web", "/web")` checks the filesystem path once while the handler is being configured. If it is a directory, the resulting handler stays filesystem-backed; otherwise it stays classpath-backed. Relative paths depend on the process working directory, so verify both the developer launch directory and the packaged launch directory.

Read [sources, routing, and fall-through](references/sources-and-routing.md) when choosing a provider, mounting resources under a context, configuring index or directory behavior, or adding an SPA fallback.

## Make the HTTP method contract explicit

`ResourceHandler` does not limit methods. If an existing file matches, POST, PUT, DELETE, and other methods can receive the same resource; only HEAD suppresses the regular-file body. Put an application-owned guard before the resource handler when static paths are intended to support only GET and HEAD:

```java
MuHandler getOrHeadOnly = (request, response) -> {
    if (request.method() == Method.GET || request.method() == Method.HEAD) {
        return false;
    }
    response.status(405);
    response.headers().set(HeaderNames.ALLOW, "GET, HEAD");
    return true;
};

ContextHandlerBuilder assets = ContextHandlerBuilder.context("/assets")
    .addHandler(getOrHeadOnly)
    .addHandler(ResourceHandlerBuilder.fileOrClasspath(
        "src/main/resources/web", "/web"));
```

The guard is inside the context so it sees only `/assets`; it returns `false` for an allowed request so the resource handler can run, and consumes a disallowed request with `405` and `Allow`. Add an explicit OPTIONS handler if the application's contract requires one.

## Preserve handler order and missing-resource behavior

Resource handlers use `request.relativePath()`, making `ContextHandlerBuilder` the normal way to mount a resource root at a URL prefix. Missing resources return `false`, so a later handler can respond. Existing resources, redirects, listings, and served default files return `true`.

Keep API/auth handlers before any broad static or SPA fallback. Make an SPA fallback accept only GET/HEAD navigation paths in the intended UI context. Leave missing versioned assets and API paths as real 404s; a blanket `index.html` response hides deploy errors and changes API semantics.

The default file is `index.html`. A request for an existing directory without a trailing slash receives `302` by default. Use `withBareDirectoryRequestAction(TREAT_AS_NOT_FOUND)` when fall-through is preferable. Directory listing is disabled by default; enabling it can expose names and metadata, and a configured default file takes precedence over a listing.

## Configure representation metadata as a contract

Mu Server maps lowercase filename extensions to `ResourceType` values. A type controls the content type, default headers, and whether its MIME type belongs in a gzip configuration derived from that type. `withExtensionToResourceType(...)` replaces the mapping; start from `ResourceType.getDefaultMapping()` when extending the defaults.

Read [HTTP caching, ranges, gzip, and headers](references/http-behavior.md) before changing MIME mappings, caching, security headers, compression, conditional requests, or download/resume behavior. Important boundaries include:

- `withResourceCustomizer(...)` runs for an existing regular resource after its standard headers are added. It does not customize a missing-resource fall-through, a bare-directory redirect, or a directory listing.
- Default cache policy is short-lived for most assets, `no-cache` for HTML and several data/text types, and one day for JavaScript. Give genuinely content-fingerprinted assets a long `public, immutable` policy while keeping entry HTML revalidatable.
- Mu Server gzip is configured on `MuServerBuilder`, defaults to eligible text MIME types over 1400 bytes, and adds `Vary: Accept-Encoding`. A custom `ResourceType(gzip=true)` does not by itself update a server builder's already-selected MIME set.
- The handler emits `Last-Modified`, honors valid `If-Modified-Since`, advertises byte ranges, and serves one satisfiable range as `206`. It ignores invalid, unsatisfiable, or multiple ranges and sends the full `200` representation. It does not emit ETags or implement `If-Range` semantics.

Keep validators, `Content-Length`, `Content-Range`, and compression mutually consistent. Test both identity and gzip variants and, when range downloads matter, a range request with the client's actual `Accept-Encoding` behavior.

## Keep filesystem serving inside the application trust boundary

Read [filesystem and packaging security](references/filesystem-and-packaging.md) for any filesystem-backed handler or deployment review. `fileHandler` uses ordinary filesystem path and link behavior; treat it as a convenience for a trusted, read-only static tree rather than an authorization or storage-boundary mechanism.

Use a narrowly scoped root, least-privilege process permissions, and deployment controls that prevent runtime writers from changing the root or its links. Keep secrets, uploads, source trees, build metadata, and mutable tenant files outside the served tree. Verify application-specific path containment through integration tests using the same proxy and URI handling as production; do not infer containment from a framework name or a single normalized client request.

## Use WebJars according to the Mu major line

For Mu Server 3 WebJar setup or a 2.x-compatible fallback, read [WebJars and version differences](references/webjars-and-versions.md). Mu Server 3 provides `webjarHandler(artifactId, version)` and metadata-driven `webjarHandler(artifactId)`. Mu Server 2.4.1 can serve the same classpath layout with `classpathHandler("/META-INF/resources/webjars/<artifact>/<version>")`.

A WebJar is an intentional additional runtime dependency. Confirm its exact group, artifact, and version from the application's dependency resolution, and verify the expected packaged paths rather than assuming an artifact's internal filenames.

## Verify observable behavior

Use the project's documented Java and build commands. Exercise the resulting server over HTTP without silently following redirects:

1. Verify filesystem, classpath, and `fileOrClasspath` startup modes that the deployment actually uses, including a packaged launch from a different working directory.
2. For GET and HEAD, assert status, exact bytes, content type, content length, cache and security headers, and absence of a HEAD body. Verify a non-allowed method and its `Allow` header when method policy matters.
3. Test the root index, nested index, bare-directory action, directory listing policy, a missing resource, and fall-through to the next handler.
4. Test `If-Modified-Since` before/equal/after the resource timestamp, malformed validators, a valid single range, suffix and open-ended ranges as applicable, and ignored invalid/multiple/unsatisfiable ranges.
5. Test identity and gzip representations, `Vary: Accept-Encoding`, MIME mappings, fingerprinted and non-fingerprinted caching, and any `ResourceCustomizer` policy.
6. For an SPA, verify one client-side navigation path, a missing fingerprinted asset that remains 404, and an API 404 that remains an API 404.
7. For filesystem sources, test the application's normal containment boundary, runtime file-update policy, read permissions, and separation from uploads and secrets. For classpath sources and WebJars, run from the packaged artifact and verify representative resources.

Report the Mu Server major line, source-selection decision, working-directory assumptions, URL context and handler order, method/directory/SPA policy, cache and compression policy, conditional/range behavior, filesystem trust boundary, WebJar coordinates if any, and the build and HTTP checks run.
