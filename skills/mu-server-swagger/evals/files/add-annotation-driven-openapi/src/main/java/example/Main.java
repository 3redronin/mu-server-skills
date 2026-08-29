package example;

import io.muserver.MuServer;
import io.muserver.MuServerBuilder;
import io.muserver.rest.RestHandlerBuilder;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

public final class Main {
    public static void main(String[] args) {
        MuServerBuilder serverBuilder = MuServerBuilder.httpServer()
            .withHttpPort(8189);

        GreetingResource greetingResource = new GreetingResource();

        MuServer server = serverBuilder
            .addHandler(RestHandlerBuilder.restHandler(greetingResource))
            .start();

        System.out.println("Started at " + server.uri());
    }

    @Path("/hello")
    @Produces(MediaType.TEXT_PLAIN)
    public static final class GreetingResource {
        @GET
        @Path("/{name}")
        public String greet(@PathParam("name") String name) {
            return "Hello, " + name;
        }
    }
}
