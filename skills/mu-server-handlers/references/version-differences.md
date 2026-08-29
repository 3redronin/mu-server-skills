# Direct-handler differences between Mu Server 2.x and 3.x

Read this only when targeting Mu Server 2.x, migrating direct handlers, or diagnosing a version-dependent contract. Mu Server 3 uses the existing `io.muserver:mu-server` coordinates and `io.muserver` packages; ignore the historical `io.muserver:mu3` prerelease artifact.

| Area | Mu Server 2.x | Mu Server 3 | Action |
| --- | --- | --- | --- |
| Java | Java 8 minimum. | Java 11 minimum. | Preserve a compatible existing toolchain; update it when moving to 3.x. |
| Nullness | Public direct-handler APIs do not carry JSpecify annotations. | Public APIs use JSpecify. `MuRequest.contentType()`, `uploadedFile()`, `attribute()`, and disconnected `remoteAddress()` are annotated nullable; `contentType(null)` removes the response header. | Fix newly visible nullness findings without assuming runtime values became non-null. For portable code, remove a response content type through headers rather than passing `null`. |
| Path and matrix `+` decoding | Path decoding can treat literal `+` as a space. | URI-path rules apply: literal `+` remains plus, `%20` is space, and `%2B` is plus. | Assert exact path-param values when plus signs or signatures matter. Query and form values remain form-decoded, where `+` is a space. |
| Repeated parameter names in one path template | Repeating `{x}` uses a back-reference, so the captures must be the same and only one value is retained. | Captures may differ. The direct `Map<String,String>` overwrites earlier values with the last capture, while Jakarta REST internals can retain all captures. | Avoid repeated names in portable direct routes; give each segment a unique name. |
| Graceful shutdown result | `stop(duration, unit)` returns `false` after clean shutdown and `true` after timeout, contrary to its Javadoc. | Returns `true` after clean shutdown and `false` when requests do not finish before the timeout. | Remove any 2.x compensation and test both branches when upgrading. |

The core direct-handler contracts remain: registration-order execution, `MuHandler` true/false stop semantics, a matched `RouteHandler` stopping the chain, context-relative routing, one request-body consumer, and response commitment rules. Do not rewrite working handlers merely because the major version changed; focus verification on the rows above and on the application's exact HTTP behavior.
