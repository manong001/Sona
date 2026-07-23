package cc.eu.sosee.sona.library;

import cc.eu.sosee.sona.personal.DirectoryPlaylistService;
import java.io.IOException;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Consumer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.core.task.TaskExecutor;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

@Service
public class ScanCoordinator {

    private static final Logger LOGGER = LoggerFactory.getLogger(ScanCoordinator.class);

    private final LibraryScanner libraryScanner;
    private final DirectoryPlaylistService directoryPlaylistService;
    private final TaskExecutor taskExecutor;
    private final TaskExecutor downloadImportTaskExecutor;
    private final AtomicReference<ScanStatus> status = new AtomicReference<>(ScanStatus.idle());
    private final AtomicBoolean rerunRequested = new AtomicBoolean();
    private final AtomicReference<String> rerunDirectory = new AtomicReference<>();
    private final AtomicReference<ScrapeMode> rerunMode = new AtomicReference<>();
    private final AtomicReference<String> rerunTrackLabel = new AtomicReference<>();
    private final AtomicReference<List<String>> rerunTrackIds = new AtomicReference<>();

    ScanCoordinator(
        LibraryScanner libraryScanner,
        DirectoryPlaylistService directoryPlaylistService,
        @Qualifier("scanTaskExecutor") TaskExecutor scanTaskExecutor,
        @Qualifier("downloadImportTaskExecutor") TaskExecutor downloadImportTaskExecutor
    ) {
        this.libraryScanner = libraryScanner;
        this.directoryPlaylistService = directoryPlaylistService;
        this.taskExecutor = scanTaskExecutor;
        this.downloadImportTaskExecutor = downloadImportTaskExecutor;
    }

    synchronized ScanStatus start() {
        return start("", ScrapeMode.STANDARD);
    }

    synchronized ScanStatus start(String relativeDirectory) {
        return start(relativeDirectory, ScrapeMode.STANDARD);
    }

