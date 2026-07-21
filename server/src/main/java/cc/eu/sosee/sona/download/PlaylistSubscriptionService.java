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
import org.springframework.http.HttpStatus;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

@Service
class PlaylistSubscriptionService {

    private static final Set<String> POOL_TYPES = Set.of("NORMAL", "DISCOVERY", "CHILD");

    private final PlaylistSubscriptionRepository subscriptions;
    private final DownloadTaskRepository downloads;
    private final DownloadService downloadService;
    private final PlaylistDownloadImportService playlistImportService;
    private final Clock clock;
    private final Set<String> syncing = ConcurrentHashMap.newKeySet();

    PlaylistSubscriptionService(
        PlaylistSubscriptionRepository subscriptions,
        DownloadTaskRepository downloads,
        DownloadService downloadService,
        PlaylistDownloadImportService playlistImportService,
        Clock clock
    ) {
        this.subscriptions = subscriptions;
        this.downloads = downloads;
        this.downloadService = downloadService;
        this.playlistImportService = playlistImportService;
        this.clock = clock;
    }

    List<PlaylistSubscriptionRepository.Subscription> list(String userId) {
        return subscriptions.findAll(userId);
    }

    synchronized PlaylistSubscriptionRepository.Subscription create(
        String userId, String username, String sourceUrl, String requestedName,
        String poolType, boolean autoDownload, int syncIntervalHours
    ) {
        var normalizedPoolType = normalizePoolType(poolType);
        if (subscriptions.findAll(userId).stream().anyMatch(item -> item.sourceUrl().equals(sourceUrl.strip()))) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "已经订阅过这个歌单");
        }
        var preview = downloadService.parsePlaylist(sourceUrl);
        var name = requestedName == null || requestedName.isBlank()
            ? preview.name().strip()
            : requestedName.strip();
        var target = playlistImportService.create(userId, name, normalizedPoolType);
        var subscription = subscriptions.create(
            userId, target.id(), sourceUrl.strip(), name, normalizedPoolType,
            autoDownload, syncIntervalHours
        );
        return sync(subscription, preview);
    }

    PlaylistSubscriptionRepository.Subscription sync(String userId, String id) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        return sync(subscription, null);
    }

    void delete(String userId, String id) {
        if (!subscriptions.delete(userId, id)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在");
        }
    }

    @Scheduled(fixedDelay = 900_000, initialDelay = 60_000)
    void syncDueSubscriptions() {
        for (var subscription : subscriptions.findDue()) {
            try {
                sync(subscription, null);
            } catch (RuntimeException ignored) {
                // 单个公开歌单失效时保留上次成功镜像，并继续同步其他订阅。
            }
        }
    }

    private PlaylistSubscriptionRepository.Subscription sync(
        PlaylistSubscriptionRepository.Subscription subscription,
        DownloadPlaylistPreview knownPreview
    ) {
        if (!syncing.add(subscription.id())) {
            return subscriptions.find(subscription.userId(), subscription.id()).orElseThrow();
        }
        try {
            var preview = knownPreview == null
                ? downloadService.parsePlaylist(subscription.sourceUrl())
                : knownPreview;
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
                } else if (subscription.autoDownload()
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
