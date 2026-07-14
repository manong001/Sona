import AVFoundation
import Foundation
import MediaPlayer
import UIKit

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

    private let player = AVPlayer()
    private var queue: [Track] = []
    private var activeAPI = APIClient.shared
    private var offlineURLProvider: ((Track) -> URL?)?
    private var timeObserver: Any?
    private var itemEndObserver: NSObjectProtocol?
    private var artworkTask: Task<Void, Never>?
    private var nowPlayingArtwork: MPMediaItemArtwork?

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
    }

    var canGoPrevious: Bool {
        guard queue.count > 1, let index = currentIndex else { return false }
        return playbackMode == .shuffle || index > queue.startIndex
    }

    var canGoNext: Bool {
        guard queue.count > 1, let index = currentIndex else { return false }
        return playbackMode == .shuffle || index < queue.index(before: queue.endIndex)
    }

    func play(
        track: Track,
        queue: [Track],
        api: APIClient = .shared,
        offlineURLProvider: @escaping (Track) -> URL?
    ) {
        self.queue = queue.contains(where: { $0.id == track.id }) ? queue : queue + [track]
        activeAPI = api
        self.offlineURLProvider = offlineURLProvider

        if currentTrack?.id == track.id {
            resume()
            return
        }

        startPlayback(track)
    }

    private func startPlayback(_ track: Track) {
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
        playbackMode = PlaybackMode.allCases[(index + 1) % PlaybackMode.allCases.count]
    }

    func toggleShuffle() {
        playbackMode = playbackMode == .shuffle ? .sequential : .shuffle
    }

    func toggleRepeatOne() {
        playbackMode = playbackMode == .repeatOne ? .sequential : .repeatOne
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        artworkTask?.cancel()
        queue = []
        currentTrack = nil
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
                self.advance(by: 1, automatic: true)
            }
        }
    }

    private var currentIndex: Int? {
        guard let currentTrack else { return nil }
        return queue.firstIndex { $0.id == currentTrack.id }
    }

    private func advance(by offset: Int, automatic: Bool) {
        guard let index = currentIndex else { return }

        if automatic && playbackMode == .repeatOne {
            seek(to: 0)
            resume()
            return
        }

        let targetIndex: Int?
        if playbackMode == .shuffle {
            targetIndex = queue.indices.filter { $0 != index }.randomElement()
        } else {
            let candidate = index + offset
            targetIndex = queue.indices.contains(candidate) ? candidate : nil
        }

        guard let targetIndex else {
            if automatic {
                isPlaying = false
                updateNowPlaying()
            }
            return
        }
        startPlayback(queue[targetIndex])
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
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count
        ]
        if let nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = nowPlayingArtwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
