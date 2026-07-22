import SwiftUI

struct SonaCollection: Identifiable {
    enum Shape {
        case square
        case circle
    }

    let id: String
    let title: String
    let subtitle: String
    let artworkURL: String?
    let artworkURLs: [String]
    let rotatesArtworkHourly: Bool
    let tracks: [Track]
    let shape: Shape

    init(
        id: String,
        title: String,
        subtitle: String,
        artworkURL: String?,
        artworkURLs: [String] = [],
        rotatesArtworkHourly: Bool = false,
        tracks: [Track],
        shape: Shape
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.artworkURLs = artworkURLs
        self.rotatesArtworkHourly = rotatesArtworkHourly
        self.tracks = tracks
        self.shape = shape
    }
}

func sonaAlbums(from tracks: [Track]) -> [SonaCollection] {
    Dictionary(grouping: tracks) { $0.album }
        .map { album, albumTracks in
            return SonaCollection(
                id: "album-\(album)",
                title: album,
                subtitle: albumTracks.first?.artist ?? "未知艺人",
                artworkURL: albumTracks.first(where: { $0.artworkURL != nil })?.artworkURL,
                tracks: albumTracks.sorted {
                    ($0.trackNumber ?? Int.max, $0.title) < ($1.trackNumber ?? Int.max, $1.title)
                },
                shape: .square
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
}

func sonaArtists(from tracks: [Track]) -> [SonaCollection] {
    var displayNames: [String: String] = [:]
    var groupedTracks: [String: [String: Track]] = [:]
    for track in tracks {
        let artist = (track.artists.first ?? track.artist)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !artist.isEmpty else { continue }
        let key = artist.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        if displayNames[key] == nil { displayNames[key] = artist }
        groupedTracks[key, default: [:]][track.id] = track
    }
    return groupedTracks
        .map { key, tracksByID in
            let artist = displayNames[key] ?? "未知艺人"
            let uniqueTracks = tracksByID.values.sorted {
                let leftIsCanonical = $0.artist.trimmingCharacters(in: .whitespacesAndNewlines) == artist
                let rightIsCanonical = $1.artist.trimmingCharacters(in: .whitespacesAndNewlines) == artist
                if leftIsCanonical != rightIsCanonical { return leftIsCanonical }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return SonaCollection(
                id: "artist-\(artist)",
                title: artist,
                subtitle: "艺人",
                artworkURL: uniqueTracks.first(where: { $0.artworkURL != nil })?.artworkURL,
                tracks: uniqueTracks,
                shape: .circle
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
}

@MainActor
func sonaUniqueHistoryTracks(_ history: [HistoryItem], library: LibraryStore) -> [Track] {
    var seen = Set<String>()
    return history.compactMap { item in
        guard seen.insert(item.trackID).inserted else { return nil }
        return library.track(id: item.trackID)
    }
}

struct SonaAvatarButton: View {
    @EnvironmentObject private var session: SessionStore
    let username: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SonaAvatarView(
                username: username,
                avatarPreset: session.currentUser?.avatarPreset,
                avatarURL: session.currentUser?.avatarURL,
                size: 32
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开账户菜单")
    }
}

struct SonaAvatarView: View {
    let username: String
    var avatarPreset: String?
    var avatarURL: String?
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let avatarURL, avatarPreset == nil {
                ArtworkView(path: avatarURL, cornerRadius: size / 2)
            } else {
                Circle()
                    .fill(avatarGradient)
                    .overlay {
                        if let preset = AvatarPreset(rawValue: avatarPreset ?? "") {
                            Image(preset.assetName)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Text(String(
                                username.trimmingCharacters(in: .whitespaces).first ?? "S"
                            ).uppercased())
                                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                                .foregroundStyle(.black.opacity(0.82))
                        }
                    }
            }
        }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
    }

    private var avatarGradient: LinearGradient {
        let colors: [Color] = switch AvatarPreset(rawValue: avatarPreset ?? "") {
        case .aurora: [.green, .purple]
        case .cosmos: [.indigo, .blue]
        case .forest: [.green, .brown]
        case .ocean: [.cyan, .blue]
        case .sunset: [.orange, .pink]
        case .candy: [.pink, .purple]
        case .ember: [.red, .orange]
        case .midnight: [.black, .indigo]
        case nil: [.sonaGreen.opacity(0.95), Color(red: 0.02, green: 0.28, blue: 0.14)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct SonaFilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color.black.opacity(0.86) : .white)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(isSelected ? Color.sonaGreen : Color.sonaChip, in: Capsule())
            .buttonStyle(.plain)
    }
}

struct SonaSectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.white)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.sonaSecondaryText)
            }
        }
    }
}

