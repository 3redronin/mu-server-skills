package example;

import com.fasterxml.jackson.jaxrs.json.JacksonJsonProvider;
import io.muserver.MuServer;
import io.muserver.MuServerBuilder;
import io.muserver.rest.RestHandlerBuilder;
import javax.ws.rs.GET;
import javax.ws.rs.Path;
import javax.ws.rs.Produces;
import javax.ws.rs.core.MediaType;

public final class Main {
    public static void main(String[] args) {
        MuServerBuilder serverBuilder = MuServerBuilder.httpServer()
            .withHttpPort(8187);

        MessageResource resource = new MessageResource();
        JacksonJsonProvider jsonProvider = new JacksonJsonProvider();

        MuServer server = serverBuilder
            .addHandler(RestHandlerBuilder.restHandler(resource)
                .addCustomReader(jsonProvider)
                .addCustomWriter(jsonProvider))
            .start();

        System.out.println("Started at " + server.uri());
    }

    @Path("/api")
    @Produces(MediaType.APPLICATION_JSON)
    public static final class MessageResource {
        @GET
        @Path("/message")
        public Message message() {
            return new Message("ready", 1);
        }
    }

    public static final class Message {
        public final String status;
        public final int version;

        public Message(String status, int version) {
            this.status = status;
            this.version = version;
        }
    }
}
