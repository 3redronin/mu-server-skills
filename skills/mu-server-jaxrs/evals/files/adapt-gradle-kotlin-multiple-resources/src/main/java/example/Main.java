package example;

import io.muserver.Method;
import io.muserver.MuServer;
import io.muserver.MuServerBuilder;

public final class Main {
    public static void main(String[] args) {
        ApplicationService applicationService = new ApplicationService();

        MuServer server = MuServerBuilder.httpServer()
            .withHttpPort(8182)
            .addHandler(Method.GET, "/health", (request, response, pathParams) -> {
                response.write(applicationService.health());
            })
            .start();

        System.out.println("Started server at " + server.uri());
    }
}
