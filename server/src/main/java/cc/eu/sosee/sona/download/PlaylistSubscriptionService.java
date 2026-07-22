package cc.eu.sosee.sona.download;

import cc.eu.sosee.sona.personal.PlaylistDownloadImportService;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.RejectedExecutionException;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.core.task.TaskExecutor;
import org.springframework.http.HttpStatus;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
class PlaylistSubscriptionService {

    private static final Set<String> POOL_TYPES = Set.of("NORMAL", "DISCOVERY", "CHILD");

    private final PlaylistSubscriptionRepository subscriptions;
    private final DownloadTaskRepository downloads;
    private final DownloadService downloadService;
    private final PlaylistDownloadImportService playlistImportService;
    private final Clock clock;
    private final TaskExecutor taskExecutor;
    private final Set<String> syncing = ConcurrentHashMap.newKeySet();

    PlaylistSubscriptionService(
        PlaylistSubscriptionRepository subscriptions,
        DownloadTaskRepository downloads,
        DownloadService downloadService,
        PlaylistDownloadImportService playlistImportService,
        Clock clock,
        @Qualifier("downloadTaskExecutor") TaskExecutor taskExecutor
    ) {
        this.subscriptions = subscriptions;
        this.downloads = downloads;
        this.downloadService = downloadService;
        this.playlistImportService = playlistImportService;
        this.clock = clock;
        this.taskExecutor = taskExecutor;
    }

    @Transactional
    List<PlaylistSubscriptionRepository.Subscription> list(String userId) {
        var values = subscriptions.findAll(userId);
        for (var subscription : values) {
            if (!syncing.contains(subscription.id())) {
                playlistImportService.replaceTracks(
                    userId, subscription.playlistId(),
                    subscriptions.matchedTrackIds(subscription.id())
                );
            }
        }
        return values;
    }

