# Safe storage and content validation

Read this reference whenever uploaded content is persisted, queued, scanned, transformed, or published.

## Separate client metadata from storage identity

Treat `filename()`, `contentType()`, and `extension()` as display or audit claims only. Path stripping performed by Mu is not an authorization or traversal defense: values such as `..`, reserved device names, confusable Unicode, trailing dots/spaces, control characters, and filesystem-specific names can remain dangerous.

Generate the storage key on the server, such as an opaque random ID or a database-assigned ID. Keep the original name in escaped metadata only if the product needs it. Never concatenate it into a directory, command, URL, HTML response, object-store key, or executable content-disposition header without the context-specific encoding and policy.

Store uploads outside executable and static web roots. Use a private, non-attacker-writable incoming root. Protect directories and files with an explicit POSIX mode or the platform's ACL model; do not assume the process umask supplies the intended access. Avoid following user-controllable symlinks.

## Stage, validate, then publish

Use an application-owned workflow with a single cleanup owner:

1. Authenticate and authorize the upload. Reserve per-tenant bytes and an in-flight slot before expensive processing where possible.
2. Create a unique private staging directory on the same filesystem as the final store. Give `saveTo(...)` a new, non-existing child path whose parent already exists.
3. Record only application-controlled identifiers. Call `saveTo(...)` before the request completes.
4. Validate the staged bytes and size. If required, run malware scanning or safe format decoding in a bounded worker with time, CPU, output-size, recursion, and decompression limits.
5. Apply final permissions and atomically move within that filesystem to a server-controlled final path. If atomic move is a requirement, treat `AtomicMoveNotSupportedException` as an unsupported deployment rather than silently weakening the guarantee.
6. Commit metadata/quota state in an order with a defined recovery procedure. Mark the upload available only after both content and authoritative metadata are durable.
7. In `finally` or the equivalent terminal callback, delete staging data, release reservations and concurrency slots, and cancel unnecessary work. A scheduled janitor should reap abandoned staging directories after a conservative age, without touching committed content.

Choose collision semantics deliberately. A server-generated unique final name is the simplest default. If a logical name can already exist, fail, version, or replace according to product policy; `UploadedFile.saveTo` itself is not a collision-safe publication primitive. For distributed/object storage, use its conditional-create or versioning mechanism rather than pretending a local rename is atomic.

Successful `saveTo` transfers cleanup responsibility to the application. A later validation failure, database failure, timeout, cancellation, or duplicate-key race must remove or quarantine that destination.

## Validate content, not claims

Enforce both a total request cap and a post-parse per-file cap. For allowed types, compare the client claim with bounded inspection of the actual bytes using the application's existing trusted decoder or scanner. Reject mismatches according to the API's documented `4xx` contract; do not infer safety from MIME type, extension, or magic bytes alone.

Consider active content, polyglots, parser vulnerabilities, archive traversal, symbolic links in archives, nested archives, decompression bombs, image dimension bombs, documents with macros, and generated-output amplification where relevant to the accepted format. Store the original as non-executable data and serve it with a server-chosen media type and safe content-disposition policy.

Avoid adding a validation dependency merely because an upload API is used. Mu's upload API needs only `io.muserver:mu-server`. Reuse established application validation, scanning, storage, and transaction facilities; add another dependency only when the user-authorized content policy requires it and the maintenance/security cost is justified.

## Bound aggregate use

`withMaxRequestSize` is per request and applies server-wide. Add application or edge controls for:

- simultaneous request bodies, open staging files, and validation jobs;
- bytes reserved per authenticated principal and globally;
- total retained bytes, file count, rate, and retention time;
- worker queues, scanner timeouts, transformation output, and error-log volume.

Do not trust `Content-Length` for quota accounting; it can be absent and is not proof that all bytes will arrive. It is useful for early refusal, while received or persisted bytes remain authoritative. Reserve conservatively, reconcile on success, and release on every abort.
