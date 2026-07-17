package cc.eu.sosee.sona.library;

import cc.eu.sosee.sona.personal.DirectoryPlaylistService;
import java.util.ArrayList;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.atomic.AtomicBoolean;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.core.task.TaskExecutor;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

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
                var errors = new ArrayList<String>();
                var result = new ScanResult(0, 0, 0, 0, 0);
                if (relativeDirectory == null || relativeDirectory.isBlank()) {
                    var directories = directoryPlaylistService.leafDirectoryPaths();
                    for (var directory : directories) {
                        try {
                            directoryPlaylistService.sync(directory);
                            var completedDirectories = result;
                            result = add(result, libraryScanner.scan(
                                directory,
                                progress -> status.set(ScanStatus.running(
                                    add(completedDirectories, progress)
                                ))
                            ));
                            errors.addAll(libraryScanner.lastErrors());
                            directoryPlaylistService.sync(directory);
                        } catch (ResponseStatusException exception) {
                            if (exception.getStatusCode().value() != 404) {
                                throw exception;
                            }
                            result = add(result, new ScanResult(0, 0, 0, 0, 1));
                            errors.add(directory + "：目录已不存在，已跳过");
                        }
                    }
                    result = add(result, new ScanResult(
                        0, 0, libraryScanner.removeMissingTracks(), 0, 0
                    ));
                    directoryPlaylistService.pruneStalePlaylists(directories);
                } else {
                    directoryPlaylistService.sync(relativeDirectory);
                    result = libraryScanner.scan(
                        relativeDirectory,
                        progress -> status.set(ScanStatus.running(progress))
                    );
                    errors.addAll(libraryScanner.lastErrors());
                    directoryPlaylistService.sync(relativeDirectory);
                }
                status.set(ScanStatus.completed(result, errors));
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
                    directoryPlaylistService.sync(relativeDirectory);
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

    private ScanResult add(ScanResult first, ScanResult second) {
        return new ScanResult(
            first.discovered() + second.discovered(),
            first.imported() + second.imported(),
            first.updated() + second.updated(),
            first.skipped() + second.skipped(),
            first.failed() + second.failed()
        );
    }
}
