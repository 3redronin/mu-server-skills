import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.WebSocket;
import java.net.http.WebSocketHandshakeException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Arrays;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.TimeUnit;

public final class WebSocketProbe {
    private static final byte[] EXPECTED_BINARY = "binary-payload".getBytes(StandardCharsets.UTF_8);

    public static void main(String[] args) throws Exception {
        URI uri = URI.create(args[0]);
        HttpClient client = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .build();

        RecordingListener listener = new RecordingListener();
        WebSocket socket = client.newWebSocketBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .subprotocols("chat.v1", "chat.v2")
            .buildAsync(uri, listener)
            .get(10, TimeUnit.SECONDS);

        require("chat.v1".equals(socket.getSubprotocol()),
            "expected negotiated subprotocol chat.v1 but got " + socket.getSubprotocol());

        socket.sendText("he", false).get(5, TimeUnit.SECONDS);
        socket.sendText("llo", true).get(5, TimeUnit.SECONDS);
        require("HELLO".equals(listener.text.get(10, TimeUnit.SECONDS)),
            "fragmented text was not delivered once as HELLO");

        socket.sendBinary(ByteBuffer.wrap(Arrays.copyOfRange(EXPECTED_BINARY, 0, 7)), false)
            .get(5, TimeUnit.SECONDS);
        socket.sendBinary(ByteBuffer.wrap(Arrays.copyOfRange(EXPECTED_BINARY, 7, EXPECTED_BINARY.length)), true)
            .get(5, TimeUnit.SECONDS);
        require(Arrays.equals(EXPECTED_BINARY, listener.binary.get(10, TimeUnit.SECONDS)),
            "fragmented binary was not echoed as one logical message");

        byte[] ping = "probe".getBytes(StandardCharsets.UTF_8);
        socket.sendPing(ByteBuffer.wrap(ping)).get(5, TimeUnit.SECONDS);
        require(Arrays.equals(ping, listener.pong.get(10, TimeUnit.SECONDS)),
            "pong payload did not match ping payload");

        socket.sendClose(WebSocket.NORMAL_CLOSURE, "probe complete").get(5, TimeUnit.SECONDS);
        require(listener.closeCode.get(10, TimeUnit.SECONDS) == WebSocket.NORMAL_CLOSURE,
            "peer close handshake did not complete with 1000");

        try {
            client.newWebSocketBuilder()
                .connectTimeout(Duration.ofSeconds(5))
                .subprotocols("unsupported.v1")
                .buildAsync(uri, new RecordingListener())
                .join();
            throw new AssertionError("unsupported subprotocol unexpectedly connected");
        } catch (CompletionException expected) {
            require(expected.getCause() instanceof WebSocketHandshakeException,
                "unsupported subprotocol did not fail as an HTTP handshake rejection: " + expected.getCause());
            WebSocketHandshakeException rejection = (WebSocketHandshakeException) expected.getCause();
            require(rejection.getResponse().statusCode() == 400,
                "unsupported subprotocol returned " + rejection.getResponse().statusCode() + " rather than 400");
        }

        System.out.println("PASS: subprotocol, fragmented text/binary, ping/pong, and close behavior verified");
    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    private static final class RecordingListener implements WebSocket.Listener {
        private final StringBuilder textParts = new StringBuilder();
        private byte[] binaryParts = new byte[0];
        private final CompletableFuture<String> text = new CompletableFuture<>();
        private final CompletableFuture<byte[]> binary = new CompletableFuture<>();
        private final CompletableFuture<byte[]> pong = new CompletableFuture<>();
        private final CompletableFuture<Integer> closeCode = new CompletableFuture<>();

        @Override
        public void onOpen(WebSocket webSocket) {
            webSocket.request(1);
        }

        @Override
        public CompletionStage<?> onText(WebSocket webSocket, CharSequence data, boolean last) {
            textParts.append(data);
            if (last) {
                text.complete(textParts.toString());
            }
            webSocket.request(1);
            return null;
        }

        @Override
        public CompletionStage<?> onBinary(WebSocket webSocket, ByteBuffer data, boolean last) {
            byte[] incoming = new byte[data.remaining()];
            data.get(incoming);
            byte[] combined = Arrays.copyOf(binaryParts, binaryParts.length + incoming.length);
            System.arraycopy(incoming, 0, combined, binaryParts.length, incoming.length);
            binaryParts = combined;
            if (last) {
                binary.complete(binaryParts);
            }
            webSocket.request(1);
            return null;
        }

        @Override
        public CompletionStage<?> onPong(WebSocket webSocket, ByteBuffer message) {
            byte[] incoming = new byte[message.remaining()];
            message.get(incoming);
            pong.complete(incoming);
            webSocket.request(1);
            return null;
        }

        @Override
        public CompletionStage<?> onClose(WebSocket webSocket, int statusCode, String reason) {
            closeCode.complete(statusCode);
            return null;
        }

        @Override
        public void onError(WebSocket webSocket, Throwable error) {
            text.completeExceptionally(error);
            binary.completeExceptionally(error);
            pong.completeExceptionally(error);
            closeCode.completeExceptionally(error);
        }
    }
}
