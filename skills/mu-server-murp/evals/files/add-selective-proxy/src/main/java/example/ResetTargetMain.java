package example;

import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketTimeoutException;

public final class ResetTargetMain {
    public static void main(String[] args) throws Exception {
        try (ServerSocket server = new ServerSocket()) {
            server.setReuseAddress(true);
            server.bind(new InetSocketAddress("127.0.0.1", 9191));
            server.setSoTimeout(5000);
            for (int i = 0; i < 3; i++) {
                try (Socket socket = server.accept()) {
                    socket.setSoLinger(true, 0);
                } catch (SocketTimeoutException ignored) {
                    return;
                }
            }
        }
    }
}
