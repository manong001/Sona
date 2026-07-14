package cc.eu.sosee.sona.library;

import java.util.concurrent.atomic.AtomicReference;
import org.springframework.core.task.TaskExecutor;
import org.springframework.stereotype.Service;

@Service
class ScanCoordinator {

    private final LibraryScanner libraryScanner;
    private final TaskExecutor taskExecutor;
    private final AtomicReference<ScanStatus> status = new AtomicReference<>(ScanStatus.idle());

    ScanCoordinator(LibraryScanner libraryScanner, TaskExecutor scanTaskExecutor) {
        this.libraryScanner = libraryScanner;
        this.taskExecutor = scanTaskExecutor;
    }

    synchronized ScanStatus start() {
        if (status.get().state() == ScanStatus.State.RUNNING) {
            return status.get();
        }
        status.set(ScanStatus.running());
        taskExecutor.execute(() -> {
            try {
                status.set(ScanStatus.completed(libraryScanner.scan()));
            } catch (Exception exception) {
                status.set(ScanStatus.failed(exception));
            }
        });
        return status.get();
    }

    ScanStatus status() {
        return status.get();
    }
}

