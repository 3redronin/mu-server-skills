# Bounded raw streaming

Read this reference when whole-multipart parsing would hold too many handler threads, spool too much aggregate data, or validate too late.

## Prefer a raw-body contract

`request.inputStream()` and `AsyncHandle.setReadListener(...)` deliver the raw HTTP request body. For `multipart/form-data`, that includes boundaries and every part header; `UploadedFile.asStream()` is not an incremental alternative because it exists only after the complete multipart body is decoded.

For a streamable endpoint, prefer one file as the request entity (`application/octet-stream` or a narrow application media type) and pass trusted application metadata separately. Keep `withMaxRequestSize(...)` and `withRequestTimeout(...)`; count bytes independently for per-file/quota policy and validate incrementally where the format allows it.

If multipart is mandatory and per-part streaming is mandatory, Mu's form API does not provide that abstraction. Use an already-approved, robust streaming multipart parser or redesign the contract. Do not split buffers on boundary-like byte sequences: boundaries can span buffers, and malformed headers, encodings, limits, and nested forms require a real parser.

## Synchronous stream

`request.inputStream()` claims the single body reader. If present, close it with try-with-resources. Read through a fixed-size buffer into a private staging file, count before writing, and abort on any application limit. This occupies a handler-executor thread while the client uploads, but avoids whole-content copies and multipart decoding.

Do not call form methods, `readBodyAsString()`, or an async read listener on the same request.

## Asynchronous stream

Call `request.handleAsync()` and install one `RequestBodyListener`. Its callbacks run on a Mu NIO thread and must not block. For disk writes, scanning, or other blocking work, hand the current buffer to a bounded application executor and invoke the supplied `DoneCallback` only after that buffer is no longer needed. This preserves backpressure; copying every callback into an unbounded queue merely moves the memory problem.

On `onComplete`, finish and force the staging file as required, validate, atomically publish, write the response asynchronously, and complete the handle. On `onError`, delete partial data, release quota/concurrency reservations, and complete or cancel application work. Also use `AsyncHandle.addResponseCompleteHandler(...)` when expensive downstream work must be cancelled after a disconnect or other early terminal response.

Coordinate terminal callbacks so cleanup and quota release happen exactly once even if read failure, response failure, timeout, and disconnect race. Never publish from a partially received file. Keep error messages bounded and avoid logging uploaded content or sensitive form values.

## Admission and validation

Authenticate before calling `handleAsync()` where the existing handler chain permits it. Reject a known-unacceptable declared length early, but continue to enforce a received-byte counter because chunked bodies lack a length and declarations are not quota truth.

Incremental magic checks can reject obvious mismatches early, but many formats require end-of-file validation. Keep data in quarantine until all checks and metadata commits succeed. Cap decompressed or transformed output separately from input bytes.
