#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacMainView: View {
    @EnvironmentObject private var player: PlayerStore
    @Binding var selectedTab: SonaTab
    @Binding var showsNowPlaying: Bool
    let availableRelease: AppReleaseInfo?
    let openDrawer: () -> Void
    @State private var showsQueue = true
    @State private var showsCompactQueue = false
    @State private var requestedCollectionID: String?
    @State private var libraryNavigationRequestID = 0
    @State private var createPlaylistRequestID = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .trailing) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        MacSidebar(
                            selectedTab: $selectedTab,
                            openLibraryCollection: { collectionID in
                                requestedCollectionID = collectionID
                                libraryNavigationRequestID += 1
                                selectedTab = .library
                            },
                            createPlaylist: {
                                createPlaylistRequestID += 1
                                selectedTab = .library
                            },
                            openProfileMenu: openDrawer
                        )
                            .frame(width: 246)

                        page
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.sonaBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        if showsQueue && proxy.size.width >= 1_080 {
                            MacQueuePanel()
                                .frame(width: min(320, proxy.size.width * 0.24))
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                    MacPlayerBar(
                        queueIsVisible: proxy.size.width >= 1_080 ? showsQueue : showsCompactQueue,
                        toggleQueue: {
                            if proxy.size.width >= 1_080 {
                                showsQueue.toggle()
                            } else {
                                showsCompactQueue.toggle()
                            }
                        },
                        openNowPlaying: { showsNowPlaying = true }
                    )
                    .frame(height: 92)
                }

                if showsCompactQueue && proxy.size.width < 1_080 {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture { showsCompactQueue = false }

                    MacQueuePanel(onClose: { showsCompactQueue = false })
                        .frame(width: min(360, max(1, proxy.size.width - 32)))
                        .padding(8)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                if showsNowPlaying {
                    NowPlayingView(onClose: { showsNowPlaying = false })
                        .transition(.opacity)
                        .zIndex(2)
                }
            }
            .background(Color.black)
        }
        .animation(.easeInOut(duration: 0.18), value: showsQueue)
        .animation(.easeInOut(duration: 0.18), value: showsCompactQueue)
        .animation(.easeInOut(duration: 0.18), value: showsNowPlaying)
    }

    @ViewBuilder
    private var page: some View {
        switch selectedTab {
        case .home:
            HomeView(openDrawer: {})
        case .discovery:
            DiscoveryView(openDrawer: {})
        case .search:
            SearchView(openDrawer: {})
        case .library:
            MusicLibraryView(
                openDrawer: {},
                requestedCollectionID: requestedCollectionID,
                libraryNavigationRequestID: libraryNavigationRequestID,
                createPlaylistRequestID: createPlaylistRequestID
            )
        case .settings:
            SettingsView(availableRelease: availableRelease)
        }
    }
}

