package cc.eu.sosee.sona.library;

import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.AtomicBoolean;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.core.task.TaskExecutor;
import org.springframework.stereotype.Service;

@Service
public class ScanCoordinator {

    private final LibraryScanner libraryScanner;
    private final TaskExecutor taskExecutor;
    private final AtomicReference<ScanStatus> status = new AtomicReference<>(ScanStatus.idle());
    private final AtomicBoolean rerunRequested = new AtomicBoolean();

    ScanCoordinator(
        LibraryScanner libraryScanner,
        @Qualifier("scanTaskExecutor") TaskExecutor scanTaskExecutor
    ) {
        this.libraryScanner = libraryScanner;
        this.taskExecutor = scanTaskExecutor;
    }

    synchronized ScanStatus start() {
        if (status.get().state() == ScanStatus.State.RUNNING) {
            rerunRequested.set(true);
            return status.get();
        }
        status.set(ScanStatus.running());
        taskExecutor.execute(() -> {
            try {
                status.set(ScanStatus.completed(libraryScanner.scan()));
            } catch (Exception exception) {
                status.set(ScanStatus.failed(exception));
            } finally {
                if (rerunRequested.getAndSet(false)) {
                    start();
                }
            }
        });
        return status.get();
    }

    ScanStatus status() {
        return status.get();
    }

    public void trigger() {
        start();
    }
}
