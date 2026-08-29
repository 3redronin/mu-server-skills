package example;

import io.muserver.AsyncHandle;
import io.muserver.AsyncSsePublisher;
import io.muserver.ContentTypes;
import io.muserver.DoneCallback;
import io.muserver.Method;
import io.muserver.MuServer;
import io.muserver.RequestBodyListener;

import java.nio.ByteBuffer;
import java.util.concurrent.TimeUnit;

import static io.muserver.MuServerBuilder.httpServer;

public final class Main {
    public static void main(String[] args) {
        MuServer server = httpServer()
            .withHttpPort(8184)
            .addHandler(Method.GET, "/health", (request, response, pathParams) ->
                response.write("healthy"))
            .addHandler(Method.POST, "/mirror", (request, response, pathParams) -> {
                response.contentType(ContentTypes.APPLICATION_OCTET_STREAM);
                AsyncHandle handle = request.handleAsync();
                handle.setReadListener(new RequestBodyListener() {
                    @Override
                    public void onDataReceived(ByteBuffer buffer, DoneCallback doneCallback) throws Exception {
                        // BUG: the write still owns buffer when demand releases it back to the transport.
                        handle.write(buffer);
                        doneCallback.onComplete(null);
                    }

                    @Override
                    public void onComplete() {
                        handle.complete();
                    }

                    @Override
                    public void onError(Throwable error) {
                        handle.complete(error);
                    }
                });
            })
            .addHandler(Method.GET, "/events", (request, response, pathParams) -> {
                AsyncSsePublisher publisher = AsyncSsePublisher.start(request, response);
                // BUG: these writes are queued without observing failure/backpressure, then closed immediately.
                publisher.sendComment("ready");
                publisher.setClientReconnectTime(2, TimeUnit.SECONDS);
                for (int i = 1; i <= 3; i++) {
                    publisher.send("value-" + i, "tick", Integer.toString(i));
                }
                publisher.close();
            })
            .start();

        System.out.println("Started at " + server.uri());
    }
}
