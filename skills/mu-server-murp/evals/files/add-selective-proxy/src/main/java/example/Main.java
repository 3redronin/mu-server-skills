package example;

import io.muserver.Method;
import io.muserver.MuServer;
import io.muserver.MuServerBuilder;

public final class Main {
    public static void main(String[] args) {
        MuServer server = MuServerBuilder.httpServer()
            .withHttpPort(8187)
            .addHandler(Method.GET, "/health", (request, response, pathParams) ->
                response.write("healthy"))
            .start();
        System.out.println("Application started at " + server.uri());
    }
}
