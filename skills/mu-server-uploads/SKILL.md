---
name: mu-server-uploads
description: >-
  Use when implementing, reviewing, hardening, or testing multipart/form-data and file-upload endpoints in Mu Server 2.x or 3.x applications, through MuRequest form/upload APIs or Jakarta REST @FormParam UploadedFile. Covers resource limits, request-scoped upload lifecycles, safe persistence, untrusted metadata and content, concurrent storage, failure cleanup, and raw asynchronous streaming for large or numerous uploads.
license: MIT
---

# Build safe Mu Server uploads

Treat the accepted HTTP body, every part header, and every byte as untrusted. Preserve the application's Java version, Mu Server version, build system, dependency choices, handler structure, authentication, and response conventions unless the request changes them. Mu's upload APIs are in `io.muserver:mu-server`; they need no additional upload dependency.

## Inspect the upload contract

Before editing, inspect the server builder, handler or resource, authentication and authorization, request-body consumers, storage code, completion behavior, exception handling, and focused tests. Establish:

- accepted media type, form-field names, whether fields may repeat, and the intended missing/empty semantics;
- maximum total request size, per-file and per-user limits, request read-idle timeout, concurrent-upload budget, and storage quota;
- permitted content, validation or scanning, retention, naming, collision behavior, permissions, and publication boundary;
- whether the endpoint needs parsed multipart parts or a raw byte stream.

Preserve an explicit or existing `io.muserver:mu-server` version. Treat Mu Server 3 as released, keep the same Maven coordinates, and do not invent a final 3.x version number. For ordinary major-version differences, use the repository's `mu-server-jaxrs` or `mu-server-upgrade` workflow as applicable.

## Choose the body-reading model

Use `request.form()`, `request.uploadedFile(name)`, and `request.uploadedFiles(name)` for conventional, bounded `multipart/form-data`. The first form/upload access claims the body, blocks that handler-executor thread until the whole body is decoded, and makes all decoded parts available together.

Use raw `request.inputStream()` for synchronous sequential streaming, or `request.handleAsync()` with `AsyncHandle.setReadListener(...)` for non-blocking raw streaming when bodies are large, numerous, slow, or must be rejected while arriving. These APIs expose the raw request body, including multipart framing; they do not stream one decoded file part. Prefer a raw-body upload contract for this path. Do not write an ad hoc multipart boundary parser.

Read only the references needed for the chosen path:

- For whole-form direct handlers and exact API semantics, read [direct multipart API and lifecycle](references/direct-multipart.md).
- Before saving any upload, read [safe storage and content validation](references/storage-security.md).
- For raw-body or asynchronous ingestion, read [bounded raw streaming](references/raw-streaming.md).
- For `@FormParam UploadedFile`, collections, or arrays, read [Jakarta REST upload binding](references/jakarta-rest.md). Keep general resource construction and registration in the `mu-server-jaxrs` workflow.

## Enforce resource bounds first

Set `MuServerBuilder.withMaxRequestSize(...)` to a finite deployment-appropriate total-body limit and `withRequestTimeout(...)` to a finite idle-read limit. The size covers the entire encoded body: every file, text field, part header, delimiter, and multipart epilogue. Allow for protocol overhead while still keeping a hard total cap; a per-file `UploadedFile.size()` check is additional policy, not a substitute.

A declared `Content-Length` above Mu's limit is rejected before the handler. Chunked or otherwise undeclared bodies are counted while they arrive and rejected after crossing the limit. The read timeout is an idle-between-data limit, not a maximum total upload duration. Keep upstream proxy and application limits intentionally aligned.

Whole-multipart parsing may use both memory and decoder-owned temporary files. The split is an implementation detail of Mu's Netty version. Do not base heap sizing, security decisions, tests, or lifecycle assumptions on a storage threshold.

Add application-level admission control where global size limits are insufficient: authenticate before accepting expensive work, bound simultaneous uploads and validation jobs, reserve tenant quota before publication, and release reservations on every failure path. A post-parse per-file check cannot prevent the rest of a multipart body from already being spooled.

## Preserve request ownership and lifecycle

The request body has one owner. Do not combine form/upload access with `inputStream()`, `readBodyAsString()`, or an async read listener. Repeated calls within the form family reuse the parsed form; crossing families throws or fails.

Mu destroys the multipart decoder at exchange end. Decoder-owned memory and temporary files are then released. Finish reads and call `saveTo(...)` before a synchronous handler returns or an async handle completes. Do not hand an `UploadedFile`, its stream, or an `asFile()` path to background work. Snapshot small scalar metadata or copies only when needed; prefer `saveTo(...)` for content that must outlive the request.

`asBytes()` and `asString()` allocate whole-content copies, and `asStream()` is available only after the whole multipart body has already been decoded. Use the copy methods only after a deliberately small size check, and close every stream.

## Validate behavior, not just the happy path

Read [upload test matrix](references/testing.md) before adding or reviewing tests. Exercise externally observable status, response headers and body, persisted bytes, absence of partial publication, cleanup, and a subsequent successful request. Cover fixed-length and chunked oversize bodies, malformed multipart, disconnects, repeated and missing fields, empty selections and zero-byte files, hostile filenames, declared/content mismatches, persistence across request completion, and concurrent collisions or quota contention.

Review the final diff for request-body ownership, total-body accounting, blocking behavior, temporary-file lifecycle, unsafe path construction, overwrite races, partial files, memory amplification, error disclosure, cleanup on every terminal path, public/wire compatibility, and new dependencies.
