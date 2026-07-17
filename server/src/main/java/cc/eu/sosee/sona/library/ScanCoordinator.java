package cc.eu.sosee.sona.library;

import cc.eu.sosee.sona.personal.DirectoryPlaylistService;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.atomic.AtomicBoolean;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.core.task.TaskExecutor;
import org.springframework.stereotype.Service;

@Service
public class ScanCoordinator {

    private final LibraryScanner libraryScanner;
    private final DirectoryPlaylistService directoryPlaylistService;
    private final TaskExecutor taskExecutor;
    private final AtomicReference<ScanStatus> status = new AtomicReference<>(ScanStatus.idle());
    private final AtomicBoolean rerunRequested = new AtomicBoolean();
    private final AtomicReference<String> rerunDirectory = new AtomicReference<>();

    ScanCoordinator(
        LibraryScanner libraryScanner,
        DirectoryPlaylistService directoryPlaylistService,
        @Qualifier("scanTaskExecutor") TaskExecutor scanTaskExecutor
    ) {
        this.libraryScanner = libraryScanner;
        this.directoryPlaylistService = directoryPlaylistService;
        this.taskExecutor = scanTaskExecutor;
    }

    synchronized ScanStatus start() {
        return start("");
    }

    synchronized ScanStatus start(String relativeDirectory) {
        if (status.get().state() == ScanStatus.State.RUNNING) {
            rerunDirectory.set(relativeDirectory);
            rerunRequested.set(true);
            return status.get();
        }
        status.set(ScanStatus.running());
        taskExecutor.execute(() -> {
            try {
                var result = libraryScanner.scan(relativeDirectory);
                directoryPlaylistService.sync();
                status.set(ScanStatus.completed(result, libraryScanner.lastErrors()));
            } catch (Exception exception) {
                status.set(ScanStatus.failed(exception));
            } finally {
                if (rerunRequested.getAndSet(false)) {
                    start(rerunDirectory.getAndSet(null));
                }
            }
        });
        return status.get();
    }

    ScanStatus status() {
        return status.get();
    }

    public CompletableFuture<ScanResult> enqueue(String relativeDirectory) {
        var result = new CompletableFuture<ScanResult>();
        try {
            taskExecutor.execute(() -> {
                try {
                    var scanResult = libraryScanner.scan(relativeDirectory);
                    directoryPlaylistService.sync();
                    result.complete(scanResult);
                } catch (Exception exception) {
                    result.completeExceptionally(exception);
                }
            });
        } catch (RuntimeException exception) {
            result.completeExceptionally(exception);
        }
        return result;
    }

    public void trigger() {
        start();
    }
}
