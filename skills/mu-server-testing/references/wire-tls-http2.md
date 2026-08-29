# Wire, TLS, and HTTP/2 tests

Read this reference only when a normal HTTP client changes the input, or when HTTPS, ALPN, HTTP/2, or mutual TLS is part of the application contract.

## Raw HTTP/1.1

Use a socket for cases such as malformed request lines, invalid header syntax, forbidden or duplicate headers a client refuses to send, conflicting framing, partial/truncated bodies, and deliberate connection closure. Normal endpoint behavior belongs in the high-level client suite.

A raw request uses bytes and CRLF, includes the correct authority unless missing/invalid `Host` is the case under test, and bounds every operation:

```java
try (Socket socket = new Socket()) {
    socket.connect(new InetSocketAddress(server.uri().getHost(), server.uri().getPort()), 2_000);
    socket.setSoTimeout(2_000);
    String request = "GET /probe HTTP/1.1\r\n"
        + "Host: " + server.uri().getAuthority() + "\r\n"
        + "Connection: close\r\n\r\n";
    socket.getOutputStream().write(request.getBytes(StandardCharsets.US_ASCII));
    socket.getOutputStream().flush();
    // Parse/assert the bounded response bytes needed by the test.
}
```

Use US-ASCII for request-line/header syntax and explicit bytes for bodies. Deliberately half-close or close the request side for truncation/disconnect cases. Read only to a bounded size/deadline; an error response may close the connection, and the test must not assume that connection remains reusable. When checking a framing error, allow only the interoperability outcomes supported by the target Mu version and transport, and explain any permitted alternative precisely.

## HTTPS trust

Create a test CA or test certificate, then construct a client `SSLContext` whose trust manager trusts only that CA/certificate. Keep it on the client instance used by that test. Avoid modifying `HttpsURLConnection` defaults, `SSLContext.setDefault`, or global hostname verification: those changes leak into unrelated parallel tests and can hide hostname or chain failures.

Use `server.httpsUri()` only after checking that the selected builder created an HTTPS connector. Mu Server 3 makes this nullable contract explicit with JSpecify; `server.uri()` remains the convenient HTTPS-preferred, otherwise-HTTP URI.

For client-certificate tests, create separate client identities for accepted, absent, expired/untrusted, and wrong-identity paths, and keep both server trust and client key material narrowly scoped. Use the production or Murp client-certificate guidance for certificate extraction and trusted-proxy boundaries.

## HTTP/2 and ALPN

Mu Server supports HTTP/2 over HTTPS, not clear-text h2c. Enable it through the application's `Http2ConfigBuilder` configuration and use a client that can negotiate ALPN. Assert the negotiated protocol through the client or connection observation; a successful HTTPS response alone does not prove HTTP/2.

Run the same application contract over HTTP/1.1 and HTTP/2 where both are supported, then add protocol-specific cases for concurrent streams, flow control, stream reset, forbidden connection-specific headers, and graceful connection shutdown only when relevant. Keep certificate trust scoped as above. A raw TCP HTTP/1 test cannot validate HTTP/2 frames; use a real HTTP/2 client or a deliberately specialized frame harness.