    synchronized ScanStatus start(String relativeDirectory, ScrapeMode mode) {
        if (status.get().state() == ScanStatus.State.RUNNING) {
            rerunDirectory.set(relativeDirectory);
            rerunMode.set(mode);
            rerunTrackLabel.set(null);
            rerunTrackIds.set(null);
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
                    var totalDirectories = directories.size();
                    for (var index = 0; index < totalDirectories; index++) {
                        var directory = directories.get(index);
                        var completedDirectoryCount = index;
                        status.set(ScanStatus.running(
                            result, ScanStatus.Phase.SCANNING_FILES, directory,
                            completedDirectoryCount, totalDirectories
                        ));
                        try {
                            var completedResult = result;
                            result = add(result, scan(
                                directory,
                                mode,
                                progress -> status.set(ScanStatus.running(
                                    add(completedResult, progress),
                                    ScanStatus.Phase.SCANNING_FILES, directory,
                                    completedDirectoryCount, totalDirectories
                                ))
                            ));
                            errors.addAll(libraryScanner.lastErrors());
                            status.set(ScanStatus.running(
                                result, ScanStatus.Phase.SYNCING_PLAYLIST, directory,
                                completedDirectoryCount, totalDirectories
                            ));
                            directoryPlaylistService.sync(directory);
                        } catch (ResponseStatusException exception) {
                            if (exception.getStatusCode().value() != 404) {
                                throw exception;
                            }
                            result = add(result, new ScanResult(0, 0, 0, 0, 1));
                            errors.add(directory + "：目录已不存在，已跳过");
                        }
                        status.set(ScanStatus.running(
                            result, ScanStatus.Phase.SCANNING_FILES, null,
                            completedDirectoryCount + 1, totalDirectories
                        ));
                    }
                    status.set(ScanStatus.running(
                        result, ScanStatus.Phase.FINALIZING, null,
                        totalDirectories, totalDirectories
                    ));
                    result = add(result, new ScanResult(
                        0, 0, libraryScanner.removeMissingTracks(), 0, 0
                    ));
                    status.set(ScanStatus.completed(result, errors, totalDirectories));
                } else {
                    status.set(ScanStatus.running(
                        result, ScanStatus.Phase.SCANNING_FILES, relativeDirectory, 0, 1
                    ));
                    result = scan(
                        relativeDirectory,
                        mode,
                        progress -> status.set(ScanStatus.running(
                            progress, ScanStatus.Phase.SCANNING_FILES, relativeDirectory, 0, 1
                        ))
                    );
                    errors.addAll(libraryScanner.lastErrors());
                    status.set(ScanStatus.running(
                        result, ScanStatus.Phase.SYNCING_PLAYLIST, relativeDirectory, 0, 1
                    ));
                    directoryPlaylistService.sync(relativeDirectory);
                    status.set(ScanStatus.completed(result, errors, 1));
                }
            } catch (Exception exception) {
                status.set(ScanStatus.failed(exception, status.get()));
            } finally {
                runRequestedRerun();
            }
        });
        return status.get();
    }

    public synchronized ScanStatus forceOverwriteTracks(String label, List<String> trackIds) {
        if (status.get().state() == ScanStatus.State.RUNNING) {
            rerunDirectory.set(null);
            rerunMode.set(null);
            rerunTrackLabel.set(label);
            rerunTrackIds.set(List.copyOf(trackIds));
            rerunRequested.set(true);
            return status.get();
        }
        var displayLabel = label == null || label.isBlank() ? "歌单" : label.strip();
        status.set(ScanStatus.running(
            new ScanResult(0, 0, 0, 0, 0), ScanStatus.Phase.SCANNING_FILES,
            displayLabel, 0, 1
        ));
        taskExecutor.execute(() -> {
            try {
                var result = libraryScanner.scanTrackIds(
                    trackIds, ScrapeMode.FORCE_OVERWRITE,
                    progress -> status.set(ScanStatus.running(
                        progress, ScanStatus.Phase.SCANNING_FILES, displayLabel, 0, 1
                    ))
                );
                status.set(ScanStatus.running(
                    result, ScanStatus.Phase.FINALIZING, displayLabel, 0, 1
                ));
                status.set(ScanStatus.completed(result, libraryScanner.lastErrors(), 1));
            } catch (Exception exception) {
                status.set(ScanStatus.failed(exception, status.get()));
            } finally {
                runRequestedRerun();
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

    public CompletableFuture<ScanResult> enqueueFiles(
        String relativeDirectory, List<Path> files
    ) {
        var result = new CompletableFuture<ScanResult>();
        try {
            downloadImportTaskExecutor.execute(() -> {
                try {
                    var scanResult = libraryScanner.scanFiles(files);
                    directoryPlaylistService.sync(relativeDirectory);
                    result.complete(scanResult);
                    enqueueEnrichment(files);
                } catch (Exception exception) {
                    result.completeExceptionally(exception);
                }
            });
        } catch (RuntimeException exception) {
            result.completeExceptionally(exception);
        }
        return result;
    }

    private void enqueueEnrichment(List<Path> files) {
        try {
            taskExecutor.execute(() -> {
                try {
                    libraryScanner.enrichFiles(files);
                } catch (RuntimeException exception) {
                    LOGGER.warn("下载歌曲后台增强失败", exception);
                }
            });
        } catch (RuntimeException exception) {
            LOGGER.warn("无法提交下载歌曲后台增强任务", exception);
        }
    }

    public void trigger() {
        start();
    }

    private void runRequestedRerun() {
        if (!rerunRequested.getAndSet(false)) {
            return;
        }
        var trackIds = rerunTrackIds.getAndSet(null);
        if (trackIds != null) {
            forceOverwriteTracks(rerunTrackLabel.getAndSet(null), trackIds);
            return;
        }
        start(rerunDirectory.getAndSet(null), rerunMode.getAndSet(null));
    }

    private ScanResult scan(
        String relativeDirectory, ScrapeMode mode, Consumer<ScanResult> progress
    ) throws IOException {
        return mode == ScrapeMode.STANDARD
            ? libraryScanner.scan(relativeDirectory, progress)
            : libraryScanner.scan(relativeDirectory, mode, progress);
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
