import AVFoundation
import Foundation
import MediaPlayer

@MainActor
final class PlayerStore: ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0

    private let player = AVPlayer()
    private var timeObserver: Any?

    init() {
        configureAudioSession()
        observeTime()
        configureRemoteCommands()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    func play(track: Track, api: APIClient = .shared, offlineURL: URL? = nil) {
        if currentTrack?.id == track.id {
            player.play()
            isPlaying = true
            updateNowPlaying()
            return
        }

        let item: AVPlayerItem
        if let offlineURL {
            item = AVPlayerItem(url: offlineURL)
        } else {
            let streamURL = api.url(for: track.streamURL)
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
        updateNowPlaying()
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
    }

    private func updateNowPlaying() {
        guard let currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: currentTrack.title,
            MPMediaItemPropertyArtist: currentTrack.artist,
            MPMediaItemPropertyAlbumTitle: currentTrack.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }
}
