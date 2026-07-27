package cc.eu.sosee.sona.download;

import cc.eu.sosee.sona.auth.UserPreferencesService;
import cc.eu.sosee.sona.personal.PlaylistDownloadImportService;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.RejectedExecutionException;
import java.util.function.Predicate;
import org.springframework.beans.factory.annotation.Autowired;
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
    private final PlaylistSubscriptionArtworkArchive artworkArchive;
    private final Predicate<String> versioningEnabled;
    private final Clock clock;
    private final TaskExecutor taskExecutor;
    private final Set<String> syncing = ConcurrentHashMap.newKeySet();

    @Autowired
    PlaylistSubscriptionService(
        PlaylistSubscriptionRepository subscriptions,
        DownloadService downloadService, PlaylistSubscriptionMatcher matcher,
        PlaylistDownloadImportService playlistImportService,
        PlaylistSubscriptionArtworkArchive artworkArchive,
        UserPreferencesService userPreferences,
        Clock clock,
        @Qualifier("downloadTaskExecutor") TaskExecutor taskExecutor
    ) {
        this.subscriptions = subscriptions;
        this.downloadService = downloadService;
        this.matcher = matcher;
        this.playlistImportService = playlistImportService;
        this.artworkArchive = artworkArchive;
        versioningEnabled = userPreferences::playlistVersionManagementEnabled;
        this.clock = clock;
        this.taskExecutor = taskExecutor;
    }

    PlaylistSubscriptionService(
        PlaylistSubscriptionRepository subscriptions,
        DownloadService downloadService, PlaylistSubscriptionMatcher matcher,
        PlaylistDownloadImportService playlistImportService,
        Clock clock, TaskExecutor taskExecutor
    ) {
        this(
            subscriptions, downloadService, matcher, playlistImportService,
            new PlaylistSubscriptionArtworkArchive() {
                @Override
                public java.util.Optional<String> archive(String sourceUrl) {
                    return java.util.Optional.empty();
                }

                @Override
                public byte[] read(String contentHash) {
                    throw new IllegalStateException("订阅歌单封面归档未配置");
                }
            },
            ignored -> true,
            clock, taskExecutor
        );
    }

    PlaylistSubscriptionService(
        PlaylistSubscriptionRepository subscriptions,
        DownloadService downloadService, PlaylistSubscriptionMatcher matcher,
        PlaylistDownloadImportService playlistImportService,
        Predicate<String> versioningEnabled,
        Clock clock, TaskExecutor taskExecutor
    ) {
        this(
            subscriptions, downloadService, matcher, playlistImportService,
            new PlaylistSubscriptionArtworkArchive() {
                @Override
                public java.util.Optional<String> archive(String sourceUrl) {
                    return java.util.Optional.empty();
                }

                @Override
                public byte[] read(String contentHash) {
                    throw new IllegalStateException("订阅歌单封面归档未配置");
                }
            },
            versioningEnabled, clock, taskExecutor
        );
    }

    private PlaylistSubscriptionService(
        PlaylistSubscriptionRepository subscriptions,
        DownloadService downloadService, PlaylistSubscriptionMatcher matcher,
        PlaylistDownloadImportService playlistImportService,
        PlaylistSubscriptionArtworkArchive artworkArchive,
        Predicate<String> versioningEnabled,
        Clock clock, TaskExecutor taskExecutor
    ) {
        this.subscriptions = subscriptions;
        this.downloadService = downloadService;
        this.matcher = matcher;
        this.playlistImportService = playlistImportService;
        this.artworkArchive = artworkArchive;
        this.versioningEnabled = versioningEnabled;
        this.clock = clock;
        this.taskExecutor = taskExecutor;
    }

    @Transactional
    List<PlaylistSubscriptionRepository.Subscription> list(String userId) {
        var values = subscriptions.findAll(userId);
        for (var subscription : values) {
            if (!syncing.contains(subscription.id())) {
                downloadService.reconcileCompletedPlaylistDownloads(
                    subscription.playlistId()
                );
                refreshAfterMatching(subscription);
            }
        }
        return subscriptions.findAll(userId);
    }

    synchronized PlaylistSubscriptionRepository.Subscription create(
        String userId, String username, String sourceUrl, String requestedName,
        String poolType, boolean autoDownload, int syncIntervalHours
    ) {
        return create(
            userId, username, sourceUrl, requestedName, poolType,
            autoDownload, true, syncIntervalHours
        );
    }

    synchronized PlaylistSubscriptionRepository.Subscription create(
        String userId, String username, String sourceUrl, String requestedName,
        String poolType, boolean autoDownload, boolean strictMode, int syncIntervalHours
    ) {
        var normalizedPoolType = normalizePoolType(poolType);
        if (subscriptions.findAll(userId).stream().anyMatch(item -> item.sourceUrl().equals(sourceUrl.strip()))) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "已经订阅过这个歌单");
        }
        var name = requestedName == null || requestedName.isBlank()
            ? "订阅歌单"
            : requestedName.strip();
        var target = playlistImportService.create(userId, name, normalizedPoolType);
        var subscription = strictMode
            ? subscriptions.create(
                userId, target.id(), sourceUrl.strip(), name, normalizedPoolType,
                autoDownload, syncIntervalHours
            )
            : subscriptions.create(
                userId, target.id(), sourceUrl.strip(), name, normalizedPoolType,
                autoDownload, false, syncIntervalHours
            );
        playlistImportService.addToHome(userId, target.id());
        submitInitialSync(subscription, requestedName == null || requestedName.isBlank());
        return subscription;
    }

    PlaylistSubscriptionRepository.Subscription sync(String userId, String id) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        return sync(subscription, "订阅歌单".equals(subscription.name()), false, false)
            .subscription();
    }

    PlaylistSubscriptionRepository.Subscription downloadMissing(String userId, String id) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        return sync(subscription, "订阅歌单".equals(subscription.name()), true, false)
            .subscription();
    }

    @Transactional
    PlaylistSubscriptionRepository.Subscription blacklistTracks(
        String userId, String id, List<String> trackIds
    ) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        subscriptions.blacklistTracks(userId, id, trackIds);
        playlistImportService.removeTracks(userId, subscription.playlistId(), trackIds);
        return subscriptions.find(userId, id).orElseThrow();
    }

    List<PlaylistSubscriptionRepository.Version> versions(String userId, String id) {
        subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        requireVersionManagementEnabled(userId);
        return subscriptions.findVersions(userId, id);
    }

    PlaylistSubscriptionRepository.Subscription selectVersion(
        String userId, String id, int versionNumber
    ) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        requireVersionManagementEnabled(userId);
        subscriptions.selectVersion(userId, id, versionNumber)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "歌单版本不存在"));
        applySelectedVersion(subscription, true);
        return subscriptions.find(userId, id).orElseThrow();
    }

    PlaylistSubscriptionRepository.Subscription followLatest(String userId, String id) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        requireVersionManagementEnabled(userId);
        subscriptions.followLatest(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "歌单还没有可用版本"));
        applySelectedVersion(subscription, true);
        return subscriptions.find(userId, id).orElseThrow();
    }

    byte[] artwork(String userId, String id, int versionNumber) {
        var version = subscriptions.findVersion(userId, id, versionNumber)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "歌单版本不存在"));
        if (!version.hasArtwork()) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "该版本没有封面");
        }
        try {
            return artworkArchive.read(version.artworkHash());
        } catch (IllegalArgumentException | IllegalStateException exception) {
            throw new ResponseStatusException(
                HttpStatus.NOT_FOUND, "订阅歌单封面不存在", exception
            );
        }
    }

    List<ItemDetail> items(String userId, String id) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        var session = matcher.open();
        var storedItems = subscriptions.findItems(subscription.id());
        return storedItems.stream()
            .map(item -> {
                var suggestions = item.matchedTrackId() == null && "SUGGESTED".equals(item.state())
                    ? session.match(asCandidate(item), Set.of()).suggestions()
                    : List.<PlaylistSubscriptionMatcher.Suggestion>of();
                return new ItemDetail(
                    item.itemKey(), item.position(), item.title(), item.artist(), item.album(),
                    item.matchedTrackId(), item.state(), suggestions
                );
            })
            .toList();
    }

    @Transactional
    ItemPage suggestedItems(String userId, String id, int offset, int limit) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        var suggested = subscriptions.findItems(subscription.id()).stream()
            .filter(item -> item.matchedTrackId() == null && "SUGGESTED".equals(item.state()))
            .toList();
        if (offset >= suggested.size()) {
            return new ItemPage(List.of(), false);
        }
        var session = matcher.open();
        var page = new ArrayList<ItemDetail>();
        var matchedAny = false;
        var index = offset;
        while (index < suggested.size() && page.size() < limit) {
            var item = suggested.get(index++);
            var match = subscription.strictMode()
                ? session.match(asCandidate(item), Set.of())
                : session.match(asCandidate(item), Set.of(), false);
            var exactTrackId = match.exactTrackId().orElse(null);
            if (exactTrackId != null && subscriptions.selectMatch(
                userId, id, item.itemKey(), exactTrackId
            )) {
                matchedAny = true;
                continue;
            }
            if (match.suggestions().isEmpty()) {
                subscriptions.updateItemState(id, item.itemKey(), "MISSING");
                continue;
            }
            page.add(new ItemDetail(
                item.itemKey(), item.position(), item.title(), item.artist(), item.album(),
                item.matchedTrackId(), item.state(), match.suggestions()
            ));
        }
        if (matchedAny) {
            refreshAfterMatching(subscription);
        }
        return new ItemPage(List.copyOf(page), index < suggested.size());
    }

    @Transactional
    BestMatchResult applyBestMatches(String userId, String id, BestMatchMode mode) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        var session = matcher.open();
        var matchedCount = 0;
        for (var item : subscriptions.findItems(subscription.id())) {
            if (item.matchedTrackId() != null || !"SUGGESTED".equals(item.state())) {
                continue;
            }
            var best = mode == BestMatchMode.IGNORE_BRACKETS
                ? session.bestBracketMatch(asCandidate(item), Set.of())
                : session.bestStrictMatch(asCandidate(item), Set.of());
            if (best.isPresent() && subscriptions.selectMatch(
                userId, id, item.itemKey(), best.get().trackId()
            )) {
                matchedCount++;
            }
        }
        var refreshed = refreshAfterMatching(subscription);
        return new BestMatchResult(
            refreshed, matchedCount
        );
    }

    @Transactional
    PlaylistSubscriptionRepository.Subscription selectMatch(
        String userId, String id, String itemKey, String trackId
    ) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        var item = subscriptions.findItem(userId, id, itemKey)
            .orElseThrow(() -> new ResponseStatusException(
                HttpStatus.CONFLICT, "候选歌曲不存在或已被其他歌曲使用"
            ));
        if (!subscriptions.selectMatch(userId, id, itemKey, trackId)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "候选歌曲不存在或已被其他歌曲使用");
        }
        subscriptions.rememberMatch(userId, item.title(), item.artist(), trackId);
        return refreshAfterMatching(subscription);
    }

    PlaylistSubscriptionRepository.Subscription updateStrictMode(
        String userId, String id, boolean strictMode
    ) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        subscriptions.updateStrictMode(id, strictMode);
        if (!strictMode) {
            downloadService.disableStrictMatchForPlaylist(subscription.playlistId());
        }
        return subscriptions.find(userId, id).orElseThrow();
    }

    @Transactional
    PlaylistSubscriptionRepository.Subscription updateSettings(
        String userId, String id, String name, String poolType, Boolean autoDownload,
        Boolean strictMode, Integer syncIntervalHours
    ) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        var effectiveInterval = syncIntervalHours == null
            ? subscription.syncIntervalHours()
            : syncIntervalHours;
        if (effectiveInterval < 1 || effectiveInterval > 168) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "同步频率无效");
        }
        var normalizedName = name.strip();
        var normalizedPoolType = poolType == null
            ? subscription.poolType() : normalizePoolType(poolType);
        var effectiveAutoDownload = autoDownload == null
            ? subscription.autoDownload() : autoDownload;
        var effectiveStrictMode = strictMode == null ? subscription.strictMode() : strictMode;
        playlistImportService.rename(userId, subscription.playlistId(), normalizedName);
        playlistImportService.updatePool(
            userId, subscription.playlistId(), normalizedPoolType
        );
        subscriptions.updateSettings(
            subscription.id(), normalizedName, normalizedPoolType,
            effectiveAutoDownload,
            effectiveStrictMode,
            effectiveInterval
        );
        if (!effectiveStrictMode) {
            downloadService.disableStrictMatchForPlaylist(subscription.playlistId());
        }
        return subscriptions.find(userId, id).orElseThrow();
    }

    synchronized PlaylistSubscriptionRepository.Subscription downloadItem(
        String userId, String id, String itemKey
    ) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        subscriptions.findItem(userId, id, itemKey)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌曲不存在"));
        if (subscriptions.isBlacklisted(userId, id, itemKey)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "歌曲已拉黑，不能下载");
        }
        var candidate = candidatesByKey(downloadService.parsePlaylist(subscription.sourceUrl()))
            .get(itemKey);
        if (candidate == null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "远端歌单已变化，请先重新同步");
        }
        var session = matcher.open();
        var match = subscription.strictMode()
            ? session.match(candidate, Set.of())
            : session.match(candidate, Set.of(), false);
        var localTrackId = match.exactTrackId().orElse(null);
        if (localTrackId != null
            && subscriptions.selectMatch(userId, id, itemKey, localTrackId)) {
            return refreshAfterMatching(subscription);
        }
        var queued = subscription.strictMode()
            ? downloadService.queueForPlaylist(
                candidate, subscription.username(), subscription.playlistId()
            )
            : downloadService.queueForPlaylist(
                candidate, subscription.username(), subscription.playlistId(), false
            );
        if (queued.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "歌曲已入库或已在下载列表");
        }
        subscriptions.updateItemState(id, itemKey, "DOWNLOADING");
        return subscriptions.find(userId, id).orElseThrow();
    }

    synchronized OriginalDownloadResult downloadSuggestedOriginals(
        String userId, String id
    ) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        var candidates = candidatesByKey(
            downloadService.parsePlaylist(subscription.sourceUrl())
        );
        var queuedCount = 0;
        var skippedCount = 0;
        for (var item : subscriptions.findItems(subscription.id())) {
            if (item.matchedTrackId() != null || !"SUGGESTED".equals(item.state())) {
                continue;
            }
            var candidate = candidates.get(item.itemKey());
            if (candidate == null) {
                skippedCount++;
                continue;
            }
            var queued = subscription.strictMode()
                ? downloadService.queueForPlaylist(
                    candidate, subscription.username(), subscription.playlistId()
                )
                : downloadService.queueForPlaylist(
                    candidate, subscription.username(), subscription.playlistId(), false
                );
            if (queued.isEmpty()) {
                skippedCount++;
                continue;
            }
            subscriptions.updateItemState(id, item.itemKey(), "DOWNLOADING");
            queuedCount++;
        }
        return new OriginalDownloadResult(
            subscriptions.find(userId, id).orElseThrow(), queuedCount, skippedCount
        );
    }

    AutomationSyncResult syncForAutomation(
        PlaylistSubscriptionRepository.Subscription subscription
    ) {
        return sync(
            subscription, "订阅歌单".equals(subscription.name()), false, true
        );
    }

    synchronized AutomationDownloadResult queueAutomationOriginals(
        String userId, String id, boolean includeSuggested
    ) {
        var subscription = subscriptions.find(userId, id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "订阅歌单不存在"));
        var candidates = candidatesByKey(
            downloadService.parsePlaylist(subscription.sourceUrl())
        );
        var tasks = new ArrayList<DownloadTask>();
        var skippedCount = 0;
        for (var item : subscriptions.findItems(subscription.id())) {
            var shouldDownload = item.matchedTrackId() == null
                && ("MISSING".equals(item.state())
                    || includeSuggested && "SUGGESTED".equals(item.state()));
            if (!shouldDownload) {
                continue;
            }
            var candidate = candidates.get(item.itemKey());
            if (candidate == null) {
                skippedCount++;
                continue;
            }
            var queued = subscription.strictMode()
                ? downloadService.queueForPlaylist(
                    candidate, subscription.username(), subscription.playlistId()
                )
                : downloadService.queueForPlaylist(
                    candidate, subscription.username(), subscription.playlistId(), false
                );
            if (queued.isEmpty()) {
                skippedCount++;
                continue;
            }
            subscriptions.updateItemState(id, item.itemKey(), "DOWNLOADING");
            tasks.add(queued.get());
        }
        return new AutomationDownloadResult(List.copyOf(tasks), skippedCount);
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

    @Transactional
    void disableVersionManagement(String userId) {
        for (var subscription : subscriptions.findAll(userId)) {
            if (subscription.latestVersionNumber() > 0) {
                subscriptions.followLatest(userId, subscription.id());
            }
            playlistImportService.replaceTracks(
                userId, subscription.playlistId(),
                subscriptions.matchedTrackIds(subscription.id())
            );
            playlistImportService.restoreSubscriptionArtwork(
                userId, subscription.playlistId()
            );
        }
    }

    @Scheduled(fixedDelay = 900_000, initialDelay = 60_000)
    void syncDueSubscriptions() {
        for (var subscription : subscriptions.findDue()) {
            try {
                sync(subscription, "订阅歌单".equals(subscription.name()), false, false);
            } catch (RuntimeException ignored) {
                // 单个公开歌单失效时保留上次成功镜像，并继续同步其他订阅。
            }
        }
    }

    private AutomationSyncResult sync(
        PlaylistSubscriptionRepository.Subscription subscription, boolean useRemoteName,
        boolean downloadMissing, boolean suppressAutoDownload
    ) {
        if (!syncing.add(subscription.id())) {
            return new AutomationSyncResult(
                subscriptions.find(subscription.userId(), subscription.id()).orElseThrow(),
                false
            );
        }
        try {
            var managesVersions = versioningEnabled.test(subscription.userId());
            if (playlistImportService.isMissing(
                subscription.userId(), subscription.playlistId()
            )) {
                var target = playlistImportService.create(
                    subscription.userId(), subscription.name(), subscription.poolType()
                );
                subscriptions.retarget(subscription.id(), target.id());
                playlistImportService.addToHome(subscription.userId(), target.id());
                subscription = subscriptions.find(
                    subscription.userId(), subscription.id()
                ).orElseThrow();
            }
            downloadService.reconcileCompletedPlaylistDownloads(
                subscription.playlistId()
            );
            var preview = downloadService.parsePlaylist(subscription.sourceUrl());
            if (useRemoteName && preview.name() != null && !preview.name().isBlank()) {
                var remoteName = preview.name().strip();
                playlistImportService.rename(subscription.userId(), subscription.playlistId(), remoteName);
                subscriptions.rename(subscription.id(), remoteName);
                subscription = subscriptions.find(subscription.userId(), subscription.id()).orElseThrow();
            }
            String artworkUrl = null;
            String artworkHash = null;
            if (preview.artworkUrl() != null && !preview.artworkUrl().isBlank()) {
                artworkUrl = preview.artworkUrl().strip();
                if (artworkUrl.startsWith("https://") || artworkUrl.startsWith("http://")) {
                    if (managesVersions) {
                        artworkHash = artworkArchive.archive(artworkUrl).orElse(null);
                    }
                    playlistImportService.setRemoteArtwork(
                        subscription.userId(), subscription.playlistId(), artworkUrl
                    );
                } else {
                    artworkUrl = null;
                }
            }
            subscriptions.updateArtwork(
                subscription.id(), artworkUrl, artworkHash, managesVersions
            );
            var now = clock.millis();
            var items = new ArrayList<PlaylistSubscriptionRepository.Item>();
            var candidatesByItemKey = new HashMap<String, DownloadCandidate>();
            var blacklistedItemKeys = subscriptions.blacklistedItemKeys(subscription.id());
            var existingItems = subscriptions.findItems(subscription.id()).stream()
                .collect(java.util.stream.Collectors.toMap(
                    PlaylistSubscriptionRepository.Item::itemKey, item -> item,
                    (left, right) -> left
                ));
            var matchSession = matcher.open();
            var occurrences = new HashMap<String, Integer>();
            for (var position = 0; position < preview.items().size(); position++) {
                var candidate = preview.items().get(position);
                var keyBase = itemKeyBase(candidate);
                var occurrence = occurrences.merge(keyBase, 1, Integer::sum) - 1;
                var itemKey = itemKey(candidate, occurrence);
                candidatesByItemKey.put(itemKey, candidate);
                var existing = existingItems.get(itemKey);
                String matchedTrackId = null;
                List<PlaylistSubscriptionMatcher.Suggestion> suggestions = List.of();
                if (blacklistedItemKeys.contains(itemKey)) {
                    items.add(new PlaylistSubscriptionRepository.Item(
                        itemKey, position, candidate.title().strip(),
                        candidate.artist().strip(), candidate.album(), null,
                        "BLACKLISTED", now
                    ));
                    continue;
                } else if (existing != null && matchSession.containsTrack(existing.matchedTrackId())) {
                    matchedTrackId = existing.matchedTrackId();
                } else {
                    var rememberedTrackId = subscriptions.findRememberedMatch(
                        subscription.userId(), candidate.title(), candidate.artist()
                    ).orElse(null);
                    if (matchSession.containsTrack(rememberedTrackId)) {
                        matchedTrackId = rememberedTrackId;
                    } else {
                        var match = subscription.strictMode()
                            ? matchSession.match(candidate, Set.of())
                            : matchSession.match(candidate, Set.of(), false);
                        matchedTrackId = match.exactTrackId().orElse(null);
                        suggestions = match.suggestions();
                    }
                }
                var state = "MISSING";
                if (matchedTrackId != null) {
                    state = "MATCHED";
                } else if (!suggestions.isEmpty()) {
                    state = "SUGGESTED";
                } else if (candidate.downloadState() == DownloadTaskState.QUEUED
                    || candidate.downloadState() == DownloadTaskState.RUNNING) {
                    state = "DOWNLOADING";
                }
                items.add(new PlaylistSubscriptionRepository.Item(
                    itemKey, position, candidate.title().strip(),
                    candidate.artist().strip(), candidate.album(), matchedTrackId, state, now
                ));
            }
            var canDownloadMissing = !suppressAutoDownload
                && (subscription.autoDownload() || downloadMissing)
                && items.stream().noneMatch(item -> "SUGGESTED".equals(item.state()));
            if (canDownloadMissing) {
                for (var index = 0; index < items.size(); index++) {
                    var item = items.get(index);
                    if (!"MISSING".equals(item.state())) {
                        continue;
                    }
                    var candidate = candidatesByItemKey.get(item.itemKey());
                    if (candidate == null) {
                        continue;
                    }
                    if (downloadMissing) {
                        var restarted = downloadService.restartForPlaylist(
                            candidate, subscription.username(), subscription.playlistId(),
                            subscription.strictMode()
                        );
                        if (restarted.existingTrackId().isPresent()) {
                            items.set(index, new PlaylistSubscriptionRepository.Item(
                                item.itemKey(), item.position(), item.title(), item.artist(),
                                item.album(), restarted.existingTrackId().orElseThrow(),
                                "MATCHED", item.lastSeenAt()
                            ));
                        } else if (restarted.task().isPresent()) {
                            items.set(index, new PlaylistSubscriptionRepository.Item(
                                item.itemKey(), item.position(), item.title(), item.artist(),
                                item.album(), item.matchedTrackId(),
                                "DOWNLOADING", item.lastSeenAt()
                            ));
                        }
                    } else {
                        var queued = subscription.strictMode()
                            ? downloadService.queueForPlaylist(
                                candidate, subscription.username(), subscription.playlistId()
                            )
                            : downloadService.queueForPlaylist(
                                candidate, subscription.username(),
                                subscription.playlistId(), false
                            );
                        if (queued.isPresent()) {
                            items.set(index, new PlaylistSubscriptionRepository.Item(
                                item.itemKey(), item.position(), item.title(), item.artist(),
                                item.album(), item.matchedTrackId(),
                                "DOWNLOADING", item.lastSeenAt()
                            ));
                        }
                    }
                }
            }
            subscriptions.replaceItems(subscription.id(), items);
            subscriptions.markSynced(subscription.id());
            var createdVersion = managesVersions && publishVersionIfComplete(
                subscription, items, artworkHash, true
            );
            var refreshed = subscriptions.find(
                subscription.userId(), subscription.id()
            ).orElseThrow();
            if (!managesVersions) {
                playlistImportService.replaceTracks(
                    subscription.userId(), subscription.playlistId(),
                    items.stream()
                        .map(PlaylistSubscriptionRepository.Item::matchedTrackId)
                        .filter(java.util.Objects::nonNull)
                        .toList()
                );
            } else if (refreshed.followingLatest()) {
                applySelectedVersion(
                    refreshed, createdVersion,
                    items.stream()
                        .map(PlaylistSubscriptionRepository.Item::matchedTrackId)
                        .filter(java.util.Objects::nonNull)
                        .toList()
                );
            }
            return new AutomationSyncResult(refreshed, true);
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
                    sync(subscription, useRemoteName, false, false);
                } catch (RuntimeException ignored) {
                    // 同步错误已记录在订阅中，不能影响创建接口的快速返回。
                }
            });
        } catch (RejectedExecutionException exception) {
            subscriptions.markFailed(subscription.id(), "后台同步任务繁忙，请稍后手动同步");
        }
    }

    private void applySelectedVersion(
        PlaylistSubscriptionRepository.Subscription subscription, boolean forceArtwork
    ) {
        applySelectedVersion(subscription, forceArtwork, null);
    }

    private PlaylistSubscriptionRepository.Subscription refreshAfterMatching(
        PlaylistSubscriptionRepository.Subscription subscription
    ) {
        var items = subscriptions.findItems(subscription.id());
        if (!versioningEnabled.test(subscription.userId())) {
            playlistImportService.replaceTracks(
                subscription.userId(), subscription.playlistId(),
                items.stream()
                    .map(PlaylistSubscriptionRepository.Item::matchedTrackId)
                    .filter(java.util.Objects::nonNull)
                    .toList()
            );
            return subscriptions.find(
                subscription.userId(), subscription.id()
            ).orElseThrow();
        }
        var createdVersion = subscriptions.hasPendingArtworkState(subscription.id())
            && publishVersionIfComplete(
                subscription, items, subscriptions.pendingArtworkHash(subscription.id()), false
            );
        var refreshed = subscriptions.find(
            subscription.userId(), subscription.id()
        ).orElseThrow();
        applySelectedVersion(
            refreshed, createdVersion && refreshed.followingLatest()
        );
        return refreshed;
    }

    private boolean publishVersionIfComplete(
        PlaylistSubscriptionRepository.Subscription subscription,
        List<PlaylistSubscriptionRepository.Item> items,
        String artworkHash,
        boolean synchronizedNow
    ) {
        if (!versioningEnabled.test(subscription.userId())
            || (!synchronizedNow && subscription.lastSyncedAt() == null)
            || items.stream().anyMatch(item ->
                !"MATCHED".equals(item.state()) && !"BLACKLISTED".equals(item.state())
            )) {
            return false;
        }
        var savedVersion = subscriptions.saveVersion(
            subscription.id(), subscription.name(), artworkHash, items
        );
        return savedVersion != null
            && savedVersion.versionNumber() != subscription.latestVersionNumber();
    }

    private void applySelectedVersion(
        PlaylistSubscriptionRepository.Subscription subscription, boolean forceArtwork,
        List<String> fallbackTrackIds
    ) {
        var snapshot = subscriptions.selectedVersion(subscription.id());
        if (snapshot.isEmpty()) {
            playlistImportService.replaceTracks(
                subscription.userId(), subscription.playlistId(),
                fallbackTrackIds == null
                    ? subscriptions.matchedTrackIds(subscription.id())
                    : fallbackTrackIds
            );
            return;
        }
        var version = snapshot.get().version();
        playlistImportService.rename(
            subscription.userId(), subscription.playlistId(), version.name()
        );
        playlistImportService.replaceTracks(
            subscription.userId(), subscription.playlistId(),
            subscriptions.selectedMatchedTrackIds(subscription.id())
        );
        var artworkPath = version.hasArtwork()
            ? versionArtworkPath(subscription.id(), version)
            : null;
        playlistImportService.setVersionArtwork(
            subscription.userId(), subscription.playlistId(), artworkPath, forceArtwork
        );
    }

    private String versionArtworkPath(
        String subscriptionId, PlaylistSubscriptionRepository.Version version
    ) {
        return "/api/v1/me/playlist-subscriptions/" + subscriptionId
            + "/versions/" + version.versionNumber() + "/artwork?v=" + version.artworkHash();
    }

    private void requireVersionManagementEnabled(String userId) {
        if (!versioningEnabled.test(userId)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "歌单版本管理未开启");
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

    enum BestMatchMode {
        STRICT,
        IGNORE_BRACKETS
    }

    record BestMatchResult(
        PlaylistSubscriptionRepository.Subscription subscription, int matchedCount
    ) {
    }

    record OriginalDownloadResult(
        PlaylistSubscriptionRepository.Subscription subscription,
        int queuedCount, int skippedCount
    ) {
    }

    record AutomationSyncResult(
        PlaylistSubscriptionRepository.Subscription subscription, boolean performed
    ) {
    }

    record AutomationDownloadResult(List<DownloadTask> tasks, int skippedCount) {
    }

    private String conciseMessage(RuntimeException exception) {
        var message = exception.getMessage();
        if (message == null || message.isBlank()) {
            message = exception.getClass().getSimpleName();
        }
        return message.length() <= 500 ? message : message.substring(0, 500);
    }
}
