package cc.eu.sosee.sona.download;

import cc.eu.sosee.sona.personal.PlaylistDownloadImportService;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
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
    private final DownloadService downloadService;
    private final PlaylistSubscriptionMatcher matcher;
    private final PlaylistDownloadImportService playlistImportService;
    private final Clock clock;
    private final TaskExecutor taskExecutor;
    private final Set<String> syncing = ConcurrentHashMap.newKeySet();

    PlaylistSubscriptionService(
        PlaylistSubscriptionRepository subscriptions,
        DownloadService downloadService, PlaylistSubscriptionMatcher matcher,
        PlaylistDownloadImportService playlistImportService,
        Clock clock,
        @Qualifier("downloadTaskExecutor") TaskExecutor taskExecutor
    ) {
        this.subscriptions = subscriptions;
        this.downloadService = downloadService;
        this.matcher = matcher;
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

    List<ItemDetail> items(String userId, String id) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        var session = matcher.open();
        var storedItems = subscriptions.findItems(subscription.id());
        var usedTrackIds = new HashSet<>(subscriptions.matchedTrackIds(subscription.id()));
        return storedItems.stream()
            .map(item -> {
                var excludedTrackIds = new HashSet<>(usedTrackIds);
                excludedTrackIds.remove(item.matchedTrackId());
                var suggestions = item.matchedTrackId() == null && "SUGGESTED".equals(item.state())
                    ? session.match(asCandidate(item), excludedTrackIds).suggestions()
                    : List.<PlaylistSubscriptionMatcher.Suggestion>of();
                return new ItemDetail(
                    item.itemKey(), item.position(), item.title(), item.artist(), item.album(),
                    item.matchedTrackId(), item.state(), suggestions
                );
            })
            .toList();
    }

    ItemPage suggestedItems(String userId, String id, int offset, int limit) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        var suggested = subscriptions.findItems(subscription.id()).stream()
            .filter(item -> item.matchedTrackId() == null && "SUGGESTED".equals(item.state()))
            .toList();
        if (offset >= suggested.size()) {
            return new ItemPage(List.of(), false);
        }
        var end = Math.min(offset + limit, suggested.size());
        var session = matcher.open();
        var usedTrackIds = new HashSet<>(subscriptions.matchedTrackIds(subscription.id()));
        var page = suggested.subList(offset, end).stream()
            .map(item -> new ItemDetail(
                item.itemKey(), item.position(), item.title(), item.artist(), item.album(),
                item.matchedTrackId(), item.state(),
                session.match(asCandidate(item), usedTrackIds).suggestions()
            ))
            .toList();
        return new ItemPage(page, end < suggested.size());
    }

    @Transactional
    BestMatchResult applyBestMatches(String userId, String id) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        var session = matcher.open();
        var usedTrackIds = new HashSet<>(subscriptions.matchedTrackIds(subscription.id()));
        var matchedCount = 0;
        for (var item : subscriptions.findItems(subscription.id())) {
            if (item.matchedTrackId() != null || !"SUGGESTED".equals(item.state())) {
                continue;
            }
            var best = session.bestStrictMatch(asCandidate(item), usedTrackIds);
            if (best.isPresent() && subscriptions.selectMatch(
                userId, id, item.itemKey(), best.get().trackId()
            )) {
                usedTrackIds.add(best.get().trackId());
                matchedCount++;
            }
        }
        playlistImportService.replaceTracks(
            userId, subscription.playlistId(), subscriptions.matchedTrackIds(id)
        );
        return new BestMatchResult(
            subscriptions.find(userId, id).orElseThrow(), matchedCount
        );
    }

    @Transactional
    PlaylistSubscriptionRepository.Subscription selectMatch(
        String userId, String id, String itemKey, String trackId
    ) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        if (!subscriptions.selectMatch(userId, id, itemKey, trackId)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "候选歌曲不存在或已被其他歌曲使用");
        }
        playlistImportService.replaceTracks(
            userId, subscription.playlistId(), subscriptions.matchedTrackIds(id)
        );
        return subscriptions.find(userId, id).orElseThrow();
    }

    synchronized PlaylistSubscriptionRepository.Subscription downloadItem(
        String userId, String id, String itemKey
    ) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        subscriptions.findItem(userId, id, itemKey)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌曲不存在"));
        var candidate = candidatesByKey(downloadService.parsePlaylist(subscription.sourceUrl()))
            .get(itemKey);
        if (candidate == null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "远端歌单已变化，请先重新同步");
        }
        if (downloadService.queueForPlaylist(
            candidate, subscription.username(), subscription.playlistId()
        ).isEmpty()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "歌曲已入库或已在下载列表");
        }
        subscriptions.updateItemState(id, itemKey, "DOWNLOADING");
        return subscriptions.find(userId, id).orElseThrow();
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
            if (preview.artworkUrl() != null && !preview.artworkUrl().isBlank()) {
                var artworkUrl = preview.artworkUrl().strip();
                if (artworkUrl.startsWith("https://") || artworkUrl.startsWith("http://")) {
                    subscriptions.updateArtwork(subscription.id(), artworkUrl);
                    playlistImportService.setRemoteArtwork(
                        subscription.userId(), subscription.playlistId(), artworkUrl
                    );
                }
            }
            var now = clock.millis();
            var items = new ArrayList<PlaylistSubscriptionRepository.Item>();
            var matchedTrackIds = new ArrayList<String>();
            var existingItems = subscriptions.findItems(subscription.id()).stream()
                .collect(java.util.stream.Collectors.toMap(
                    PlaylistSubscriptionRepository.Item::itemKey, item -> item,
                    (left, right) -> left
                ));
            var matchSession = matcher.open();
            var occurrences = new HashMap<String, Integer>();
            var usedTrackIds = new HashSet<String>();
            for (var position = 0; position < preview.items().size(); position++) {
                var candidate = preview.items().get(position);
                var keyBase = itemKeyBase(candidate);
                var occurrence = occurrences.merge(keyBase, 1, Integer::sum) - 1;
                var itemKey = itemKey(candidate, occurrence);
                var existing = existingItems.get(itemKey);
                String matchedTrackId = null;
                List<PlaylistSubscriptionMatcher.Suggestion> suggestions = List.of();
                if (existing != null && matchSession.containsTrack(existing.matchedTrackId())
                    && !usedTrackIds.contains(existing.matchedTrackId())) {
                    matchedTrackId = existing.matchedTrackId();
                } else {
                    var match = matchSession.match(candidate, usedTrackIds);
                    matchedTrackId = match.exactTrackId().orElse(null);
                    suggestions = match.suggestions();
                }
                var state = "MISSING";
                if (matchedTrackId != null) {
                    matchedTrackIds.add(matchedTrackId);
                    usedTrackIds.add(matchedTrackId);
                    state = "MATCHED";
                } else if (!suggestions.isEmpty()) {
                    state = "SUGGESTED";
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
                    itemKey, position, candidate.title().strip(),
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

    private Map<String, DownloadCandidate> candidatesByKey(DownloadPlaylistPreview preview) {
        var result = new HashMap<String, DownloadCandidate>();
        var occurrences = new HashMap<String, Integer>();
        for (var candidate : preview.items()) {
            var keyBase = itemKeyBase(candidate);
            var occurrence = occurrences.merge(keyBase, 1, Integer::sum) - 1;
            result.put(itemKey(candidate, occurrence), candidate);
        }
        return result;
    }

    private String itemKeyBase(DownloadCandidate candidate) {
        return PlaylistSubscriptionMatcher.normalizedText(candidate.title()) + "\n"
            + PlaylistSubscriptionMatcher.normalizedArtists(candidate.artist());
    }

    private String itemKey(DownloadCandidate candidate, int occurrence) {
        var value = itemKeyBase(candidate) + "\n" + occurrence;
        try {
            return HexFormat.of().formatHex(
                MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8))
            );
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException(exception);
        }
    }

    private DownloadCandidate asCandidate(PlaylistSubscriptionRepository.Item item) {
        return new DownloadCandidate(
            item.itemKey(), "subscription", "订阅歌单", item.title(), item.artist(),
            item.album(), null, null, null, null, null, false, null, null
        );
    }

    record ItemDetail(
        String itemKey, int position, String title, String artist, String album,
        String matchedTrackId, String state,
        List<PlaylistSubscriptionMatcher.Suggestion> suggestions
    ) {
    }

    record ItemPage(List<ItemDetail> items, boolean hasMore) {
    }

    record BestMatchResult(
        PlaylistSubscriptionRepository.Subscription subscription, int matchedCount
    ) {
    }

    private String conciseMessage(RuntimeException exception) {
        var message = exception.getMessage();
        if (message == null || message.isBlank()) {
            message = exception.getClass().getSimpleName();
        }
        return message.length() <= 500 ? message : message.substring(0, 500);
    }
}