    synchronized PlaylistSubscriptionRepository.Subscription create(
        String userId, String username, String sourceUrl, String requestedName,
        String poolType, boolean autoDownload, int syncIntervalHours
    ) {
        var normalizedPoolType = normalizePoolType(poolType);
        if (subscriptions.findAll(userId).stream().anyMatch(item -> item.sourceUrl().equals(sourceUrl.strip()))) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "已经订阅过这个歌单");
        }
        var name = requestedName == null || requestedName.isBlank()
            ? "订阅歌单"
            : requestedName.strip();
        var target = playlistImportService.create(userId, name, normalizedPoolType);
        var subscription = subscriptions.create(
            userId, target.id(), sourceUrl.strip(), name, normalizedPoolType,
            autoDownload, syncIntervalHours
        );
        playlistImportService.addToHome(userId, target.id());
        submitInitialSync(subscription, requestedName == null || requestedName.isBlank());
        return subscription;
    }

    PlaylistSubscriptionRepository.Subscription sync(String userId, String id) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        return sync(subscription, "订阅歌单".equals(subscription.name()), false);
    }

    PlaylistSubscriptionRepository.Subscription downloadMissing(String userId, String id) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        return sync(subscription, "订阅歌单".equals(subscription.name()), true);
    }

    @Transactional
    PlaylistSubscriptionRepository.Subscription rename(String userId, String id, String name) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        var normalizedName = name.strip();
        playlistImportService.rename(userId, subscription.playlistId(), normalizedName);
        subscriptions.rename(subscription.id(), normalizedName);
        return subscriptions.find(userId, id).orElseThrow();
    }

    @Transactional
    void delete(String userId, String id) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        subscriptions.delete(userId, id);
        playlistImportService.delete(userId, subscription.playlistId());
    }

    @Scheduled(fixedDelay = 900_000, initialDelay = 60_000)
    void syncDueSubscriptions() {
        for (var subscription : subscriptions.findDue()) {
            try {
                sync(subscription, "订阅歌单".equals(subscription.name()), false);
            } catch (RuntimeException ignored) {
                // 单个公开歌单失效时保留上次成功镜像，并继续同步其他订阅。
            }
        }
    }

    private PlaylistSubscriptionRepository.Subscription sync(
        PlaylistSubscriptionRepository.Subscription subscription, boolean useRemoteName,
        boolean downloadMissing
    ) {
        if (!syncing.add(subscription.id())) {
            return subscriptions.find(subscription.userId(), subscription.id()).orElseThrow();
        }
        try {
            var preview = downloadService.parsePlaylist(subscription.sourceUrl());
            if (useRemoteName && preview.name() != null && !preview.name().isBlank()) {
                var remoteName = preview.name().strip();
                playlistImportService.rename(subscription.userId(), subscription.playlistId(), remoteName);
                subscriptions.rename(subscription.id(), remoteName);
                subscription = subscriptions.find(subscription.userId(), subscription.id()).orElseThrow();
            }
            var now = clock.millis();
            var items = new ArrayList<PlaylistSubscriptionRepository.Item>();
            var matchedTrackIds = new ArrayList<String>();
            for (var position = 0; position < preview.items().size(); position++) {
                var candidate = preview.items().get(position);
                var matchedTrackId = downloads.findLibraryTrackId(candidate).orElse(null);
                var state = "MISSING";
                if (matchedTrackId != null) {
                    matchedTrackIds.add(matchedTrackId);
                    state = "MATCHED";
                } else if (candidate.downloadState() == DownloadTaskState.QUEUED
                    || candidate.downloadState() == DownloadTaskState.RUNNING) {
                    state = "DOWNLOADING";
                } else if ((subscription.autoDownload() || downloadMissing)
                    && downloadService.queueForPlaylist(
                        candidate, subscription.username(), subscription.playlistId()
                    ).isPresent()) {
                    state = "DOWNLOADING";
                }
                items.add(new PlaylistSubscriptionRepository.Item(
                    itemKey(candidate, position), position, candidate.title().strip(),
                    candidate.artist().strip(), candidate.album(), matchedTrackId, state, now
                ));
            }
            playlistImportService.replaceTracks(
                subscription.userId(), subscription.playlistId(), matchedTrackIds
            );
            subscriptions.replaceItems(subscription.id(), items);
            subscriptions.markSynced(subscription.id());
            return subscriptions.find(subscription.userId(), subscription.id()).orElseThrow();
        } catch (RuntimeException exception) {
            subscriptions.markFailed(subscription.id(), conciseMessage(exception));
            throw exception;
        } finally {
            syncing.remove(subscription.id());
        }
    }

    private void submitInitialSync(
        PlaylistSubscriptionRepository.Subscription subscription, boolean useRemoteName
    ) {
        try {
            taskExecutor.execute(() -> {
                try {
                    sync(subscription, useRemoteName, false);
                } catch (RuntimeException ignored) {
                    // 同步错误已记录在订阅中，不能影响创建接口的快速返回。
                }
            });
        } catch (RejectedExecutionException exception) {
            subscriptions.markFailed(subscription.id(), "后台同步任务繁忙，请稍后手动同步");
        }
    }

    private String normalizePoolType(String value) {
        var normalized = value == null ? "NORMAL" : value.strip().toUpperCase();
        if (!POOL_TYPES.contains(normalized)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "歌曲池类型无效");
        }
        return normalized;
    }

    private String itemKey(DownloadCandidate candidate, int position) {
        var value = position + "\n" + candidate.title().strip().toLowerCase()
            + "\n" + candidate.artist().strip().toLowerCase();
        try {
            return HexFormat.of().formatHex(
                MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8))
            );
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException(exception);
        }
    }

    private String conciseMessage(RuntimeException exception) {
        var message = exception.getMessage();
        if (message == null || message.isBlank()) {
            message = exception.getClass().getSimpleName();
        }
        return message.length() <= 500 ? message : message.substring(0, 500);
    }
}
