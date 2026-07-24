import AVFoundation
import Foundation
import MediaPlayer
import UIKit
import SwiftUI

enum PlaybackMode: CaseIterable {
    case sequential
    case repeatOne
    case shuffle

    var title: String {
        switch self {
        case .sequential: "顺序播放"
        case .repeatOne: "单曲循环"
        case .shuffle: "随机播放"
        }
    }

    var systemImage: String {
        switch self {
        case .sequential: "arrow.right"
        case .repeatOne: "repeat.1"
        case .shuffle: "shuffle"
        }
    }
}

@MainActor
final class PlaybackProgress: ObservableObject {
    @Published fileprivate(set) var elapsed: Double = 0
    @Published fileprivate(set) var duration: Double = 0

    fileprivate func update(elapsed: Double? = nil, duration: Double? = nil) {
        if let elapsed {
            self.elapsed = elapsed
        }
        if let duration {
            self.duration = duration
        }
    }
}

@MainActor
final class PlayerStore: ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackMode: PlaybackMode = .sequential
    @Published private(set) var playbackQueue: [Track] = []
    @Published private(set) var queueTitle = "随机播放"
    @Published private(set) var isLoadingQueue = false
    @Published private(set) var queueErrorMessage: String?
    @Published private(set) var queueType = "RANDOM"
    @Published private(set) var queueContextID: String?
    let progress = PlaybackProgress()

    var elapsed: Double { progress.elapsed }
    var duration: Double { progress.duration }

    private let player = AVPlayer()
    private var activeAPI = APIClient.shared
    private var offlineURLProvider: ((Track) -> URL?)?
    private var timeObserver: Any?
    private var itemEndObserver: NSObjectProtocol?
    private var itemFailureObserver: NSObjectProtocol?
    private var itemStalledObserver: NSObjectProtocol?
    private var audioInterruptionObserver: NSObjectProtocol?
    private var audioRouteChangeObserver: NSObjectProtocol?
    private var playbackResourceLoader: PlaybackCacheResourceLoader?
    private var stalledRecoveryTask: Task<Void, Never>?
    private var currentItemNeedsReload = false
    private var resumeAfterInterruption = false
    private var fallbackTrackID: String?
    private var artworkTask: Task<Void, Never>?
    private var randomQueueTask: Task<Void, Never>?
    private var stateRestoreTask: Task<Void, Never>?
    private var stateSaveTask: Task<Void, Never>?
    private var carPlayPlaybackTask: Task<Void, Never>?
    private var dailyRecommendationQueues: [[Track]]?
    private var dailyRecommendationQueueIndex: Int?
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var listenedSeconds: Double = 0
    private var hasRestoredState = false
    private var activeUserID: String?
    private var lastSavedProgressBucket: Int64 = -1
    private var favoriteStateProvider: ((String) -> Bool)?
    private var favoriteUpdateHandler: ((String, Bool) async -> Bool)?
    private var carPlayFavoriteTracksProvider: (() async -> [Track])?
    private var carPlayOfflineURLProvider: ((Track) -> URL?)?
    private var wasCarPlayConnected = false

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        configureAudioSession()
        observeTime()
        observeItemEnd()
        observeItemFailure()
        observeItemStalled()
        observeAudioInterruptions()
        wasCarPlayConnected = isCarPlayConnected
        observeAudioRouteChanges()
        configureRemoteCommands()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
        }
        if let itemFailureObserver {
            NotificationCenter.default.removeObserver(itemFailureObserver)
        }
        if let itemStalledObserver {
            NotificationCenter.default.removeObserver(itemStalledObserver)
        }
        if let audioInterruptionObserver {
            NotificationCenter.default.removeObserver(audioInterruptionObserver)
        }
        if let audioRouteChangeObserver {
            NotificationCenter.default.removeObserver(audioRouteChangeObserver)
        }
        artworkTask?.cancel()
        randomQueueTask?.cancel()
        stateRestoreTask?.cancel()
        stateSaveTask?.cancel()
        carPlayPlaybackTask?.cancel()
        stalledRecoveryTask?.cancel()
        playbackResourceLoader?.cancelAll()
    }

    var canGoPrevious: Bool {
        currentIndex != nil
    }

    var canGoNext: Bool {
        currentIndex != nil
    }

    func play(
        track: Track,
        queue: [Track],
        prioritizedQueueTitle: String? = nil,
        queueContextID: String? = nil,
        api: APIClient = .shared,
        offlineURLProvider: @escaping (Track) -> URL?
    ) {
        activeAPI = api
        self.offlineURLProvider = offlineURLProvider
        randomQueueTask?.cancel()
        stateRestoreTask?.cancel()
        dailyRecommendationQueues = nil
        dailyRecommendationQueueIndex = nil
        queueErrorMessage = nil

        if let prioritizedQueueTitle {
            playbackQueue = prioritizedQueue(queue, startingWith: track)
            queueTitle = prioritizedQueueTitle
            queueType = prioritizedQueueTitle == "发现" ? "DISCOVERY" : "PLAYLIST"
            self.queueContextID = queueContextID
            isLoadingQueue = false
        } else {
            playbackQueue = [track]
            queueTitle = "随机播放"
            queueType = "RANDOM"
            self.queueContextID = nil
        }

        if currentTrack?.id == track.id {
            resume()
        } else {
            startPlayback(track)
        }

        if prioritizedQueueTitle == nil {
            loadRandomQueue(keeping: track)
        }
    }

    func playDailyRecommendations(
        track: Track,
        queues: [[Track]],
        queueIndex: Int,
        api: APIClient = .shared,
        offlineURLProvider: @escaping (Track) -> URL?
    ) {
        guard queues.indices.contains(queueIndex), !queues[queueIndex].isEmpty else { return }
        activeAPI = api
        self.offlineURLProvider = offlineURLProvider
        randomQueueTask?.cancel()
        stateRestoreTask?.cancel()
        queueErrorMessage = nil
        dailyRecommendationQueues = queues
        dailyRecommendationQueueIndex = queueIndex
        playbackQueue = prioritizedQueue(queues[queueIndex], startingWith: track)
        queueTitle = "每日推荐 \(queueIndex + 1)"
        queueType = "DAILY"
        queueContextID = "daily-\(queueIndex)"
        isLoadingQueue = false

        if currentTrack?.id == track.id {
            resume()
        } else {
            startPlayback(track)
        }
    }

    private func startPlayback(
        _ track: Track,
        streamURLOverride: String? = nil,
        autoplay: Bool = true,
        persistState: Bool = true,
        usePlaybackCache: Bool = true
    ) {
        if streamURLOverride == nil {
            fallbackTrackID = nil
        }
        submitCurrentPlayback()
        stalledRecoveryTask?.cancel()
        stalledRecoveryTask = nil
        playbackResourceLoader?.cancelAll()
        playbackResourceLoader = nil
        currentItemNeedsReload = false
        let item: AVPlayerItem
        if let offlineURL = offlineURLProvider?(track) {
            item = AVPlayerItem(url: offlineURL)
        } else {
            let streamURL = activeAPI.url(for: streamURLOverride ?? track.streamURL)
            if usePlaybackCache {
                let resourceLoader = PlaybackCacheResourceLoader(originalURL: streamURL)
                playbackResourceLoader = resourceLoader
                item = AVPlayerItem(asset: resourceLoader.makeAsset())
            } else {
                let cookies = HTTPCookieStorage.shared.cookies(for: streamURL) ?? []
                let asset = AVURLAsset(
                    url: streamURL,
                    options: [AVURLAssetHTTPCookiesKey: cookies]
                )
                item = AVPlayerItem(asset: asset)
            }
        }
        item.preferredForwardBufferDuration = 30
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        player.replaceCurrentItem(with: item)
        currentTrack = track
        refreshRemoteFavoriteState()
        progress.update(elapsed: 0, duration: Double(track.durationMs) / 1_000)
        listenedSeconds = 0
        lastSavedProgressBucket = -1
        if autoplay {
            activateAudioSession()
            player.play()
        } else {
            player.pause()
        }
        isPlaying = autoplay
        loadNowPlayingArtwork(for: track)
        if persistState {
            self.persistState()
        }
    }

    private func restartPlayback(
        _ track: Track,
        at seconds: Double,
        streamURLOverride: String? = nil,
        usePlaybackCache: Bool
    ) {
        queueErrorMessage = nil
        startPlayback(
            track,
            streamURLOverride: streamURLOverride,
            persistState: false,
            usePlaybackCache: usePlaybackCache
        )
        if seconds > 0 {
            seek(to: seconds, persistState: false)
        }
        persistState()
    }

    func previous() {
        advance(by: -1, automatic: false)
    }

    func next() {
        advance(by: 1, automatic: false)
    }

    func cyclePlaybackMode() {
        guard let index = PlaybackMode.allCases.firstIndex(of: playbackMode) else { return }
        setPlaybackMode(PlaybackMode.allCases[(index + 1) % PlaybackMode.allCases.count])
    }

    func toggleShuffle() {
        setPlaybackMode(playbackMode == .shuffle ? .sequential : .shuffle)
    }

    func toggleRepeatOne() {
        setPlaybackMode(playbackMode == .repeatOne ? .sequential : .repeatOne)
    }

    func playQueuedTrack(_ track: Track) {
        guard playbackQueue.contains(where: { $0.id == track.id }) else { return }
        startPlayback(track)
    }

    func playNext(_ track: Track) {
        playbackQueue.removeAll { $0.id == track.id }
        let insertion = min((currentIndex ?? -1) + 1, playbackQueue.count)
        playbackQueue.insert(track, at: insertion)
        saveState()
    }

    func addToQueue(_ track: Track) {
        guard !playbackQueue.contains(where: { $0.id == track.id }) else { return }
        playbackQueue.append(track)
        saveState()
    }

    func moveQueueItems(from offsets: IndexSet, to destination: Int) {
        playbackQueue.move(fromOffsets: offsets, toOffset: destination)
        saveState()
    }

    func removeQueueItems(at offsets: IndexSet) {
        let currentID = currentTrack?.id
        playbackQueue.remove(atOffsets: offsets)
        if let currentID, !playbackQueue.contains(where: { $0.id == currentID }) {
            stop()
        } else {
            saveState()
        }
    }

    func removeTrack(id: String) {
        let wasCurrent = currentTrack?.id == id
        playbackQueue.removeAll { $0.id == id }
        if wasCurrent {
            stop()
        } else {
            saveState()
        }
    }

    func clearUpcomingQueue() {
        guard let currentTrack else { return }
        playbackQueue = [currentTrack]
        saveState()
    }

    func stop() {
        submitCurrentPlayback()
        clearCachedPlayback()
        clearLocalPlayback()
    }

    func stopForLogout() {
        clearLocalPlayback()
        activeUserID = nil
        hasRestoredState = false
        carPlayFavoriteTracksProvider = nil
        carPlayOfflineURLProvider = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    func beginSession(userID: String) {
        guard activeUserID != userID else { return }
        if activeUserID != nil {
            clearLocalPlayback()
        }
        activeUserID = userID
        hasRestoredState = false
        activeAPI = .shared
    }

    private func clearLocalPlayback() {
        player.pause()
        playbackResourceLoader?.cancelAll()
        playbackResourceLoader = nil
        player.replaceCurrentItem(with: nil)
        artworkTask?.cancel()
        randomQueueTask?.cancel()
        stateRestoreTask?.cancel()
        stateSaveTask?.cancel()
        carPlayPlaybackTask?.cancel()
        stalledRecoveryTask?.cancel()
        stalledRecoveryTask = nil
        dailyRecommendationQueues = nil
        dailyRecommendationQueueIndex = nil
        playbackQueue = []
        queueTitle = "随机播放"
        isLoadingQueue = false
        queueErrorMessage = nil
        currentTrack = nil
        fallbackTrackID = nil
        queueType = "RANDOM"
        queueContextID = nil
        offlineURLProvider = nil
        listenedSeconds = 0
        progress.update(elapsed: 0, duration: 0)
        isPlaying = false
        currentItemNeedsReload = false
        resumeAfterInterruption = false
        nowPlayingArtwork = nil
        lastSavedProgressBucket = -1
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        refreshRemoteFavoriteState()
    }

    func togglePlayback() {
        if player.timeControlStatus == .playing {
            pause()
        } else {
            resume()
        }
    }

    private func resume(persistState: Bool = true) {
        if currentItemNeedsReload, let currentTrack {
            restartPlayback(
                currentTrack,
                at: elapsed,
                usePlaybackCache: false
            )
            return
        }
        activateAudioSession()
        player.play()
        isPlaying = true
        updateNowPlaying()
        if persistState {
            self.persistState()
        }
    }

    private func pause() {
        stalledRecoveryTask?.cancel()
        stalledRecoveryTask = nil
        player.pause()
        isPlaying = false
        resumeAfterInterruption = false
        updateNowPlaying()
        persistState()
    }

    func seek(to seconds: Double, persistState: Bool = true) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        progress.update(elapsed: seconds)
        updateNowPlaying()
        if persistState {
            self.persistState()
        }
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // 系统会在首次播放时再次尝试激活音频会话。
        }
    }

    private func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func observeTime() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.progress.update(elapsed: max(0, time.seconds.isFinite ? time.seconds : 0))
                if self?.isPlaying == true {
                    self?.listenedSeconds += 0.5
                }
                self?.persistProgressIfNeeded()
            }
        }
    }

    private func observeItemEnd() {
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self,
                      let endedItem = notification.object as? AVPlayerItem,
                      endedItem === self.player.currentItem else { return }
                self.submitCurrentPlayback(forceProgress: 100)
                self.advance(by: 1, automatic: true)
            }
        }
    }

    private func observeItemFailure() {
        itemFailureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self,
                      let item = notification.object as? AVPlayerItem,
                      item === self.player.currentItem,
                      let track = self.currentTrack else { return }
                let failedAt = self.elapsed
                if self.playbackResourceLoader != nil {
                    self.restartPlayback(
                        track,
                        at: failedAt,
                        usePlaybackCache: false
                    )
                    return
                }
                guard self.fallbackTrackID != track.id else {
                    self.isPlaying = false
                    self.currentItemNeedsReload = true
                    self.queueErrorMessage = "本地与在线兜底均无法播放"
                    return
                }
                self.fallbackTrackID = track.id
                self.restartPlayback(
                    track,
                    at: failedAt,
                    streamURLOverride: "/api/v1/tracks/\(track.id)/fallback-stream",
                    usePlaybackCache: false
                )
            }
        }
    }

    private func observeItemStalled() {
        itemStalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self,
                      self.isPlaying,
                      let item = notification.object as? AVPlayerItem,
                      item === self.player.currentItem else { return }
                self.player.play()
                self.stalledRecoveryTask?.cancel()
                let stalledAt = self.elapsed
                self.stalledRecoveryTask = Task { [weak self, weak item] in
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled,
                          let self,
                          let item,
                          item === self.player.currentItem,
                          self.isPlaying,
                          self.player.timeControlStatus != .playing,
                          self.elapsed < stalledAt + 0.5,
                          let track = self.currentTrack else { return }
                    self.restartPlayback(
                        track,
                        at: stalledAt,
                        usePlaybackCache: false
                    )
                }
            }
        }
    }

    private func observeAudioInterruptions() {
        audioInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioInterruption(notification)
            }
        }
    }

    private func observeAudioRouteChanges() {
        audioRouteChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAudioRouteChange()
            }
        }
    }

    private func handleAudioRouteChange() {
        let connected = isCarPlayConnected
        let newlyConnected = connected && !wasCarPlayConnected
        wasCarPlayConnected = connected
        guard newlyConnected else { return }
        carPlayPlaybackTask?.cancel()
        carPlayPlaybackTask = Task { [weak self] in
            await self?.startCarPlayPlaybackIfNeeded()
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

        switch type {
        case .began:
            resumeAfterInterruption = isPlaying
            player.pause()
            isPlaying = false
            updateNowPlaying()
        case .ended:
            let shouldResumePlayback = resumeAfterInterruption
            resumeAfterInterruption = false
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            guard shouldResumePlayback,
                  options.contains(.shouldResume),
                  currentTrack != nil else { return }
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                player.play()
                isPlaying = true
            } catch {
                isPlaying = false
            }
            updateNowPlaying()
        @unknown default:
            break
        }
    }

    private var currentIndex: Int? {
        guard let currentTrack else { return nil }
        return playbackQueue.firstIndex { $0.id == currentTrack.id }
    }

    private func advance(by offset: Int, automatic: Bool) {
        guard let index = currentIndex else { return }

        if automatic && playbackMode == .repeatOne {
            submitCurrentPlayback(forceProgress: 100)
            listenedSeconds = 0
            seek(to: 0)
            resume()
            return
        }

        let candidate = index + offset
        if playbackQueue.indices.contains(candidate) {
            startPlayback(playbackQueue[candidate])
            return
        }

        if offset > 0 {
            guard PlaybackQueueTransition.canLeaveQueue(automatic: automatic) else { return }
            if queueType != "RANDOM" {
                let api = activeAPI
                let completedType = queueType
                let completedContext = queueContextID
                Task { try? await api.recordPlayedBatch(
                    queueType: completedType, queueContextID: completedContext
                ) }
            }
            if automatic, advanceToNextDailyRecommendationQueue() {
                return
            }
            replaceWithRandomQueue()
            return
        }

        guard let last = playbackQueue.last else { return }
        startPlayback(last)
    }

    private func advanceToNextDailyRecommendationQueue() -> Bool {
        guard let queues = dailyRecommendationQueues,
              let currentQueueIndex = dailyRecommendationQueueIndex else { return false }
        var nextQueueIndex = currentQueueIndex + 1
        while queues.indices.contains(nextQueueIndex) {
            let nextQueue = queues[nextQueueIndex]
            if let first = nextQueue.first {
                dailyRecommendationQueueIndex = nextQueueIndex
                playbackQueue = prioritizedQueue(nextQueue, startingWith: first)
                queueTitle = "每日推荐 \(nextQueueIndex + 1)"
                queueType = "DAILY"
                queueContextID = "daily-\(nextQueueIndex)"
                startPlayback(first)
                return true
            }
            nextQueueIndex += 1
        }
        return false
    }

    private func setPlaybackMode(_ mode: PlaybackMode) {
        let shouldShuffle = mode == .shuffle && playbackMode != .shuffle
        playbackMode = mode
        if shouldShuffle, let currentTrack {
            playbackQueue = [currentTrack] + playbackQueue
                .filter { $0.id != currentTrack.id }
                .shuffled()
            persistState()
        }
    }

    private func prioritizedQueue(_ queue: [Track], startingWith track: Track) -> [Track] {
        let values = queue.contains(where: { $0.id == track.id }) ? queue : queue + [track]
        guard playbackMode == .shuffle else { return values }
        return [track] + values.filter { $0.id != track.id }.shuffled()
    }

    private func loadRandomQueue(keeping track: Track) {
        isLoadingQueue = true
        let api = activeAPI
        randomQueueTask = Task { [weak self] in
            do {
                let randomTracks = try await api.randomTracks(limit: 50)
                guard !Task.isCancelled,
                      let self,
                      self.currentTrack?.id == track.id else { return }
                var seen = Set([track.id])
                let remaining = randomTracks.filter { seen.insert($0.id).inserted }
                self.playbackQueue = Array(([track] + remaining).prefix(50))
                self.isLoadingQueue = false
                self.updateNowPlaying()
                self.persistState()
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.isLoadingQueue = false
                self.queueErrorMessage = error.localizedDescription
            }
        }
    }

    private func replaceWithRandomQueue() {
        guard !isLoadingQueue else { return }
        dailyRecommendationQueues = nil
        dailyRecommendationQueueIndex = nil
        isPlaying = false
        isLoadingQueue = true
        queueErrorMessage = nil
        updateNowPlaying()
        let api = activeAPI
        let previousTrackID = currentTrack?.id
        randomQueueTask?.cancel()
        randomQueueTask = Task { [weak self] in
            do {
                var randomTracks = try await api.randomTracks(limit: 50)
                guard !Task.isCancelled, let self else { return }
                if randomTracks.count > 1, randomTracks.first?.id == previousTrackID {
                    randomTracks.append(randomTracks.removeFirst())
                }
                self.playbackQueue = randomTracks
                self.queueTitle = "随机播放"
                self.queueType = "RANDOM"
                self.queueContextID = nil
                self.isLoadingQueue = false
                guard let first = randomTracks.first else {
                    self.queueErrorMessage = "曲库中没有可播放的歌曲"
                    return
                }
                self.startPlayback(first)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.isLoadingQueue = false
                self.queueErrorMessage = error.localizedDescription
            }
        }
    }

    private func submitCurrentPlayback(forceProgress: Double? = nil) {
        guard let trackID = currentTrack?.id else { return }
        let listenedMs = Int64(max(0, listenedSeconds) * 1_000)
        listenedSeconds = 0
        let progress = forceProgress ?? (duration > 0 ? min(100, elapsed / duration * 100) : 0)
        let api = activeAPI
        Task {
            try? await api.recordPlayback(
                trackID: trackID,
                listenedMs: listenedMs,
                progressPercent: progress
            )
        }
    }

    func saveState() {
        submitCurrentPlayback()
        persistState()
    }

    func flushState() async {
        guard let snapshot = playbackStateSnapshot() else { return }
        cachePlaybackState()
        submitCurrentPlayback()
        stateSaveTask?.cancel()
        try? await snapshot.api.savePlaybackState(
            queueType: snapshot.queueType,
            queueContextID: snapshot.queueContextID,
            trackID: snapshot.trackID,
            queueTrackIDs: snapshot.queueTrackIDs,
            progressMs: snapshot.progressMs
        )
    }

    private func persistProgressIfNeeded() {
        guard currentTrack != nil else { return }
        let bucket = Int64(max(0, elapsed)) / 5
        guard bucket != lastSavedProgressBucket else { return }
        lastSavedProgressBucket = bucket
        persistState()
    }

    private func persistState() {
        guard let snapshot = playbackStateSnapshot() else { return }
        cachePlaybackState()
        stateSaveTask?.cancel()
        stateSaveTask = Task {
            try? await snapshot.api.savePlaybackState(
                queueType: snapshot.queueType,
                queueContextID: snapshot.queueContextID,
                trackID: snapshot.trackID,
                queueTrackIDs: snapshot.queueTrackIDs,
                progressMs: snapshot.progressMs
            )
        }
    }

    private func playbackStateSnapshot() -> PlaybackStateSnapshot? {
        guard let currentTrack else { return nil }
        let api = activeAPI
        return PlaybackStateSnapshot(
            api: api,
            queueType: queueType,
            queueContextID: queueContextID,
            trackID: currentTrack.id,
            queueTrackIDs: PlaybackRestoration.orderedTrackIDs(
                currentTrackID: currentTrack.id,
                queueTrackIDs: playbackQueue.map(\.id)
            ),
            progressMs: Int64(max(0, elapsed) * 1_000)
        )
    }

    func restoreCachedStateIfAvailable(
        offlineURLProvider: @escaping (Track) -> URL?
    ) {
        guard currentTrack == nil,
              let key = playbackCacheKey,
              let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(CachedPlaybackState.self, from: data),
              let track = state.queue.first(where: { $0.id == state.currentTrackID }) else {
            return
        }
        self.offlineURLProvider = offlineURLProvider
        configureRestoredQueue(type: state.queueType, contextID: state.queueContextID)
        playbackQueue = state.queue
        startPlayback(track, autoplay: false, persistState: false)
        seek(to: Double(state.progressMs) / 1_000, persistState: false)
        if isCarPlayConnected {
            resume(persistState: false)
        }
    }

    func restoreStateIfNeeded(offlineURLProvider: @escaping (Track) -> URL?) async {
        guard !hasRestoredState else { return }
        do {
            guard let state = try await activeAPI.playbackState() else {
                clearCachedPlayback()
                clearLocalPlayback()
                hasRestoredState = true
                return
            }
            let initialTrackID = currentTrack?.id
            let cachedTrack = currentTrack?.id == state.trackId ? currentTrack : nil
            let track: Track
            do {
                track = try await activeAPI.track(id: state.trackId)
            } catch APIError.server(let status, _) where status == 404 {
                clearCachedPlayback()
                clearLocalPlayback()
                hasRestoredState = true
                return
            } catch {
                guard let cachedTrack else { throw error }
                track = cachedTrack
            }
            guard currentTrack?.id == initialTrackID else {
                return
            }
            self.offlineURLProvider = offlineURLProvider
            configureRestoredQueue(type: state.queueType, contextID: state.queueContextId)
            if playbackQueue.isEmpty {
                playbackQueue = [track]
            }
            if currentTrack?.id == track.id {
                currentTrack = track
                progress.update(duration: Double(track.durationMs) / 1_000)
            } else {
                startPlayback(track, autoplay: false, persistState: false)
            }
            seek(to: Double(state.progressMs) / 1_000, persistState: false)
            if hasAutomaticPlaybackRoute {
                resume(persistState: false)
            }
            hasRestoredState = true

            let trackIDs = PlaybackRestoration.orderedTrackIDs(
                currentTrackID: state.trackId,
                queueTrackIDs: state.queueTrackIds
            )
            let api = activeAPI
            isLoadingQueue = true
            stateRestoreTask?.cancel()
            stateRestoreTask = Task { [weak self] in
                var restoredQueue: [Track] = []
                for id in trackIDs {
                    guard !Task.isCancelled else { return }
                    if id == track.id {
                        restoredQueue.append(track)
                    } else if let queueTrack = try? await api.track(id: id) {
                        restoredQueue.append(queueTrack)
                    }
                }
                guard !Task.isCancelled,
                      let self,
                      self.currentTrack?.id == track.id,
                      !restoredQueue.isEmpty else { return }
                self.playbackQueue = restoredQueue
                self.isLoadingQueue = false
                self.cachePlaybackState()
            }
        } catch {
            hasRestoredState = false
            queueErrorMessage = error.localizedDescription
        }
    }

    private func configureRestoredQueue(type: String, contextID: String?) {
        queueType = type
        queueContextID = contextID
        if type == "DISCOVERY" {
            queueTitle = "发现"
        } else if type == "DAILY" {
            queueTitle = "每日推荐"
        } else if type == "PLAYLIST" {
            queueTitle = "歌单"
        } else {
            queueTitle = "随机播放"
        }
    }

    private var playbackCacheKey: String? {
        activeUserID.map { "sona.playback.cache.\($0)" }
    }

    private func cachePlaybackState() {
        guard let key = playbackCacheKey, let currentTrack else { return }
        var queue = playbackQueue
        if !queue.contains(where: { $0.id == currentTrack.id }) {
            queue.insert(currentTrack, at: 0)
        }
        let state = CachedPlaybackState(
            queueType: queueType,
            queueContextID: queueContextID,
            currentTrackID: currentTrack.id,
            queue: queue,
            progressMs: Int64(max(0, elapsed) * 1_000)
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func clearCachedPlayback() {
        guard let key = playbackCacheKey else { return }
        UserDefaults.standard.removeObject(forKey: key)
    }

    func prepareRandomQueueIfNeeded(
        offlineURLProvider: @escaping (Track) -> URL?
    ) async {
        guard currentTrack == nil, playbackQueue.isEmpty else { return }
        do {
            playbackQueue = try await activeAPI.randomTracks(limit: 50)
            queueTitle = "随机播放"
            queueType = "RANDOM"
            queueContextID = nil
            guard let first = playbackQueue.first else {
                queueErrorMessage = "曲库中没有可播放的歌曲"
                return
            }
            self.offlineURLProvider = offlineURLProvider
            startPlayback(first, autoplay: hasAutomaticPlaybackRoute)
        } catch {
            queueErrorMessage = error.localizedDescription
        }
    }

    func prepareChildModeRandomQueue(
        offlineURLProvider: @escaping (Track) -> URL?
    ) async {
        randomQueueTask?.cancel()
        stateRestoreTask?.cancel()
        dailyRecommendationQueues = nil
        dailyRecommendationQueueIndex = nil
        queueErrorMessage = nil
        isLoadingQueue = true
        if currentTrack?.poolType != "CHILD" {
            pause()
        }
        defer { isLoadingQueue = false }

        do {
            let randomTracks = try await activeAPI.randomTracks(limit: 50, childMode: true)
            guard !Task.isCancelled else { return }
            playbackQueue = randomTracks
            queueTitle = "儿童随机播放"
            queueType = "RANDOM"
            queueContextID = nil
            self.offlineURLProvider = offlineURLProvider
            guard let first = randomTracks.first else {
                if currentTrack?.poolType != "CHILD" {
                    clearLocalPlayback()
                }
                queueTitle = "儿童随机播放"
                queueErrorMessage = "儿童歌池中暂无可播放的歌曲"
                return
            }
            startPlayback(first, autoplay: false)
        } catch {
            guard !Task.isCancelled else { return }
            queueErrorMessage = error.localizedDescription
        }
    }

    private var hasAutomaticPlaybackRoute: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
            switch output.portType {
            case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .carAudio:
                true
            default:
                false
            }
        }
    }

    private var isCarPlayConnected: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
            switch output.portType {
            case .carAudio:
                true
            default:
                false
            }
        }
    }

    private struct PlaybackStateSnapshot {
        let api: APIClient
        let queueType: String
        let queueContextID: String?
        let trackID: String
        let queueTrackIDs: [String]
        let progressMs: Int64
    }

    private struct CachedPlaybackState: Codable {
        let queueType: String
        let queueContextID: String?
        let currentTrackID: String
        let queue: [Track]
        let progressMs: Int64
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let position = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.seek(to: position.positionTime) }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        commands.likeCommand.localizedTitle = "收藏"
        commands.likeCommand.localizedShortTitle = "收藏"
        commands.likeCommand.isEnabled = false
        commands.likeCommand.addTarget { [weak self] event in
            guard let event = event as? MPFeedbackCommandEvent else {
                return .commandFailed
            }
            let isFavorite = !event.isNegative
            Task { @MainActor in
                await self?.setCurrentTrackFavorite(isFavorite)
            }
            return .success
        }
    }

    func configureFavoriteCommand(
        isFavorite: @escaping (String) -> Bool,
        updateFavorite: @escaping (String, Bool) async -> Bool
    ) {
        favoriteStateProvider = isFavorite
        favoriteUpdateHandler = updateFavorite
        refreshRemoteFavoriteState()
    }

    func configureCarPlayAutoPlayback(
        favoriteTracks: @escaping () async -> [Track],
        offlineURLProvider: @escaping (Track) -> URL?
    ) {
        carPlayFavoriteTracksProvider = favoriteTracks
        carPlayOfflineURLProvider = offlineURLProvider
    }

    func startCarPlayPlaybackIfNeeded() async {
        guard isCarPlayConnected else { return }
        if currentTrack != nil {
            if !isPlaying {
                resume()
            }
            return
        }
        guard let favoriteTracksProvider = carPlayFavoriteTracksProvider,
              let offlineURLProvider = carPlayOfflineURLProvider else { return }
        let favoriteTracks = await favoriteTracksProvider()
        guard !Task.isCancelled, isCarPlayConnected, currentTrack == nil else { return }
        if let first = favoriteTracks.first {
            play(
                track: first,
                queue: favoriteTracks,
                prioritizedQueueTitle: "收藏的歌曲",
                queueContextID: "liked-songs",
                offlineURLProvider: offlineURLProvider
            )
            return
        }
        await prepareRandomQueueIfNeeded(offlineURLProvider: offlineURLProvider)
    }

    func refreshRemoteFavoriteState() {
        let likeCommand = MPRemoteCommandCenter.shared().likeCommand
        guard let currentTrack, let favoriteStateProvider else {
            likeCommand.isEnabled = false
            likeCommand.isActive = false
            return
        }
        likeCommand.isEnabled = favoriteUpdateHandler != nil
        likeCommand.isActive = favoriteStateProvider(currentTrack.id)
    }

    private func setCurrentTrackFavorite(_ isFavorite: Bool) async {
        guard let currentTrack, let favoriteUpdateHandler else { return }
        _ = await favoriteUpdateHandler(currentTrack.id, isFavorite)
        refreshRemoteFavoriteState()
    }

    private func loadNowPlayingArtwork(for track: Track) {
        artworkTask?.cancel()
        nowPlayingArtwork = fallbackArtwork().map(makeArtwork)
        updateNowPlaying()

        guard let path = track.artworkURL else { return }
        let trackID = track.id
        let api = activeAPI
        artworkTask = Task { [weak self] in
            guard let image = try? await RemoteImageCache.shared.image(for: api.url(for: path)),
                  !Task.isCancelled,
                  let self,
                  self.currentTrack?.id == trackID else { return }
            self.nowPlayingArtwork = self.makeArtwork(image)
            self.updateNowPlaying()
        }
    }

    private func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private func fallbackArtwork() -> UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String] else {
            return UIImage(named: "AppIcon60x60")
        }
        return iconFiles.reversed().compactMap(UIImage.init(named:)).first
    }

    private func updateNowPlaying() {
        guard let currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentTrack.title,
            MPMediaItemPropertyArtist: currentTrack.artist,
            MPMediaItemPropertyAlbumTitle: currentTrack.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: currentIndex ?? 0,
            MPNowPlayingInfoPropertyPlaybackQueueCount: playbackQueue.count
        ]
        if let nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = nowPlayingArtwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