private struct MacSidebar: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var personal: PersonalStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @Binding var selectedTab: SonaTab
    let openLibraryCollection: (String) -> Void
    let createPlaylist: () -> Void
    let openProfileMenu: () -> Void
    @State private var loadedPlaylistTracks: [String: Track] = [:]
    @State private var playlistPlaybackTask: Task<Void, Never>?

    private let primaryItems: [(SonaTab, String, String)] = [
        (.home, "首页", "house.fill"),
        (.discovery, "发现", "sparkles"),
        (.search, "搜索", "magnifyingglass"),
        (.library, "音乐库", "books.vertical.fill")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.sonaGreen)
                Text("Sona")
                    .font(.system(size: 22, weight: .bold))
            }
            .padding(.horizontal, 18)
            .frame(height: 64)

            VStack(spacing: 4) {
                ForEach(primaryItems, id: \.0) { tab, title, icon in
                    sidebarButton(tab: tab, title: title, icon: icon)
                }
                sidebarButton(tab: .settings, title: "设置", icon: "gearshape.fill")
            }
            .padding(.horizontal, 8)

            Divider()
                .overlay(Color.white.opacity(0.12))
                .padding(.vertical, 14)

            HStack {
                Text("你的音乐库")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.sonaSecondaryText)
                Spacer()
                Button(action: createPlaylist) {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.sonaSecondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新建歌单")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 2) {
                    MacSidebarLibraryRow(
                        title: "收藏的歌曲",
                        subtitle: "歌单",
                        icon: "heart.fill",
                        color: Color(red: 0.43, green: 0.30, blue: 0.78),
                        openAction: { openLibraryCollection("liked-songs") },
                        playAction: playFavorites
                    )
                    ForEach(personal.playlists) { playlist in
                        MacSidebarLibraryRow(
                            title: playlist.name,
                            subtitle: "歌单 · \(session.currentUser?.username ?? "Sona")",
                            icon: "music.note.list",
                            color: .sonaSurface,
                            artworkURL: artworkURL(for: playlist),
                            openAction: { openLibraryCollection(playlist.id) },
                            playAction: { play(playlist) }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Button(action: openProfileMenu) {
                HStack(spacing: 10) {
                    SonaAvatarView(
                        username: session.currentUser?.username ?? "Sona",
                        avatarPreset: session.currentUser?.avatarPreset,
                        avatarURL: session.currentUser?.avatarURL,
                        size: 32
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.currentUser?.username ?? "Sona")
                            .font(.subheadline.weight(.semibold))
                        Text(session.currentUser?.role.title ?? "用户")
                            .font(.caption2)
                            .foregroundStyle(Color.sonaSecondaryText)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .padding(14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开账户菜单")
        }
        .foregroundStyle(.white)
        .background(Color(red: 0.055, green: 0.055, blue: 0.055))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func sidebarButton(tab: SonaTab, title: String, icon: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selectedTab == tab ? .white : Color.sonaSecondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 42)
                .background(
                    selectedTab == tab ? Color.white.opacity(0.10) : .clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
    }

    private func playFavorites() {
        playlistPlaybackTask?.cancel()
        playlistPlaybackTask = Task {
            let tracks = await personal.loadAllFavoriteTracks()
            guard !Task.isCancelled else { return }
            playLibraryCollection(
                title: "收藏的歌曲",
                id: "liked-songs",
                tracks: tracks
            )
        }
    }

    private func play(_ playlist: Playlist) {
        playlistPlaybackTask?.cancel()
        playlistPlaybackTask = Task {
            var tracks: [Track] = []
            for id in playlist.trackIDs where !personal.hiddenTrackIDs.contains(id) {
                guard !Task.isCancelled else { return }
                if let track = library.track(id: id) ?? loadedPlaylistTracks[id] {
                    tracks.append(track)
                } else if let track = try? await APIClient.shared.track(id: id) {
                    loadedPlaylistTracks[id] = track
                    tracks.append(track)
                }
                if tracks.count == 1 {
                    playLibraryCollection(
                        title: playlist.name,
                        id: playlist.id,
                        tracks: tracks
                    )
                }
            }
            guard !Task.isCancelled else { return }
            if tracks.count > 1 {
                playLibraryCollection(
                    title: playlist.name,
                    id: playlist.id,
                    tracks: tracks
                )
            }
        }
    }

    private func playLibraryCollection(title: String, id: String, tracks: [Track]) {
        let visibleTracks = tracks.filter { !personal.hiddenTrackIDs.contains($0.id) }
        guard let first = visibleTracks.first else { return }
        switch player.playbackMode {
        case .shuffle:
            player.toggleShuffle()
        case .repeatOne:
            player.toggleRepeatOne()
        case .sequential:
            break
        }
        player.play(
            track: first,
            queue: visibleTracks,
            prioritizedQueueTitle: title,
            queueContextID: id,
            offlineURLProvider: offline.localURL(for:)
        )
    }

    private func artworkURL(for playlist: Playlist) -> String? {
        sonaArtworkPaths(playlist.artworkURLs).first
            ?? sonaFirstArtworkURL(in: playlist.trackIDs.compactMap(library.track(id:)))
    }
}

private struct MacSidebarLibraryRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    var artworkURL: String? = nil
    let openAction: () -> Void
    let playAction: () -> Void
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .leading) {
            Button(action: openAction) {
                HStack(spacing: 10) {
                    artwork
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.sonaSecondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
                .padding(.horizontal, 8)
                .frame(height: 54)
                .contentShape(Rectangle())
                .background(
                    isHovered ? Color.white.opacity(0.09) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
            }
            .buttonStyle(.plain)

            if isHovered {
                Button(action: playAction) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 3)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("播放")
                .padding(.leading, 8)
                .transition(.opacity)
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL {
            ArtworkView(path: artworkURL, cornerRadius: 4, thumbnailSize: 192)
                .frame(width: 42, height: 42)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: icon)
                        .foregroundStyle(.white)
                }
        }
    }
}

private struct MacQueuePanel: View {
    @EnvironmentObject private var player: PlayerStore
    var onClose: (() -> Void)? = nil

    private var upcomingTracks: [Track] {
        guard let current = player.currentTrack,
              let index = player.playbackQueue.firstIndex(where: { $0.id == current.id }) else {
            return player.playbackQueue
        }
        return Array(player.playbackQueue.dropFirst(index + 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("播放队列")
                    .font(.title3.bold())
                Spacer()
                if let onClose {
                    Button("关闭", systemImage: "xmark") { onClose() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                }
            }
            .padding(.top, 18)

            if let track = player.currentTrack {
                Text("正在播放")
                    .font(.caption.bold())
                    .foregroundStyle(Color.sonaSecondaryText)
                queueRow(track, isCurrent: true)
            }

            HStack {
                Text("接下来播放")
                    .font(.caption.bold())
                    .foregroundStyle(Color.sonaSecondaryText)
                Spacer()
                if !upcomingTracks.isEmpty {
                    Button("清除") { player.clearUpcomingQueue() }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                }
            }

            if upcomingTracks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.line.last.and.arrowtriangle.forward")
                        .font(.largeTitle)
                    Text("队列中暂无歌曲")
                        .font(.subheadline)
                }
                .foregroundStyle(Color.sonaSecondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(upcomingTracks) { track in
                            Button { player.playQueuedTrack(track) } label: {
                                queueRow(track, isCurrent: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .foregroundStyle(.white)
        .background(Color(red: 0.055, green: 0.055, blue: 0.055))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func queueRow(_ track: Track, isCurrent: Bool) -> some View {
        HStack(spacing: 10) {
            ArtworkView(path: track.artworkURL, cornerRadius: 4)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .foregroundStyle(isCurrent ? Color.sonaGreen : .white)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(Color.sonaSecondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(track.durationText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.sonaSecondaryText)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct MacPlayerBar: View {
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var personal: PersonalStore
    let queueIsVisible: Bool
    let toggleQueue: () -> Void
    let openNowPlaying: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            currentTrack
                .frame(maxWidth: .infinity, alignment: .leading)

            playbackControls
                .frame(maxWidth: .infinity)

            trailingControls
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .foregroundStyle(.white)
        .background(Color.black)
    }

    private var currentTrack: some View {
        HStack(spacing: 12) {
            ArtworkView(path: player.currentTrack?.artworkURL, cornerRadius: 5)
                .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 4) {
                Text(player.currentTrack?.title ?? "选择一首歌曲开始播放")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(player.currentTrack?.artist ?? "Sona")
                    .font(.caption)
                    .foregroundStyle(Color.sonaSecondaryText)
                    .lineLimit(1)
            }
            if let track = player.currentTrack {
                Button {
                    Task { await personal.toggleFavorite(trackID: track.id) }
                } label: {
                    Image(systemName: personal.favoriteIDs.contains(track.id) ? "heart.fill" : "heart")
                        .foregroundStyle(personal.favoriteIDs.contains(track.id) ? Color.sonaGreen : .white)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if player.currentTrack != nil { openNowPlaying() } }
    }

    private var playbackControls: some View {
        VStack(spacing: 7) {
            HStack(spacing: 24) {
                Button { player.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .foregroundStyle(player.playbackMode == .shuffle ? Color.sonaGreen : .white)
                }
                Button { player.previous() } label: {
                    Image(systemName: "backward.end.fill")
                }
                Button { player.togglePlayback() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 34))
                }
                Button { player.next() } label: {
                    Image(systemName: "forward.end.fill")
                }
                Button { player.toggleRepeatOne() } label: {
                    Image(systemName: player.playbackMode == .repeatOne ? "repeat.1" : "repeat")
                        .foregroundStyle(player.playbackMode == .repeatOne ? Color.sonaGreen : .white)
                }
            }
            .buttonStyle(.plain)
            .disabled(player.currentTrack == nil)

            HStack(spacing: 9) {
                Text(time(player.elapsed))
                Slider(
                    value: Binding(
                        get: { player.elapsed },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 1)
                )
                .tint(.white)
                Text(time(player.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Color.sonaSecondaryText)
        }
    }

    private var trailingControls: some View {
        HStack(spacing: 14) {
            if let track = player.currentTrack {
                Text(track.qualityText)
                    .font(.caption)
                    .foregroundStyle(Color.sonaGreen)
                    .lineLimit(1)
            }
            Button {
                toggleQueue()
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(queueIsVisible ? Color.sonaGreen : .white)
            }
            .buttonStyle(.plain)
        }
    }

    private func time(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
#endif
