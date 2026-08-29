# Async lifecycle and flow control

Read this reference for any direct handler using `handleAsync()`, asynchronous response writes, or `RequestBodyListener`.

## Exchange ownership

`MuRequest.handleAsync()` is idempotent for a request and marks it asynchronous. Once called, Mu no longer completes the response when the handler returns. A general `MuHandler` cannot return `false` after entering async mode; doing so is rejected because no later handler may own the response. The routed `addHandler(Method, path, RouteHandler)` adapter returns `true` after a matched route.

Call `complete()` only after the last write has completed. Make application termination idempotent because normal completion, producer failure, a write failure, timeout, disconnect, and shutdown can race:

```java
final AtomicBoolean ended = new AtomicBoolean();

void succeed(AsyncHandle handle) {
    if (ended.compareAndSet(false, true)) {
        handle.complete();
    }
}

void fail(AsyncHandle handle, Throwable error) {
    cancelUpstream();
    if (ended.compareAndSet(false, true)) {
        handle.complete(error);
    }
}
```

Do not use the atomic flag as a write queue. If multiple threads can produce output, serialize them through one bounded application queue or one continuation chain, and define overload behavior rather than accepting unlimited events.

## Response write ownership

Both `AsyncHandle.write(ByteBuffer, DoneCallback)` and `write(ByteBuffer)` are non-blocking. Their completion means Mu has finished the write or detected failure; it is the point at which the producer may reuse the buffer and request or generate the next chunk.

Use a pump with one write in flight:

```java
void writeChunk(AsyncHandle handle, ByteBuffer buffer) {
    handle.write(buffer, error -> {
        if (error != null) {
            fail(handle, error);
            return;
        }
        buffer.clear();             // safe only now
        readNextChunk(buffer);      // eventually calls writeChunk again or succeed
    });
}
```

Mu's HTTP/1 channel backpressure can delay the callback while the channel is not writable. The callback is therefore a useful demand boundary, not permission to enqueue many writes in advance. A future-returning write supplies the same boundary; do not call `Future.get()` on an I/O thread.

Set response status and headers first. The first write changes the response to streaming and commits metadata. If an exception happens before that point, `complete(error)` can use Mu's exception handling and possibly send an error response. Once bytes have started, status and headers cannot repair the response; stop the producer and terminate it as failed. Never send a second application error body into a partially written binary or event stream.

## Request-body demand and buffer lifetime

`setReadListener` claims the request body. Do not also call `inputStream()`, `readBodyAsString()`, `form()`, or another body reader. Mu still enforces its configured maximum request size.

For each non-empty body segment, `onDataReceived` receives a buffer plus a `DoneCallback`. The buffer remains owned by that callback:

- Call the callback exactly once. Omitting it stalls the request and retains the input buffer; calling it twice can release transport state twice.
- Calling it with `null` requests more data. Calling it with an error fails body processing.
- Do not retain or read the buffer after the callback. If work must outlive acknowledgment, copy only the needed bytes before acknowledging.
- The callback must cover all asynchronous use. A zero-copy echo can pass both objects directly to `handle.write(buffer, doneCallback)` because the input is released only when the response write finishes.
- `onComplete` runs only after the last input buffer has been acknowledged. If it sends a final response chunk, complete from that chunk's write callback rather than racing it.
- `onError` means no more input should be expected. Cancel dependent work and enter the same idempotent terminal path used by write and producer failures.

The listener methods run on Mu's socket I/O thread. Perform only lightweight coordination there. If processing is offloaded, bound the executor/queue, keep the callback outstanding until processing no longer needs the buffer, and preserve body order.

## Completion and cancellation

Add the response-completion handler before publishing work that might finish quickly. The current implementation attaches a state listener; it is not a replay API for terminal events that occurred before registration.

```java
AsyncHandle handle = request.handleAsync();
handle.addResponseCompleteHandler(info -> {
    cancelUpstream();
    releasePerRequestResources();
    if (!info.completedSuccessfully()) {
        recordTransportCancellation();
    }
});
```

Keep this callback non-blocking. `completedSuccessfully()` means the full request was read and the full response was sent. A fully delivered HTTP `500` still counts as transport success; disconnects, idle timeouts, and truncated output do not. A disconnected peer also causes pending or later writes to fail, but a silent dead connection may not be noticed until the server reads or writes again.

## Mu Server 2.x and 3.x

The direct `AsyncHandle`, `RequestBodyListener`, `SsePublisher`, and `AsyncSsePublisher` model remains available in Mu Server 3. Relative to 2.4.1, the relevant public direct APIs primarily gain JSpecify nullness declarations; do not infer a new copying, concurrency, or backpressure guarantee from the major upgrade. Mu Server 3 requires Java 11 and uses SLF4J 2.

Mu Server 3's synchronous direct `SsePublisher` restores the thread interrupt flag if its blocking send is interrupted before throwing `IOException`; 2.4.1 wraps interruption without that restoration. Code that catches the exception should still stop publishing and preserve its own cancellation semantics.

Evidence: [Mu async documentation](https://muserver.io/async), [`AsyncHandle` source](https://github.com/3redronin/mu-server/blob/master/src/main/java/io/muserver/AsyncHandle.java), [`RequestBodyListener` source](https://github.com/3redronin/mu-server/blob/master/src/main/java/io/muserver/RequestBodyListener.java), and [Mu Server 3 migration notes](https://muserver.io/changelog/mu-server-3).
