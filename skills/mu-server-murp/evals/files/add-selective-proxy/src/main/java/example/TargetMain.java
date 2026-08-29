package example;

import io.muserver.MuServer;
import io.muserver.MuServerBuilder;

public final class TargetMain {
    public static void main(String[] args) {
        MuServer target = MuServerBuilder.httpServer()
            .withHttpPort(9191)
            .addHandler((request, response) -> {
                if (request.uri().getRawPath().equals("/backend/slow")) {
                    Thread.sleep(3000);
                }
                response.write(String.join("\n",
                    "method=" + request.method(),
                    "rawPath=" + request.uri().getRawPath(),
                    "rawQuery=" + request.uri().getRawQuery(),
                    "host=" + request.headers().get("host"),
                    "forwarded=" + request.headers().getAll("forwarded"),
                    "via=" + request.headers().getAll("via"),
                    "xForwardedFor=" + request.headers().get("x-forwarded-for"),
                    "body=" + request.readBodyAsString()));
                return true;
            })
            .start();
        System.out.println("Target started at " + target.uri());
    }
}
