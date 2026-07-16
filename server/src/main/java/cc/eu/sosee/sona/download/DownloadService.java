package cc.eu.sosee.sona.download;

import cc.eu.sosee.sona.library.ScanCoordinator;
import cc.eu.sosee.sona.personal.PlaylistDownloadImportService;
import java.util.Comparator;
import java.util.List;
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
    private final ScanCoordinator scanCoordinator;
    private final TaskExecutor taskExecutor;
    private final PlaylistDownloadImportService playlistImportService;

    DownloadService(
        DownloaderGateway gateway,
        DownloadTaskRepository repository,
        ScanCoordinator scanCoordinator,
        PlaylistDownloadImportService playlistImportService,
        @Qualifier("downloadTaskExecutor") TaskExecutor taskExecutor
    ) {
        this.gateway = gateway;
        this.repository = repository;
        this.scanCoordinator = scanCoordinator;
        this.playlistImportService = playlistImportService;
        this.taskExecutor = taskExecutor;
    }

    List<DownloadSource> sources() {
        requireEnabled();
        return gateway.sources();
    }

    List<DownloadCandidate> search(String query, List<String> sources) {
        requireEnabled();
        return gateway.search(query.strip(), sources).stream()
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
        return gateway.parsePlaylist(url.strip());
    }

    PlaylistQueueResult queuePlaylist(
        String name, List<DownloadCandidate> candidates, String userId, String username
    ) {
        requireEnabled();
        var target = playlistImportService.create(userId, name);
        var tasks = candidates.stream()
            .map(candidate -> {
                var task = repository.create(candidate, username, target.id());
                submit(task);
                return task;
            })
            .toList();
        return new PlaylistQueueResult(target.id(), target.name(), tasks);
    }

    DownloadTask queue(DownloadCandidate candidate, String requestedBy) {
        requireEnabled();
        var task = repository.create(candidate, requestedBy);
        submit(task);
        return task;
    }

    DownloadTask retry(String id) {
        requireEnabled();
        var task = repository.findById(id)
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
                scanCoordinator.trigger();
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
