# Sources, routing, and fall-through

Read this reference when selecting `fileHandler`, `classpathHandler`, or `fileOrClasspath`, mounting resources, changing default files or listings, or implementing an SPA.

## Provider selection and update behavior

`ResourceHandlerBuilder.fileHandler(path)` validates that the configured root is a directory when the builder is created. For each request, the filesystem provider resolves the context-relative resource path and reads current existence, directory, size, and last-modified information. File additions, edits, and removals are therefore live, subject to filesystem races and permissions.

`classpathHandler(root)` walks the classpath tree when the handler is built. It caches the resource inventory, file size, and last-modified metadata, then opens the selected resource for each response. In a packaged JAR this matches the normal immutable-resource model. In an exploded classes directory, a new file is not discovered and an edited file can have stale metadata until the handler is rebuilt; restart rather than relying on hot classpath edits.

`fileOrClasspath(fileRoot, classpathRoot)` is an early choice, not a per-request fallback. It checks `Files.isDirectory(Paths.get(fileRoot))` while configuring the handler and returns either a file-backed or classpath-backed builder. A relative file root is resolved from the JVM's working directory. Log or otherwise make the selected deployment mode observable when an unexpected working directory could silently select a different source.

## Context paths and ordering

The resource handler consumes `request.relativePath()`. Mount it under an application URL prefix with a context:

```java
ContextHandlerBuilder.context("/static")
    .addHandler(methodGuard)
    .addHandler(ResourceHandlerBuilder.classpathHandler("/web"));
```

Contexts and child handlers are registration-ordered. A missing resource returns `false`; the context restores the outer request paths before later outer handlers run. This enables a deliberate fallback, but it also means a broad handler registered before an API can intercept the API request. Keep authorization and APIs ahead of public assets unless the context isolates them.

A request for the bare context, such as `/static`, is handled by `ContextHandler` and redirected to `/static/`. Separately, a filesystem or classpath directory requested without a trailing slash is controlled by `withBareDirectoryRequestAction(...)`:

- `REDIRECT_WITH_TRAILING_SLASH` is the default and sends `302`.
- `TREAT_AS_NOT_FOUND` returns `false`, allowing a later handler or the server's default 404.

## Index files and listings

`index.html` is the default file. `withDefaultFile(null)` disables it. For a path ending in `/`, Mu first looks for the default file; if it exists, it wins even when directory listings are enabled.

Directory listing is disabled by default. When enabled, Mu renders an HTML page containing child names, last-modified data, and sizes. Configure it only when that disclosure is part of the application contract. `withDirectoryListingDateFormatter(...)` and `withDirectoryListingCSS(...)` change presentation, not access control.

## SPA fallback design

ResourceHandler's `false` result for a missing asset is useful for an SPA, but fallback scope must remain explicit:

1. Register API and authentication handlers first or isolate the UI under its own context.
2. Let the resource handler serve real files.
3. Let the SPA fallback handle only GET/HEAD navigation paths belonging to the UI.
4. Leave missing filenames that look like assets—especially versioned `.js`, `.css`, maps, fonts, and images—as 404 so stale HTML and incomplete deploys are visible.
5. Ensure the fallback can load `index.html` from the packaged classpath; a source-tree-only filesystem read will break when the working directory changes.

The SPA response is application-owned. Give it the same HTML cache and security policy as the ordinary `index.html`, implement HEAD deliberately, and test one navigation path plus API and asset near-misses.
