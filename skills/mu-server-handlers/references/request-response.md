# Synchronous request and response contracts

Use these rules when implementing direct synchronous handlers. Treat all request values as untrusted and preserve an application's existing wire contract when adapting code.

## Read request data deliberately

| Input | API and observable behavior |
| --- | --- |
| Query | `request.query()` returns `RequestParameters`. HTML form-compatible decoding maps both `+` and `%20` to a space; use `request.uri().getRawQuery()` when the raw distinction matters. `get(name)` returns the first value or `null`; `getAll(name)` returns every value or an empty list. |
| Form | `request.form()` blocks until an `application/x-www-form-urlencoded` or `multipart/*` body is read, returns the same `RequestParameters` model, and consumes the body. Check the request media type and return the application's intended client error for unsupported content instead of calling `form()` indiscriminately. |
| Headers | `request.headers()` uses case-insensitive header names. `get` returns the first value, `getAll` preserves repeated field values, and parsers such as `contentType()`, `accept()`, and `forwarded()` are available. `request.contentType()` returns only the type/subtype string; `request.headers().contentType()` retains parameters such as `charset`. |
| Cookies | `request.cookie(name)` returns the first value as `Optional<String>`; `request.cookies()` returns the parsed cookie list. Cookie values are not automatically URL-decoded. |
| Text body | `readBodyAsString()` is blocking, returns `""` when there is no body, uses the declared charset, and defaults to UTF-8. Use it only for appropriately bounded text bodies. |
| Binary/large body | `inputStream()` returns `Optional.empty()` when headers do not indicate a body. Close a present stream. Reading is blocking and subject to the configured request size and read timeout. Async body processing is outside this skill. |

Only one request-body interpretation can own the body: `form()`, `readBodyAsString()`, or `inputStream()`. Do not inspect a body in an early filter and expect a later handler to reread it. Parse once and store the parsed result as a request attribute if later handlers need it.

`RequestParameters` typed getters return the supplied default for missing values and invalid numeric syntax. `getBoolean` is true, case-insensitively, for `true`, `on`, `yes`, and `1`; other or absent values are false. Do not use a default-returning getter when the contract must distinguish missing from malformed input—read the string and validate it explicitly.

The server-wide maximum request body is 24 MiB by default and applies to these readers, but applications should set and test a limit appropriate to the endpoint. A declared oversized body can be rejected before a normal exchange exists; a streaming body can fail while being consumed.

For multipart forms, `form()` reads text fields and `uploadedFile(name)`/`uploadedFiles(name)` access files. Validate count, filename, content type, and size according to the application; a missing single upload returns `null` and a missing list is empty.

## Construct the response before commitment

The default status is `200`. Set `status`, response headers, `contentType`, and cookies before a body method starts sending headers.

| Output | Contract |
| --- | --- |
| `write(String)` | Sends one fixed-length body and cannot be called twice or after another body-writing method. It respects a response charset and otherwise uses UTF-8. If no content type is set, it sets `text/plain;charset=utf-8`. |
| `writer()` | Returns a buffered UTF-8 `PrintWriter`, sets `text/plain;charset=utf-8` when absent, and is flushed/closed when a synchronous handler completes. An early `flush()` commits headers. |
| `outputStream()` | Returns a buffered byte stream that is flushed/closed at synchronous completion. Set an accurate media type explicitly. `outputStream(0)` is unbuffered. |
| `sendChunk(String)` | Sends immediately, may be called repeatedly, and starts a streamed response. Set the content type first: unlike `write` and `writer`, it does not add a default `Content-Type`. |
| `redirect(URI/String)` | Resolves a relative location against `request.uri()`, normalizes it, and sets `Location`. It uses `302` unless status is already `300`, `301`, `302`, or `303`. It does not add a response body. |

Choose one body-writing family. `sendChunk`, `writer`, and `outputStream` can commit before the handler returns; `hasStartedSendingData()` reports that boundary. After commitment, status cannot change and header mutations cannot change the already-sent wire headers.

If no body method is used, a handled ordinary response completes empty. Mu Server adds `Content-Length: 0` for most non-HEAD empty responses, but not for `204`, `205`, `304`, or HEAD under the corresponding rules. A direct HEAD route must be registered explicitly; response machinery suppresses its body.

If the application declares `Content-Length` while using streamed output, send exactly that many bytes. Too many or too few bytes is a response error and can make the connection unusable. Let `write(String)` calculate length for complete text responses.

## Send cookies safely

Create response cookies with `CookieBuilder`, then call `response.addCookie(cookie)`. `CookieBuilder.newSecureCookie()` and `Cookie.builder()` default to `Secure`, `HttpOnly`, and `SameSite=Strict`; `newCookie()` does not. Use `withUrlEncodedValue` for characters outside the cookie-value grammar and decode it explicitly when reading.

To delete a cookie, send the same name, path, and domain with an empty value and max age `0`. A different path or domain identifies a different cookie and will not delete the original.
