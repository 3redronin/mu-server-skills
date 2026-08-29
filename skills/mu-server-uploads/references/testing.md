# Upload test matrix

Read this reference before writing or reviewing upload tests. Select the cases relevant to the endpoint, and use raw clients where ordinary multipart builders normalize away the malformed or hostile input being tested.

## Parsing and cardinality

- One valid file plus text metadata; verify status, response media type, decoded field, stored size, and exact stored bytes.
- Missing required file; expect the documented client error and no storage side effect.
- Multiple file parts with the same name; verify all are visible in order, or that a singular contract rejects repetition. Verify `uploadedFile` selects the first only where that behavior is intentional.
- Missing text field versus an explicitly empty text field; repeated text fields; names not recognized by the endpoint.
- Empty filename with zero bytes (no selected file) versus a named zero-byte file (present empty file).
- Required `boundary` missing, mismatched, truncated, or never closed; malformed part headers; excessive parts or header text. Assert the application's documented failure response, no final object, and continued server health. Do not assume every Mu/Netty version maps every decoder error to the same status without a test.

## Size and timing

- A fixed-length encoded body exactly at the configured total limit and one byte over; the oversize request should be rejected before handler persistence.
- The same over-limit case with chunked or unknown length; verify `413`, termination behavior relevant to the HTTP version, no publication, and a successful subsequent request.
- A file at its per-file limit inside a multipart body whose total includes boundaries, part headers, text fields, and other files. Verify both policies independently.
- A client that pauses longer than `withRequestTimeout`; distinguish the expected idle-read behavior from a continuously progressing long upload.
- Several concurrent bodies at the admission limit and at least one beyond it; verify bounded queues/files/threads, the chosen overload response, and quota release.

If clients use `Expect: 100-continue`, add a known-oversize case. Current Mu behavior rejects that expectation with `417`, whereas ordinary declared and received over-limit requests use `413`.

## Metadata and content

- Filenames with `../`, `..\\`, absolute paths, mixed separators, `..`, control characters, Unicode confusables, reserved names, multiple dots, no extension, and very long values. Assert the storage path is server-generated, remains under the intended root, and never overwrites an existing object.
- Duplicate client filenames in parallel requests. Assert distinct identifiers or the explicitly documented fail/version/replace rule.
- A misleading extension and `Content-Type`, including an allowed claim with disallowed bytes and valid bytes with the wrong claim. Assert byte-based policy and quarantine behavior.
- Format-specific bombs or active content where applicable, with deterministic low test limits rather than genuinely expensive fixtures.

## Persistence and cleanup

- Call `saveTo` during request handling, finish the exchange, then verify the application-owned destination still contains the exact bytes.
- Verify decoder-backed handles are not used after completion. At application level, assert staging is empty after success and every rejection.
- Interrupt a request after partial bytes, race a disconnect with timeout where practical, and inject validation, scanner, move, and metadata-commit failures. Assert no final publication, partial staging is eventually removed, reservations are released exactly once, and a retry succeeds.
- Restart or run the janitor against an old abandoned staging entry and a committed object; only the abandoned entry should be removed.

Run repeated and concurrent tests enough times to expose shared-name and cleanup races without using wall-clock sleeps as correctness assertions. Use latches, barriers, controlled streams, and eventual checks with bounded deadlines.
