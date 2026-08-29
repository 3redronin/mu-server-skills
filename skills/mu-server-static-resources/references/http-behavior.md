# HTTP caching, ranges, gzip, and headers

Read this reference when changing representation metadata or diagnosing conditional, range, compression, or browser behavior.

## Resource types and defaults

For a regular resource, Mu selects a `ResourceType` from the lowercase filename extension. Unknown or extensionless files use `application/octet-stream`. `withExtensionToResourceType(map)` replaces the entire mapping, so extend a mutable copy of the built-ins:

```java
Map<String, ResourceType> types = ResourceType.getDefaultMapping();
types.put("example", new ResourceType(
    "application/example",
    Headers.http2Headers().add(HeaderNames.CACHE_CONTROL, "max-age=300"),
    false,
    Collections.singletonList("example")));

ResourceHandlerBuilder.classpathHandler("/web")
    .withExtensionToResourceType(types);
```

Extension keys omit the dot. Mu's built-ins generally use:

- `no-cache` for HTML, plain text, JSON, CSV, and several user-facing data types;
- `max-age=86400` plus `X-Content-Type-Options: nosniff` for JavaScript;
- `max-age=300` plus `nosniff` for CSS;
- `max-age=300` for most other known and unknown resources.

These are defaults, not knowledge of the build pipeline. Override cache policy when the filename contract supports it:

- Content-hashed assets can use `Cache-Control: public, max-age=31536000, immutable`; retain old hashed files long enough for cached HTML still referring to them.
- Entry HTML, service workers, manifests, and other stable names should normally revalidate (`no-cache`) so deployments become visible.
- Avoid `no-store` unless storage itself is forbidden; it prevents useful revalidation and offline behavior.

## ResourceCustomizer scope

`withResourceCustomizer` is invoked after Mu adds content type, `Accept-Ranges`, content length, last modified, and the selected type's headers, but before conditional and range processing. It can replace cache policy and add headers based on `request.relativePath()`:

```java
.withResourceCustomizer(new ResourceCustomizer() {
    @Override
    public void beforeHeadersSent(MuRequest request, Headers headers) {
        headers.set(HeaderNames.X_CONTENT_TYPE_OPTIONS, "nosniff");
        if (request.relativePath().matches(".*\\.[0-9a-f]{8,}\\.(js|css)$")) {
            headers.set(HeaderNames.CACHE_CONTROL,
                "public, max-age=31536000, immutable");
        }
    }
})
```

`ResourceCustomizer` supplies a default method and is not a functional interface, so use an explicit implementation rather than a lambda. Use a predicate that matches the application's actual fingerprint convention; the regex is illustrative. The hook applies only to an existing regular resource. Put policy needed on redirects, listings, 404s, or all application responses in a separate earlier handler or trusted edge.

Add `nosniff` wherever active content types must not be guessed. Set a tested Content Security Policy for HTML at the application or edge layer if the site requires one; it must match the site's real scripts, styles, frames, and connections rather than a generic copied value. Avoid changing `Content-Length`, `Content-Range`, `Last-Modified`, or `Accept-Ranges` in the customizer unless the application replaces the corresponding semantics.

## Conditional requests

When provider metadata is available, a normal response includes `Last-Modified`. A valid `If-Modified-Since` whose second-resolution value is at least the resource's last-modified time produces `304` and no body. An invalid date is ignored and the resource is served normally.

ResourceHandler does not generate `ETag` and does not process `If-None-Match`. If strong content validation or deployment-specific ETags are required, place a cache/CDN or application handler with a complete validator contract in front rather than adding an ETag header without matching conditional logic.

## Byte ranges

Regular resources with a known size advertise `Accept-Ranges: bytes`.

- One satisfiable byte range produces `206`, `Content-Range`, the selected `Content-Length`, and those bytes. Prefix, open-ended, and suffix ranges are supported by the range parser.
- Multiple ranges are ignored and the whole representation is returned as `200`; no multipart/byteranges body is generated.
- Invalid and unsatisfiable ranges are ignored and return the full `200`, not `416`. HTTP permits a server to ignore Range, so clients must accept this behavior.
- `If-Modified-Since` is evaluated before Range; a matching validator produces `304` rather than `206`.
- `If-Range` is not implemented. A request containing it is still processed as an ordinary Range request, so applications needing validator-gated resumptions require another implementation or a capable edge.

Test exact bytes and headers. Also test HEAD: for a regular resource it has the GET headers and suppresses the body, including when a Range header is present.

## Gzip interaction

Gzip belongs to `MuServerBuilder`, not to ResourceHandler itself. It is enabled by default for configured text MIME types whose declared size is greater than 1400 bytes. Negotiated responses add `Content-Encoding` and `Vary: Accept-Encoding`; identity responses remain available to clients that do not request gzip.

`ResourceType.gzip()` is used when deriving a MIME set, but `MuServerBuilder` derives its default set from built-in types when the server builder is created. Adding a custom type to one resource handler does not update that set. To gzip a custom MIME type, pass the intended complete set to `withGzip(minimumSize, mimeTypes)`.

Compression changes the transferred representation and interacts with content lengths, caches, and range clients. When resumable downloads matter, test Range with the real `Accept-Encoding` behavior or exclude that download MIME type from on-the-fly gzip. Do not serve a precompressed file as though it were the unencoded representation; set its content encoding and vary/cache rules deliberately.
