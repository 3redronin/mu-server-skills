package example;

import io.muserver.ContentTypes;
import io.muserver.Method;
import io.muserver.MuServer;
import io.muserver.MuServerBuilder;
import io.muserver.handlers.ResourceHandlerBuilder;

import static io.muserver.ContextHandlerBuilder.context;

public final class Main {
    public static void main(String[] args) {
        MuServer server = MuServerBuilder.httpServer()
            .withHttpPort(8192)
            .addHandler(Method.GET, "/api/health", (request, response, pathParams) -> {
                response.contentType(ContentTypes.TEXT_PLAIN_UTF8);
                response.write("healthy");
            })
            // This deliberately incomplete fixture is the starting point for the eval.
            .addHandler(context("/app")
                .addHandler(ResourceHandlerBuilder
                    .fileOrClasspath("src/main/resources/public", "/public")
                    .withDirectoryListing(true)))
            .start();

        System.out.println("Started at " + server.uri());
    }
}
