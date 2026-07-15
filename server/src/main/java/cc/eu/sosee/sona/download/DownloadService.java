package cc.eu.sosee.sona.download;

import cc.eu.sosee.sona.library.ScanCoordinator;
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

    DownloadService(
        DownloaderGateway gateway,
        DownloadTaskRepository repository,
        ScanCoordinator scanCoordinator,
        @Qualifier("downloadTaskExecutor") TaskExecutor taskExecutor
    ) {
        this.gateway = gateway;
        this.repository = repository;
        this.scanCoordinator = scanCoordinator;
        this.taskExecutor = taskExecutor;
    }

    List<DownloadSource> sources() {
        requireEnabled();
        return gateway.sources();
    }

    List<DownloadCandidate> search(String query) {
        requireEnabled();
        return gateway.search(query.strip()).stream()
            .sorted(Comparator.comparing(
                DownloadCandidate::fileSizeBytes,
                Comparator.nullsLast(Comparator.reverseOrder())
            ).thenComparing(DownloadCandidate::candidateId))
            .toList();
    }

    List<DownloadTask> tasks() {
        return repository.findRecent();
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
            repository.update(task.id(), DownloadTaskState.COMPLETED, files, null);
            scanCoordinator.trigger();
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
}
