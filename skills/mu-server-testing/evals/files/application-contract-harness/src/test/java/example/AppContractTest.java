package example;

import io.muserver.ContentTypes;
import io.muserver.HeaderNames;
import io.muserver.Method;
import io.muserver.MuServer;
import io.muserver.MuServerBuilder;
import io.muserver.ResponseInfo;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AppContractTest {
    private static final byte[] CONTRACT_BODY = "ok-\u03bc".getBytes(StandardCharsets.UTF_8);

    private final HttpClient client = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(2))
        .followRedirects(HttpClient.Redirect.NEVER)
        .build();
    private final CountDownLatch completion = new CountDownLatch(1);
    private final AtomicReference<ResponseInfo> completionInfo = new AtomicReference<>();

    private MuServer server;
    private URI baseUri;

    @BeforeEach
    void startServer() {
        server = MuServerBuilder.httpServer()
            .withInterface("127.0.0.1")
            .withMaxRequestSize(64)
            .addResponseCompleteListener(info -> {
                if ("/complete".equals(info.request().uri().getPath())) {
                    completionInfo.set(info);
                    completion.countDown();
                }
            })
            .addHandler(Method.GET, "/contract", (request, response, pathParams) -> {
                response.contentType(ContentTypes.APPLICATION_OCTET_STREAM);
                response.headers().add("X-Value", "one").add("X-Value", "two");
                try (OutputStream body = response.outputStream()) {
                    body.write(CONTRACT_BODY);
                }
            })
            .addHandler(Method.HEAD, "/contract", (request, response, pathParams) -> {
                response.contentType(ContentTypes.APPLICATION_OCTET_STREAM);
                response.headers().set(HeaderNames.CONTENT_LENGTH, CONTRACT_BODY.length);
            })
            .addHandler(Method.GET, "/old", (request, response, pathParams) -> response.redirect("/contract"))
            .addHandler(Method.GET, "/complete", (request, response, pathParams) -> response.write("done"))
            .addHandler(Method.GET, "/request-headers", (request, response, pathParams) ->
                response.write(String.join("|", request.headers().getAll("X-Dup"))))
            .addHandler(Method.POST, "/echo", (request, response, pathParams) ->
                response.write(request.readBodyAsString()))
            .start();
        baseUri = server.uri();
    }

    @AfterEach
    void stopServer() {
        if (server != null) {
            server.stop();
        }
    }

    @Test
    void assertsStatusRepeatedHeadersAndExactBytes() throws Exception {
        HttpResponse<InputStream> response = client.send(
            request("/contract").GET().build(),
            HttpResponse.BodyHandlers.ofInputStream());

        try (InputStream body = response.body()) {
            assertEquals(200, response.statusCode());
            assertEquals(ContentTypes.APPLICATION_OCTET_STREAM.toString(),
                response.headers().firstValue("Content-Type").orElseThrow());
            assertEquals(List.of("one", "two"), response.headers().allValues("X-Value"));
            assertArrayEquals(CONTRACT_BODY, body.readAllBytes());
        }
    }

    @Test
    void headHasHeadersButNoBodyBytes() throws Exception {
        HttpResponse<byte[]> response = client.send(
            request("/contract")
                .method("HEAD", HttpRequest.BodyPublishers.noBody())
                .build(),
            HttpResponse.BodyHandlers.ofByteArray());

        assertEquals(200, response.statusCode());
        assertEquals(CONTRACT_BODY.length,
            response.headers().firstValueAsLong("Content-Length").orElseThrow());
        assertEquals(0, response.body().length);
    }

    @Test
    void redirectIsObservedRatherThanFollowed() throws Exception {
        HttpResponse<Void> response = client.send(
            request("/old").GET().build(),
            HttpResponse.BodyHandlers.discarding());

        assertEquals(302, response.statusCode());
        assertEquals(baseUri.resolve("/contract").toString(),
            response.headers().firstValue("Location").orElseThrow());
    }

    @Test
    void waitsForServerSideResponseCompletion() throws Exception {
        HttpResponse<String> response = client.send(
            request("/complete").GET().build(),
            HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));

        assertEquals("done", response.body());
        assertTrue(completion.await(2, TimeUnit.SECONDS), "response-complete listener timed out");
        assertTrue(completionInfo.get().completedSuccessfully());
    }

    @Test
    void requestSizeLimitIsVisibleOverHttp() throws Exception {
        byte[] tooLarge = new byte[65];
        HttpResponse<Void> response = client.send(
            request("/echo")
                .POST(HttpRequest.BodyPublishers.ofByteArray(tooLarge))
                .build(),
            HttpResponse.BodyHandlers.discarding());

        assertEquals(413, response.statusCode());
    }

    @Test
    void rawSocketPreservesRepeatedRequestHeaders() throws Exception {
        String request = "GET /request-headers HTTP/1.1\r\n"
            + "Host: " + baseUri.getAuthority() + "\r\n"
            + "X-Dup: one\r\n"
            + "X-Dup: two\r\n"
            + "Connection: close\r\n\r\n";

        String response = sendRaw(request);
        assertTrue(response.startsWith("HTTP/1.1 200 OK\r\n"), response);
        assertTrue(response.endsWith("one|two"), response);
    }

    @Test
    void rawSocketCanExerciseARequestAClientWouldRepair() throws Exception {
        String requestWithoutHost = "GET /contract HTTP/1.1\r\nConnection: close\r\n\r\n";

        String response = sendRaw(requestWithoutHost);
        assertTrue(response.startsWith("HTTP/1.1 400 Bad Request\r\n"), response);
    }

    private String sendRaw(String request) throws Exception {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(baseUri.getHost(), baseUri.getPort()), 2_000);
            socket.setSoTimeout(2_000);
            socket.getOutputStream().write(request.getBytes(StandardCharsets.US_ASCII));
            socket.getOutputStream().flush();
            return new String(socket.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    private HttpRequest.Builder request(String path) {
        return HttpRequest.newBuilder(baseUri.resolve(path)).timeout(Duration.ofSeconds(3));
    }
}
