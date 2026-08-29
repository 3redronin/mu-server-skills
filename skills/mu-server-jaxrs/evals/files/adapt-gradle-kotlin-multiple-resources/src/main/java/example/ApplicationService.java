package example;

import java.util.concurrent.atomic.AtomicInteger;

public final class ApplicationService {
    private final AtomicInteger requestNumber = new AtomicInteger();

    public String health() {
        return "healthy";
    }

    public String greet(String name) {
        return "Hello, " + name;
    }

    public int nextRequestNumber() {
        return requestNumber.incrementAndGet();
    }
}