struct SonaLikedCover: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.30, green: 0.10, blue: 0.95), Color(red: 0.67, green: 0.88, blue: 0.77)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "heart.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

struct SonaCollectionArtwork: View {
    let collection: SonaCollection
    var size: CGFloat

    var body: some View {
        Group {
            if collection.rotatesArtworkHourly {
                TimelineView(.periodic(from: .now, by: 60 * 60)) { context in
                    ArtworkView(
                        path: rotatingArtwork(at: context.date),
                        cornerRadius: collection.shape == .circle ? size / 2 : 6,
                        thumbnailSize: requestedThumbnailSize
                    )
                }
            } else if collection.artworkURLs.count < 2 {
                ArtworkView(
                    path: collection.artworkURLs.first ?? collection.artworkURL,
                    cornerRadius: collection.shape == .circle ? size / 2 : 6,
                    thumbnailSize: requestedThumbnailSize
                )
            } else {
                SonaMosaicArtwork(
                    paths: collection.artworkURLs,
                    thumbnailSize: requestedThumbnailSize / 2
                )
            }
        }
            .frame(width: size, height: size)
            .clipShape(collection.shape == .circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
    }

    private func rotatingArtwork(at date: Date) -> String? {
        guard !collection.artworkURLs.isEmpty else { return nil }
        let hour = UInt64(date.timeIntervalSince1970 / (60 * 60))
        let offset = collection.id.utf8.reduce(UInt64(0)) { $0 &* 31 &+ UInt64($1) }
        let index = Int((hour &+ offset) % UInt64(collection.artworkURLs.count))
        return collection.artworkURLs[index]
    }

    private var requestedThumbnailSize: Int {
        size <= 80 ? 256 : 768
    }
}

private struct SonaMosaicArtwork: View {
    let paths: [String]
    let thumbnailSize: Int

