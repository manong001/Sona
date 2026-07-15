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
final class PlayerStore: ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var playbackMode: PlaybackMode = .sequential
    @Published private(set) var playbackQueue: [Track] = []
    @Published private(set) var queueTitle = "随机播放"
    @Published private(set) var isLoadingQueue = false
    @Published private(set) var queueErrorMessage: String?
    @Published private(set) var queueType = "RANDOM"
    @Published private(set) var queueContextID: String?

    private let player = AVPlayer()
    private var activeAPI = APIClient.shared
    private var offlineURLProvider: ((Track) -> URL?)?
    private var timeObserver: Any?
    private var itemEndObserver: NSObjectProtocol?
    private var artworkTask: Task<Void, Never>?
    private var randomQueueTask: Task<Void, Never>?
    private var dailyRecommendationQueues: [[Track]]?
    private var dailyRecommendationQueueIndex: Int?
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var listenedSeconds: Double = 0
    private var hasRestoredState = false

    init() {
        configureAudioSession()
        observeTime()
        observeItemEnd()
        configureRemoteCommands()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
        }
        artworkTask?.cancel()
        randomQueueTask?.cancel()
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

    private func startPlayback(_ track: Track) {
        submitCurrentPlayback()
        let item: AVPlayerItem
        if let offlineURL = offlineURLProvider?(track) {
            item = AVPlayerItem(url: offlineURL)
        } else {
            let streamURL = activeAPI.url(for: track.streamURL)
            let cookies = HTTPCookieStorage.shared.cookies(for: streamURL) ?? []
            let asset = AVURLAsset(
                url: streamURL,
                options: [AVURLAssetHTTPCookiesKey: cookies]
            )
            item = AVPlayerItem(asset: asset)
        }
        player.replaceCurrentItem(with: item)
        currentTrack = track
        elapsed = 0
        duration = Double(track.durationMs) / 1_000
        listenedSeconds = 0
        player.play()
        isPlaying = true
        loadNowPlayingArtwork(for: track)
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

    func clearUpcomingQueue() {
        guard let currentTrack else { return }
        playbackQueue = [currentTrack]
        saveState()
    }

    func stop() {
        submitCurrentPlayback()
        player.pause()
        player.replaceCurrentItem(with: nil)
        artworkTask?.cancel()
        randomQueueTask?.cancel()
        dailyRecommendationQueues = nil
        dailyRecommendationQueueIndex = nil
        playbackQueue = []
        queueTitle = "随机播放"
        isLoadingQueue = false
        queueErrorMessage = nil
        currentTrack = nil
        listenedSeconds = 0
        elapsed = 0
        duration = 0
        isPlaying = false
        nowPlayingArtwork = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func togglePlayback() {
        if player.timeControlStatus == .playing {
            pause()
        } else {
            resume()
        }
    }

    private func resume() {
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    private func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        elapsed = seconds
        updateNowPlaying()
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // 系统会在首次播放时再次尝试激活音频会话。
        }
    }

    private func observeTime() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.elapsed = max(0, time.seconds.isFinite ? time.seconds : 0)
                if self?.isPlaying == true {
                    self?.listenedSeconds += 0.5
                }
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
        guard let currentTrack else { return }
        submitCurrentPlayback()
        let api = activeAPI
        let type = queueType
        let context = queueContextID
        let progress = Int64(max(0, elapsed) * 1_000)
        Task {
            try? await api.savePlaybackState(
                queueType: type,
                queueContextID: context,
                trackID: currentTrack.id,
                queueTrackIDs: playbackQueue.map(\.id),
                progressMs: progress
            )
        }
    }

    func restoreStateIfNeeded(offlineURLProvider: @escaping (Track) -> URL?) async {
        guard !hasRestoredState, currentTrack == nil else { return }
        hasRestoredState = true
        do {
            guard let state = try await activeAPI.playbackState() else { return }
            var restoredQueue: [Track] = []
            let trackIDs = state.queueTrackIds.isEmpty ? [state.trackId] : state.queueTrackIds
            for id in trackIDs {
                if let track = try? await activeAPI.track(id: id) { restoredQueue.append(track) }
            }
            guard let track = restoredQueue.first(where: { $0.id == state.trackId }) else { return }
            self.offlineURLProvider = offlineURLProvider
            queueType = state.queueType
            queueContextID = state.queueContextId
            queueTitle = state.queueType == "DISCOVERY" ? "发现" : (state.queueContextId ?? "随机播放")
            playbackQueue = restoredQueue
            startPlayback(track)
            seek(to: Double(state.progressMs) / 1_000)
            pause()
            if state.queueType == "RANDOM" { loadRandomQueue(keeping: track) }
        } catch {
            queueErrorMessage = error.localizedDescription
        }
    }

    func prepareRandomQueueIfNeeded() async {
        guard currentTrack == nil, playbackQueue.isEmpty else { return }
        do {
            playbackQueue = try await activeAPI.randomTracks(limit: 50)
            queueTitle = "随机播放"
            queueType = "RANDOM"
            queueContextID = nil
        } catch {
            queueErrorMessage = error.localizedDescription
        }
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
    }

    private func loadNowPlayingArtwork(for track: Track) {
        artworkTask?.cancel()
        nowPlayingArtwork = fallbackArtwork().map(makeArtwork)
        updateNowPlaying()

        guard let path = track.artworkURL else { return }
        let trackID = track.id
        let api = activeAPI
        artworkTask = Task { [weak self] in
            guard let data = try? await api.data(at: path),
                  !Task.isCancelled,
                  let image = UIImage(data: data),
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
