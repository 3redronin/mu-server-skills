package example;

import io.muserver.BaseWebSocket;
import io.muserver.DoneCallback;
import io.muserver.Method;
import io.muserver.MuServer;
import io.muserver.MuServerBuilder;
import io.muserver.WebSocketHandlerBuilder;

import java.nio.ByteBuffer;

public final class Main {
    private Main() {
    }

    public static void main(String[] args) {
        MuServer server = MuServerBuilder.httpServer()
            .withHttpPort(8189)
            .addHandler(Method.GET, "/health", (request, response, pathParams) -> response.write("healthy"))
            .addHandler(WebSocketHandlerBuilder.webSocketHandler((request, responseHeaders) ->
                new BaseWebSocket() {
                    @Override
                    public void onText(String message, boolean isLast, DoneCallback onComplete) {
                        session().sendText(message.toUpperCase(), isLast, onComplete);
                    }

                    @Override
                    public void onBinary(ByteBuffer buffer, boolean isLast, DoneCallback onComplete) {
                        session().sendBinary(buffer, isLast, onComplete);
                    }
                }
            ).withPath("/ws"))
            .addHandler(Method.GET, "/ws", (request, response, pathParams) -> response.write("websocket endpoint"))
            .start();

        Runtime.getRuntime().addShutdownHook(new Thread(server::stop));
        System.out.println("Started at " + server.uri());
    }
}