    var body: some View {
        GeometryReader { proxy in
            let cellSize = proxy.size.width / 2
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(cellSize), spacing: 0), count: 2),
                spacing: 0
            ) {
                ForEach(0..<4, id: \.self) { index in
                    ArtworkView(
                        path: index < paths.count ? paths[index] : nil,
                        cornerRadius: 0,
                        thumbnailSize: thumbnailSize
                    )
                    .frame(width: cellSize, height: cellSize)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct SonaMediaCard: View {
    let collection: SonaCollection
    var width: CGFloat = 168

    private let dailyColors: [Color] = [
        Color(red: 0.13, green: 0.91, blue: 0.91),
        Color(red: 0.91, green: 0.95, blue: 0.18),
        Color(red: 1.00, green: 0.27, blue: 0.16),
        Color(red: 0.96, green: 0.48, blue: 0.74),
        Color(red: 0.35, green: 0.78, blue: 0.58),
        Color(red: 0.62, green: 0.49, blue: 0.95)
    ]

    private var dailyIndex: Int? {
        guard collection.id.hasPrefix("daily-") else { return nil }
        return Int(collection.id.dropFirst("daily-".count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let dailyIndex {
                dailyArtwork(color: dailyColors[dailyIndex % dailyColors.count])
            } else {
                SonaCollectionArtwork(collection: collection, size: width)
                Text(collection.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Text(collection.subtitle)
                .font(.caption)
                .foregroundStyle(Color.sonaSecondaryText)
                .lineLimit(2)
        }
        .frame(width: width, alignment: .leading)
    }

    private func dailyArtwork(color: Color) -> some View {
        SonaCollectionArtwork(collection: collection, size: width)
            .overlay(alignment: .topLeading) {
                Image(systemName: "music.note")
                    .font(.caption.bold())
                    .foregroundStyle(Color.sonaBackground)
                    .frame(width: 26, height: 26)
                    .background(color, in: Circle())
                    .padding(8)
            }
            .overlay(alignment: .bottom) {
                Text(collection.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.sonaBackground)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(color.opacity(0.94))
                    .padding(6)
            }
    }
}

struct SonaMacHoverMediaCard<Content: View>: View {
    var artworkSize: CGFloat = 168
    let playAction: () -> Void
    private let content: Content
    @State private var isHovered = false

    init(
        artworkSize: CGFloat = 168,
        playAction: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.artworkSize = artworkSize
        self.playAction = playAction
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        #if targetEnvironment(macCatalyst)
        ZStack(alignment: .topLeading) {
            content
                .padding(10)
                .background(
                    isHovered ? Color.white.opacity(0.09) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )

            if isHovered {
                Button(action: playAction) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 48, height: 48)
                        .background(Color.sonaGreen, in: Circle())
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("播放")
                .offset(x: artworkSize - 46, y: artworkSize - 46)
                .transition(.scale(scale: 0.88).combined(with: .opacity))
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovered)
        #else
        content
        #endif
    }
}

struct SonaMacHoverShortcutCard<Content: View>: View {
    let playAction: () -> Void
    private let content: Content
    @State private var isHovered = false

    init(playAction: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.playAction = playAction
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        #if targetEnvironment(macCatalyst)
        ZStack(alignment: .trailing) {
            cardContent

            if isHovered {
                Button(action: playAction) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 34, height: 34)
                        .background(Color.sonaGreen, in: Circle())
                        .shadow(color: .black.opacity(0.32), radius: 5, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("播放")
                .padding(.trailing, 8)
                .transition(.scale(scale: 0.88).combined(with: .opacity))
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovered)
        #else
        cardContent
        #endif
    }

    private var cardContent: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.sonaSurface.opacity(0.95))
                    .overlay {
                        if isHovered {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.09))
                        }
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct SonaTrackListView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var personal: PersonalStore
    @State private var isSelecting = false
    @State private var selectedIDs = Set<String>()
    @State private var showsImporter = false
    @State private var showsServerDirectoryPicker = false
    @State private var importMessage: String?
    @State private var isImportingServerDirectory = false
    @State private var importProgressMessage = ""
    @State private var loadedPlaylistTracks: [String: Track] = [:]
    @State private var isLoadingPlaylistTracks = false
    @State private var editedTracks: [String: Track] = [:]
    @State private var editingTrack: Track?
    let collection: SonaCollection
    let playbackQueue: [Track]?
    let dailyRecommendationQueues: [[Track]]?
    let loadsMoreFromLibrary: Bool

    init(
        collection: SonaCollection,
        playbackQueue: [Track]? = nil,
        dailyRecommendationQueues: [[Track]]? = nil,
        loadsMoreFromLibrary: Bool = false
    ) {
        self.collection = collection
        self.playbackQueue = playbackQueue
        self.dailyRecommendationQueues = dailyRecommendationQueues
        self.loadsMoreFromLibrary = loadsMoreFromLibrary
    }

    private var playlist: Playlist? {
        guard collection.id.hasPrefix("playlist-") else { return nil }
        let id = String(collection.id.dropFirst("playlist-".count))
        return personal.playlists.first { $0.id == id }
    }

    private var displayedCollection: SonaCollection {
        guard let playlist else { return collection }
        return SonaCollection(
            id: collection.id,
            title: collection.title,
            subtitle: collection.subtitle,
            artworkURL: playlist.artworkURLs.first,
            artworkURLs: playlist.artworkURLs,
            rotatesArtworkHourly: playlist.artworkTrackID == nil,
            tracks: tracks,
            shape: collection.shape
        )
    }

    private var tracks: [Track] {
        let values: [Track]
        if collection.id == "liked-songs" {
            if !personal.favoriteTracks.isEmpty || personal.favoriteIDs.isEmpty {
                values = personal.favoriteTracks
            } else {
                values = library.tracks.filter { personal.favoriteIDs.contains($0.id) }
            }
        } else if let playlist {
            values = playlist.trackIDs.compactMap {
                library.track(id: $0) ?? loadedPlaylistTracks[$0]
            }
        } else {
            values = loadsMoreFromLibrary ? library.tracks : collection.tracks
        }
        return values
            .map { editedTracks[$0.id] ?? $0 }
            .filter { !personal.hiddenTrackIDs.contains($0.id) }
    }

    private var trackCount: Int {
        if collection.id == "liked-songs" { return personal.favoriteIDs.count }
        return playlist?.trackIDs.count ?? tracks.count
    }

    private var queue: [Track] {
        if prioritizedQueueTitle != nil {
            return tracks
        }
        guard let playbackQueue, !playbackQueue.isEmpty else { return tracks }
        return playbackQueue
    }

    private var prioritizedQueueTitle: String? {
        let isPlaylist = collection.id == "liked-songs" ||
            collection.id.hasPrefix("playlist-") ||
            collection.subtitle.hasPrefix("歌单")
        guard collection.id == "daily-recommendations" ||
            isPlaylist || collection.id.hasPrefix("album-") else { return nil }
        return collection.title
    }

    private var queueContextID: String? {
        prioritizedQueueTitle == nil ? nil : collection.id
    }

    private var showsShuffleButton: Bool {
        collection.id == "daily-recommendations" ||
            collection.id == "liked-songs" ||
            collection.id.hasPrefix("playlist-") ||
            collection.subtitle.hasPrefix("歌单")
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.sonaSurface.opacity(0.95), .sonaBackground, .sonaBackground],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 0) {
                    VStack(spacing: 18) {
                        SonaCollectionArtwork(collection: displayedCollection, size: 230)
                            .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
                        VStack(spacing: 5) {
                            Text(collection.title)
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                            Text(collection.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(Color.sonaSecondaryText)
                        }
                        HStack {
                            Text("\(trackCount) 首歌曲")
                                .font(.caption)
                                .foregroundStyle(Color.sonaSecondaryText)
                            Spacer()
                            if showsShuffleButton {
                                Button {
                                    playRandom()
                                } label: {
                                    Image(systemName: "shuffle")
                                        .font(.title3.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 48, height: 48)
                                        .background(.white.opacity(0.1), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("随机播放")
                                .disabled(
                                    tracks.isEmpty ||
                                    (collection.id == "liked-songs" && personal.isLoadingMoreFavorites)
                                )
                            }
                            Button {
                                if collection.id == "liked-songs" {
                                    Task {
                                        let allTracks = await personal.loadAllFavoriteTracks()
                                        guard let first = allTracks.first else { return }
                                        player.play(
                                            track: first,
                                            queue: allTracks,
                                            prioritizedQueueTitle: prioritizedQueueTitle,
                                            queueContextID: queueContextID,
                                            offlineURLProvider: offline.localURL(for:)
                                        )
                                    }
                                } else {
                                    guard let first = tracks.first else { return }
                                    play(first)
                                }
                            } label: {
                                if collection.id == "liked-songs" {
                                    if personal.isLoadingMoreFavorites {
                                        ProgressView()
                                            .tint(.black)
                                            .frame(width: 48, height: 48)
                                            .background(Color.sonaGreen, in: Circle())
                                    } else {
                                        Label("播放全部", systemImage: "play.fill")
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.black)
                                            .padding(.horizontal, 18)
                                            .frame(height: 48)
                                            .background(Color.sonaGreen, in: Capsule())
                                    }
                                } else {
                                    Image(systemName: "play.fill")
                                        .font(.title2)
                                        .foregroundStyle(.black)
                                        .frame(width: 56, height: 56)
                                        .background(Color.sonaGreen, in: Circle())
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(
                                tracks.isEmpty ||
                                (collection.id == "liked-songs" && personal.isLoadingMoreFavorites)
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)

                    if isLoadingPlaylistTracks && tracks.isEmpty {
                        ProgressView("正在载入歌单…")
                            .padding(.vertical, 18)
                    }

                    ForEach(tracks) { track in
                        HStack {
                            if isSelecting {
                                Image(systemName: selectedIDs.contains(track.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Color.sonaGreen)
                            }
                            TrackRow(
                                track: track,
                                showsOfflineBadge: offline.downloadedIDs.contains(track.id),
                                isFavorite: personal.favoriteIDs.contains(track.id),
                                moreActionTitle: playlistArtworkActionTitle(for: track),
                                moreActionSystemImage: playlist?.artworkTrackID == track.id
                                    ? "checkmark.circle.fill" : "photo",
                                moreActionDisabled: playlist?.artworkTrackID == track.id,
                                moreAction: playlistArtworkAction(for: track),
                                tapAction: {
                                    if isSelecting {
                                        if !selectedIDs.insert(track.id).inserted {
                                            selectedIDs.remove(track.id)
                                        }
                                    } else {
                                        play(track)
                                    }
                                }
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .contextMenu {
                            if session.currentUser?.isAdmin == true {
                                Button("编辑歌曲名和歌手", systemImage: "pencil") {
                                    editingTrack = track
                                }
                            }
                            Button("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") {
                                player.playNext(track)
                            }
                            Button("添加到播放队列", systemImage: "text.badge.plus") {
                                player.addToQueue(track)
                            }
                        }
                        .task {
                            if collection.id == "liked-songs" {
                                await personal.loadNextFavoritePageIfNeeded(currentTrack: track)
                            } else if loadsMoreFromLibrary {
                                await library.loadNextPageIfNeeded(currentTrack: track)
                            }
                        }
                    }

                    if collection.id == "liked-songs" && personal.isLoadingMoreFavorites {
                        ProgressView("载入更多…")
                            .padding(.vertical, 18)
                    } else if loadsMoreFromLibrary && library.isLoadingMore {
                        ProgressView("载入更多…")
                            .padding(.vertical, 18)
                    }
                }
                .padding(.bottom, 24)
            }

            if isImportingServerDirectory {
                DirectoryImportProgressOverlay(message: importProgressMessage)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            Button(
                tracks.allSatisfy { offline.downloadedIDs.contains($0.id) }
                    ? "已全部离线" : "全部离线",
                systemImage: "arrow.down.circle"
            ) {
                Task {
                    let values = collection.id == "liked-songs"
                        ? await personal.loadAllFavoriteTracks() : tracks
                    await offline.downloadAll(values)
                }
            }
            .disabled(tracks.isEmpty || tracks.contains { offline.activeDownloads.contains($0.id) })
            if collection.id == "liked-songs" {
                if session.currentUser?.isAdmin == true {
                    Menu("导入", systemImage: "square.and.arrow.down") {
                        Button("扫描服务器音乐目录", systemImage: "externaldrive") {
                            showsServerDirectoryPicker = true
                        }
                        Button("从 App 本地导入", systemImage: "iphone") {
                            showsImporter = true
                        }
                    }
                }
                Button(isSelecting ? "完成" : "多选") {
                    isSelecting.toggle()
                    if !isSelecting { selectedIDs.removeAll() }
                }
                if isSelecting, !selectedIDs.isEmpty {
                    Button("移除 \(selectedIDs.count) 首", role: .destructive) {
                        let ids = selectedIDs
                        Task {
                            await personal.removeFavorites(trackIDs: ids)
                            selectedIDs.removeAll()
                            isSelecting = false
                        }
                    }
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: playlist?.trackIDs) {
            await loadMissingPlaylistTracks()
        }
        .sheet(item: $editingTrack) { track in
            TrackIdentityEditorView(track: track) { updated in
                editedTracks[updated.id] = updated
                library.applyTrackUpdate(updated)
                personal.applyTrackUpdate(updated)
                if loadedPlaylistTracks[updated.id] != nil {
                    loadedPlaylistTracks[updated.id] = updated
                }
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            Task { await importLocalFiles(result) }
        }
        .sheet(isPresented: $showsServerDirectoryPicker) {
            ServerDirectoryPicker { directory in
                Task { await importServerDirectory(directory) }
            }
        }
        .alert("导入结果", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("好") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    private func loadMissingPlaylistTracks() async {
        guard let playlist else { return }
        isLoadingPlaylistTracks = true
        defer { isLoadingPlaylistTracks = false }
        for id in playlist.trackIDs
        where library.track(id: id) == nil && loadedPlaylistTracks[id] == nil {
            guard !Task.isCancelled else { return }
            if let track = try? await APIClient.shared.track(id: id) {
                loadedPlaylistTracks[id] = track
            }
        }
    }

    private func playlistArtworkActionTitle(for track: Track) -> String? {
        guard session.currentUser?.isAdmin == true,
              playlist != nil,
              track.artworkURL != nil else { return nil }
        return playlist?.artworkTrackID == track.id ? "当前歌单封面" : "设为歌单封面"
    }

    private func playlistArtworkAction(for track: Track) -> (() -> Void)? {
        guard session.currentUser?.isAdmin == true,
              let playlist,
              track.artworkURL != nil else { return nil }
        return {
            guard playlist.artworkTrackID != track.id else { return }
            Task {
                await personal.setPlaylistArtwork(
                    playlistID: playlist.id,
                    trackID: track.id
                )
            }
        }
    }

    private func play(_ track: Track) {
        if let dailyRecommendationQueues,
           let queueIndex = Int(collection.id.dropFirst("daily-".count)) {
            player.playDailyRecommendations(
                track: track,
                queues: dailyRecommendationQueues,
                queueIndex: queueIndex,
                offlineURLProvider: offline.localURL(for:)
            )
            return
        }
        player.play(
            track: track,
            queue: queue,
            prioritizedQueueTitle: prioritizedQueueTitle,
            queueContextID: queueContextID,
            offlineURLProvider: offline.localURL(for:)
        )
    }

    private func playRandom() {
        if collection.id == "liked-songs" {
            Task {
                playRandom(await personal.loadAllFavoriteTracks())
            }
        } else {
            playRandom(tracks)
        }
    }

    private func playRandom(_ values: [Track]) {
        let shuffled = values.shuffled()
        guard let first = shuffled.first else { return }
        player.play(
            track: first,
            queue: shuffled,
            prioritizedQueueTitle: prioritizedQueueTitle,
            queueContextID: queueContextID,
            offlineURLProvider: offline.localURL(for:)
        )
    }

    private func importServerDirectory(_ directory: ServerMusicDirectory) async {
        isImportingServerDirectory = true
        importProgressMessage = "正在加入已入库歌曲…"
        defer { isImportingServerDirectory = false }
        do {
            let result = try await APIClient.shared.importFavorites(directory: directory.path)
            await personal.refresh()
            importMessage = result.scanning == true
                ? "“\(directory.name)”已快速加入收藏 \(result.importedCount) 首，后台正在补入新歌曲"
                : "“\(directory.name)”已加入收藏 \(result.importedCount) 首"
        } catch {
            importMessage = error.localizedDescription
        }
    }

    private func importLocalFiles(_ result: Result<[URL], Error>) async {
        do {
            let urls = try result.get()
            let record = try? await APIClient.shared.createImportRecord(
                type: .localFiles,
                source: "\(urls.count) 个本地文件",
                target: "正常歌曲池",
                total: urls.count
            )
            let upload = await APIClient.shared.uploadTracks(urls: urls)
            guard upload.succeeded > 0 else {
                if let record {
                    let _ = try? await APIClient.shared.updateImportRecord(
                        id: record.id,
                        update: ImportRecordUpdate(
                            state: .failed,
                            succeeded: 0,
                            failed: upload.failed,
                            message: upload.message ?? "文件上传失败"
                        )
                    )
                }
                importMessage = upload.message ?? "文件上传失败"
                return
            }
            if let record {
                let _ = try? await APIClient.shared.updateImportRecord(
                    id: record.id,
                    update: ImportRecordUpdate(
                        state: .running,
                        succeeded: upload.succeeded,
                        failed: upload.failed,
                        message: "正在扫描曲库…"
                    )
                )
            }
            await library.scan()
            if let errorMessage = library.errorMessage {
                if let record {
                    let _ = try? await APIClient.shared.updateImportRecord(
                        id: record.id,
                        update: scanRecordUpdate(
                            state: .failed,
                            status: library.scanStatus,
                            succeeded: upload.succeeded,
                            failed: upload.failed + max(library.scanStatus?.failed ?? 0, 1),
                            message: errorMessage
                        )
                    )
                }
                importMessage = errorMessage
                return
            }
            if let record {
                let _ = try? await APIClient.shared.updateImportRecord(
                    id: record.id,
                    update: scanRecordUpdate(
                        state: .completed,
                        status: library.scanStatus,
                        succeeded: upload.succeeded,
                        failed: upload.failed,
                        message: upload.failed > 0 ? "部分文件上传失败" : "已完成"
                    )
                )
            }
            await personal.refresh()
            importMessage = upload.failed == 0
                ? "已导入 \(upload.succeeded) 首到正常歌曲池"
                : "已导入 \(upload.succeeded) 首，失败 \(upload.failed) 首"
        } catch {
            importMessage = error.localizedDescription
        }
    }
}

struct DirectoryImportProgressOverlay: View {
    let message: String

    var body: some View {
        Color.black.opacity(0.45)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Color.sonaGreen)
                    Text(message)
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.center)
                    Text("目录较大时可能需要几分钟")
                        .font(.caption)
                        .foregroundStyle(Color.sonaSecondaryText)
                }
                .padding(24)
                .frame(maxWidth: 260)
                .background(Color.sonaSurface, in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("服务器目录导入中，\(message)")
    }
}
