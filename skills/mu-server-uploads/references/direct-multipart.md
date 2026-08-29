# Direct multipart API and lifecycle

Read this reference when implementing or reviewing a direct `MuHandler` or `RouteHandler` that uses Mu's parsed form APIs.

## Parse once

Require `multipart/form-data` before calling upload accessors. A direct route does not have Jakarta REST `@Consumes` matching, and upload methods are not a general parser for arbitrary entity types.

Any first call to `request.form()`, `request.uploadedFile(name)`, or `request.uploadedFiles(name)` selects the same multipart form reader and waits for the final request-body chunk. Calls within that family then reuse the decoded data. The request cannot also be consumed through `inputStream()`, `readBodyAsString()`, or `AsyncHandle.setReadListener(...)`.

Use these exact absence and repetition contracts:

- `request.form().get(name)` returns the first text value or `null` when absent.
- `request.form().getAll(name)` returns all text values or an empty list. An explicitly empty text part is present with value `""`; use `contains(name)` or list cardinality when that distinction matters.
- `request.uploadedFile(name)` returns the first file or `null` when absent.
- `request.uploadedFiles(name)` returns all files with that field name or an empty list, in decoded part order.
- A file part with both an empty filename and zero bytes is treated as no upload. A zero-byte part with a non-empty filename is an uploaded file of size zero. Decide explicitly whether that is valid.

[RFC 7578](https://www.rfc-editor.org/rfc/rfc7578.html) makes `boundary` a required media-type parameter and requires each part to have `Content-Disposition: form-data` with a `name`. It requires current senders to represent multiple files as separate parts with the same name, and requires duplicated fields not to be coalesced. Keep singular endpoints explicit about rejecting extra files rather than silently accepting only the first when repetition is invalid. A file `filename` is only recommended and a part `Content-Type` is optional, so application requiredness and content policy remain separate checks.

## Understand `UploadedFile`

`UploadedFile` exposes:

- `filename()`: a client-supplied display name after parser/Mu transformations. Mu strips `/` and `\` path prefixes, but the result is still unsafe as a storage path and can vary with the bundled decoder.
- `extension()`: the suffix after the last dot in that untrusted name, or `""`; it is not a content classification.
- `contentType()`: the client-declared part media type, not a detected type.
- `size()`: decoded file-content bytes, excluding multipart framing.
- `asBytes()` and UTF-8 `asString()`: whole-file copies. Bound size before allocating them.
- `asStream()`: a stream over already-decoded storage, not a live per-part stream. Close it in the request scope.
- `asFile()`: a local file representation whose durability depends on the decoder's in-memory/disk choice. Do not retain it beyond the exchange.
- `saveTo(File)`: persists by moving or writing the decoded data to the destination and creates missing parent directories. Call it before exchange completion.

Do not depend on whether `saveTo` uses a rename or copy, or on replacement behavior when the destination exists; those vary by storage representation and filesystem. It is not an atomic publish or exclusive-create API. Give it a new server-controlled staging path, then validate and publish with application-owned collision semantics.

## Lifecycle boundary

Mu calls the form reader's cleanup when the HTTP exchange ends for HTTP/1.1 and HTTP/2, including error terminal states. Multipart cleanup destroys the decoder, which releases decoded buffers and decoder-owned temporary files. This has several consequences:

- Persist required content with `saveTo(...)` before returning from a synchronous handler or calling `AsyncHandle.complete()`.
- A successfully saved destination is application-owned and may outlive the request. Delete it if later validation or metadata commit fails.
- A `byte[]` or `String` copied before completion is independent, but can amplify memory use. Snapshot scalar filename, media type, or size values if background metadata work needs them.
- An `UploadedFile`, `asStream()` result, or `asFile()` result is not a portable post-request handle. Do not let storage-mode-dependent behavior make tests pass accidentally.

`saveTo` can move the decoder file. A previously obtained `asFile()` may therefore stop naming an existing file; do not mix the two representations.

## Resource behavior

`withMaxRequestSize(n)` applies to bytes of the complete encoded request body. Mu's current behavior rejects an ordinary declared `Content-Length > n` before dispatch with `413`; a chunked/undeclared body gets `413` after cumulative received bytes exceed `n`. With `Expect: 100-continue`, current Mu rejects a known-too-large expectation with `417`. [RFC 9110 section 15.5.14](https://www.rfc-editor.org/rfc/rfc9110.html#section-15.5.14) permits a server returning `413 Content Too Large` to terminate the request or close the connection as the protocol permits. Test only the cases the application or clients rely on, including exact-limit and one-byte-over boundaries.

`withRequestTimeout(duration, unit)` is reset as body data arrives. A pause beyond it produces the read-timeout path (a `408` can be sent if the response has not started). This does not cap the wall-clock duration of a continuously progressing upload.

Multipart decoding can spill parts to disk, but callers cannot configure or rely on a stable public Mu threshold. `UploadedFile.size()` and content checks happen after the complete multipart envelope has been received. If incremental file-level enforcement is required, use a raw upload contract and the streaming path.
