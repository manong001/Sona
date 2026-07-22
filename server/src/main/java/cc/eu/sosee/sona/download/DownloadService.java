package cc.eu.sosee.sona.download;

import cc.eu.sosee.sona.personal.PlaylistDownloadImportService;
import jakarta.annotation.PostConstruct;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.RejectedExecutionException;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.core.task.TaskExecutor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

@Service
class DownloadService {

    private final DownloaderGateway gateway;
    private final DownloadTaskRepository repository;
    private final TaskExecutor taskExecutor;
    private final PlaylistDownloadImportService playlistImportService;

    DownloadService(
        DownloaderGateway gateway,
        DownloadTaskRepository repository,
        PlaylistDownloadImportService playlistImportService,
        @Qualifier("downloadTaskExecutor") TaskExecutor taskExecutor
    ) {
        this.gateway = gateway;
        this.repository = repository;
        this.playlistImportService = playlistImportService;
        this.taskExecutor = taskExecutor;
    }

    @PostConstruct
    void recoverInterruptedTasks() {
        repository.failActiveTasks("服务重启，下载任务已中断，请重试");
    }

    List<DownloadSource> sources() {
        requireEnabled();
        return gateway.sources();
    }

    List<DownloadCandidate> search(String query, List<String> sources) {
        requireEnabled();
        return gateway.search(query.strip(), sources).stream()
            .map(candidate -> candidate.withDownloadState(
                existingState(candidate).orElse(null)
            ))
            .sorted(Comparator.comparing(
                DownloadCandidate::fileSizeBytes,
                Comparator.nullsLast(Comparator.reverseOrder())
            ).thenComparing(DownloadCandidate::candidateId))
            .toList();
    }

    List<DownloadTask> tasks(String requestedBy) {
        return repository.findRecent(requestedBy);
    }

    DownloadPlaylistPreview parsePlaylist(String url) {
        requireEnabled();
        var preview = gateway.parsePlaylist(url.strip());
        return new DownloadPlaylistPreview(
            preview.name(),
            preview.artworkUrl(),
            preview.items().stream()
                .map(candidate -> candidate.withDownloadState(
                    existingState(candidate).orElse(null)
                ))
                .toList()
        );
    }

    synchronized PlaylistQueueResult queuePlaylist(
        String name, List<DownloadCandidate> candidates, String userId, String username
    ) {
        requireEnabled();
        var available = candidates.stream()
            .filter(candidate -> existingState(candidate).isEmpty())
            .toList();
        if (available.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "歌曲均已下载或已在下载列表");
        }
        var target = playlistImportService.createFeatured(userId, name);
        var tasks = available.stream()
            .map(candidate -> {
                var task = repository.create(candidate, username, target.id());
                submit(task);
                return task;
            })
            .toList();
        return new PlaylistQueueResult(target.id(), target.name(), tasks);
    }

    synchronized DownloadTask queue(DownloadCandidate candidate, String requestedBy) {
        requireEnabled();
        var state = existingState(candidate);
        if (state.isPresent()) {
            var message = state.get() == DownloadTaskState.COMPLETED
                ? "歌曲已存在于曲库"
                : "歌曲已在下载列表";
            throw new ResponseStatusException(HttpStatus.CONFLICT, message);
        }
        var task = repository.create(candidate, requestedBy);
        submit(task);
        return task;
    }

    synchronized Optional<DownloadTask> queueForPlaylist(
        DownloadCandidate candidate, String requestedBy, String targetPlaylistId
    ) {
        requireEnabled();
        if (existingState(candidate).isPresent()) {
            return Optional.empty();
        }
        var task = repository.create(candidate, requestedBy, targetPlaylistId);
        submit(task);
        return Optional.of(task);
    }

    private Optional<DownloadTaskState> existingState(DownloadCandidate candidate) {
        if (repository.existsInLibrary(candidate)) {
            return Optional.of(DownloadTaskState.COMPLETED);
        }
        return repository.findExistingState(candidate);
    }

    DownloadTask retry(String id, String requestedBy) {
        requireEnabled();
        var task = repository.findById(id, requestedBy)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "下载任务不存在"));
        if (task.state() != DownloadTaskState.FAILED) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "只有失败任务可以重试");
        }
        repository.update(task.id(), DownloadTaskState.QUEUED, List.of(), null);
        var queued = repository.findById(task.id()).orElseThrow();
        submit(queued);
        return queued;
    }

    void delete(String id, String requestedBy) {
        if (!repository.delete(id, requestedBy)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "下载记录不存在");
        }
    }

    private void submit(DownloadTask task) {
        try {
            taskExecutor.execute(() -> run(task));
        } catch (RejectedExecutionException exception) {
            repository.update(task.id(), DownloadTaskState.FAILED, List.of(), "下载队列已满");
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS, "下载队列已满");
        }
    }

    private void run(DownloadTask task) {
        repository.update(task.id(), DownloadTaskState.RUNNING, List.of(), null);
        try {
            var files = gateway.download(task.candidateId());
            if (files.isEmpty()) {
                throw new IllegalStateException("下载服务没有返回文件");
            }
            if (task.targetPlaylistId() == null) {
                playlistImportService.scanDownloadedFiles(files);
            } else {
                playlistImportService.addDownloadedFiles(task.targetPlaylistId(), files);
            }
            repository.update(task.id(), DownloadTaskState.COMPLETED, files, null);
        } catch (Exception exception) {
            repository.update(
                task.id(),
                DownloadTaskState.FAILED,
                List.of(),
                conciseMessage(exception)
            );
        }
    }

    private void requireEnabled() {
        if (!gateway.isEnabled()) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "音乐下载服务未启用");
        }
    }

    private String conciseMessage(Exception exception) {
        var message = exception.getMessage();
        if (message == null || message.isBlank()) {
            message = exception.getClass().getSimpleName();
        }
        return message.length() <= 500 ? message : message.substring(0, 500);
    }

    record PlaylistQueueResult(String playlistId, String playlistName, List<DownloadTask> tasks) {
    }
}
