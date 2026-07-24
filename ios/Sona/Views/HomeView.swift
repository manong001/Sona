import SwiftUI

private let favoriteRotationInterval: Duration = .seconds(5)

struct HomeView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var personal: PersonalStore
    @State private var selectedFilter = "全部"
    @State private var dailyTracks: [Track] = []
    @State private var genres: [String] = []
    @State private var madeForYouMixes: [MadeForYouMix] = []
    @State private var favoriteRotationOffset = 0
    @State private var loadedHomePlaylistTracks: [String: Track] = [:]
    @State private var homePlaylistPlaybackTask: Task<Void, Never>?
    @AppStorage("childMode") private var childMode = false
    @AppStorage("miniPlayerMode") private var miniPlayerMode = "floating"
    let openDrawer: () -> Void

    private let chartShortcuts = [
        ChartShortcut(
            region: "ALL", title: "热歌总榜", subtitle: "全站播放热度",
            systemImage: "flame.fill", color: Color(red: 0.72, green: 0.19, blue: 0.26)
        ),
        ChartShortcut(
            region: "CN", title: "中文榜", subtitle: "中文热门歌曲",
            systemImage: "music.mic", color: Color(red: 0.74, green: 0.29, blue: 0.16)
        ),
        ChartShortcut(
            region: "US", title: "英语榜", subtitle: "英语热门歌曲",
            systemImage: "star.fill", color: Color(red: 0.20, green: 0.36, blue: 0.72)
        ),
        ChartShortcut(
            region: "KR", title: "韩语榜", subtitle: "韩语热门歌曲",
            systemImage: "waveform", color: Color(red: 0.48, green: 0.24, blue: 0.67)
        ),
        ChartShortcut(
            region: "JP", title: "日语榜", subtitle: "日语热门歌曲",
            systemImage: "sparkles", color: Color(red: 0.12, green: 0.52, blue: 0.48)
        )
    ]

    private var username: String {
        session.currentUser?.username ?? "Sona"
    }

    private var historyTracks: [Track] {
        Array(sonaUniqueHistoryTracks(personal.history, library: library).prefix(12))
    }

    private var favoriteTracks: [Track] {
        if !personal.favoriteTracks.isEmpty || personal.favoriteIDs.isEmpty {
            return personal.favoriteTracks
        }
        return library.tracks.filter { personal.favoriteIDs.contains($0.id) }
    }

    private var likedSongsCollection: SonaCollection {
        SonaCollection(
            id: "liked-songs",
            title: "收藏的歌曲",
            subtitle: "歌单 · \(username)",
            artworkURL: sonaFirstArtworkURL(in: favoriteTracks),
            tracks: favoriteTracks,
            shape: .square
        )
    }

    private var playlistCollections: [SonaCollection] {
        personal.playlists.filter(\.shownOnHome).sorted {
            ($0.homePosition ?? Int.max) < ($1.homePosition ?? Int.max)
        }.map { playlist in
            let tracks = playlist.trackIDs.compactMap(library.track(id:))
            return SonaCollection(
                id: "playlist-\(playlist.id)",
                title: playlist.name,
                subtitle: playlist.isDirectoryPlaylist
                    ? "\(homePlaylistPoolTitle(playlist.poolType)) · Sona"
                    : playlist.featured ? "共享歌单 · Sona" : "歌单 · \(username)",
                artworkURL: sonaArtworkPaths(playlist.artworkURLs).first
                    ?? sonaFirstArtworkURL(in: tracks),
                artworkURLs: sonaArtworkPaths(playlist.artworkURLs),
                rotatesArtworkHourly: playlist.artworkTrackID == nil,
                tracks: tracks,
                shape: .square
            )
        }
    }

    private var recentCollections: [SonaCollection] {
        historyTracks.map { track in
            SonaCollection(
                id: "recent-\(track.id)",
                title: track.title,
                subtitle: track.artist,
                artworkURL: track.artworkURL,
                tracks: [track],
                shape: .square
            )
        }
    }

    private var orderedHomePlaylistCollections: [SonaCollection] {
        var values: [(position: Int, id: String, collection: SonaCollection)] = []
        if personal.favoritesShownOnHome {
            values.append((
                personal.favoritesHomePosition ?? Int.max,
                likedSongsCollection.id,
                likedSongsCollection
            ))
        }
        let collectionsByID = Dictionary(
            uniqueKeysWithValues: playlistCollections.map { ($0.id, $0) }
        )
        for playlist in personal.playlists where playlist.shownOnHome {
            let id = "playlist-\(playlist.id)"
            if let collection = collectionsByID[id] {
                values.append((playlist.homePosition ?? Int.max, id, collection))
            }
        }
        return values.sorted {
            ($0.position, $0.id) < ($1.position, $1.id)
        }.map(\.collection)
    }

    private var favoriteCollections: [SonaCollection] {
        let collections = favoriteTracks.prefix(12).map { track in
            SonaCollection(
                id: "favorite-\(track.id)",
                title: track.title,
                subtitle: track.artist,
                artworkURL: track.artworkURL,
                tracks: [track],
                shape: .square
            )
        }
        guard collections.count > 1 else { return collections }

        let offset = favoriteRotationOffset % collections.count
        return Array(collections[offset...]) + Array(collections[..<offset])
    }

    private var dailyCollection: SonaCollection {
        SonaCollection(
            id: "daily-recommendations",
            title: "今日推荐",
            subtitle: "每天为你更新",
            artworkURL: sonaFirstArtworkURL(in: dailyTracks),
            tracks: dailyTracks,
            shape: .square
        )
    }

    private var dailyCollections: [SonaCollection] {
        var groups = Array(repeating: [Track](), count: min(6, dailyTracks.count))
        for (index, track) in dailyTracks.prefix(180).enumerated() {
            groups[index % groups.count].append(track)
        }
        return groups.enumerated().map { index, tracks in
            SonaCollection(
                id: "daily-\(index)",
                title: "每日推荐 \(index + 1)",
                subtitle: dailyArtists(from: tracks),
                artworkURL: sonaFirstArtworkURL(in: tracks),
                tracks: tracks,
                shape: .square
            )
        }
    }

    private var personalizedSourceTracks: [Track] {
        var seen = Set<String>()
        return (dailyTracks + historyTracks + library.tracks).filter {
            seen.insert($0.id).inserted
        }
    }

    private var radioCollections: [SonaCollection] {
        let source = diverseTracks(
            excluding: Set(dailyTracks.map(\.id)),
            limit: 180
        )
        var seenArtists = Set<String>()
        let anchors = source.filter {
            let artist = $0.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            return !artist.isEmpty && seenArtists.insert(artist).inserted
        }.prefix(4)

        var assignedTrackIDs = Set<String>()
        return anchors.map { anchor in
            let related = uniqueTracks([anchor] + source.filter {
                $0.artist == anchor.artist ||
                    (anchor.genre != "未分类" && $0.genre == anchor.genre)
            } + source)
            let unused = related.filter { !assignedTrackIDs.contains($0.id) }
            let fallback = related.filter { assignedTrackIDs.contains($0.id) }
            let tracks = Array((unused + fallback).prefix(30))
            assignedTrackIDs.formUnion(tracks.map(\.id))
            return SonaCollection(
                id: "radio-\(anchor.id)",
                title: anchor.artist,
                subtitle: artistSummary(from: tracks, limit: 5),
                artworkURL: sonaFirstArtworkURL(in: tracks),
                artworkURLs: Array(sonaArtworkPaths(tracks.compactMap(\.artworkURL)).prefix(3)),
                tracks: tracks,
                shape: .square
            )
        }
    }

    private var madeForYouCollections: [SonaCollection] {
        madeForYouMixes.compactMap { mix in
            guard !mix.tracks.isEmpty else { return nil }
            return SonaCollection(
                id: mix.id,
                title: "\(mix.artist) 合辑",
                subtitle: artistSummary(from: mix.tracks, limit: 3),
                artworkURL: sonaFirstArtworkURL(in: mix.tracks),
                tracks: mix.tracks,
                shape: .square
            )
        }
    }

    private func artistSummary(from tracks: [Track], limit: Int) -> String {
        var values: [String] = []
        for track in tracks where !values.contains(track.artist) {
            values.append(track.artist)
        }
        return values.prefix(limit).joined(separator: "、")
    }

    private func dailyArtists(from tracks: [Track]) -> String {
        let artists = tracks.reduce(into: [String]()) { values, track in
            guard !values.contains(track.artist) else { return }
            values.append(track.artist)
        }
        let names = artists.prefix(3).joined(separator: "、")
        return artists.count > 3 ? "\(names) 等更多曲风" : names
    }

    private func uniqueTracks(_ tracks: [Track]) -> [Track] {
        var seen = Set<String>()
        return tracks.filter { seen.insert($0.id).inserted }
    }

    private func diverseTracks(excluding excludedIDs: Set<String>, limit: Int) -> [Track] {
        let preferred = personalizedSourceTracks.filter { !excludedIDs.contains($0.id) }
        let fallback = personalizedSourceTracks.filter { excludedIDs.contains($0.id) }
        return Array((preferred + fallback).prefix(limit))
    }

    private var albums: [SonaCollection] {
        Array(sonaAlbums(from: library.tracks).prefix(12))
    }

    private var artists: [SonaCollection] {
        Array(sonaArtists(from: historyTracks.isEmpty ? library.tracks : historyTracks).prefix(12))
    }

    private var shortcuts: [SonaCollection] {
        var values: [SonaCollection] = []
        values.append(contentsOf: orderedHomePlaylistCollections.prefix(3))
        values.append(contentsOf: recentCollections.prefix(max(0, 8 - values.count)))
        return Array(values.prefix(8))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.02, green: 0.20, blue: 0.10), .sonaBackground, .sonaBackground],
                    startPoint: .topLeading,
                    endPoint: .center
                )
                .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 30) {
                        VStack(spacing: 16) {
                            header
                            if selectedFilter != "音乐" {
                                shortcutGrid
                            }
                        }
                        if library.tracks.isEmpty && library.isLoading {
                            ProgressView("载入你的音乐…")
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
                        } else {
                            homeContent
                        }
                    }
                    .padding(.bottom, homeBottomPadding)
                }
                .refreshable {
                    await personal.refresh()
                    await loadRecommendations()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: childMode) { await loadRecommendations() }
            .task { await rotateFavorites() }
        }
    }

    private var homeBottomPadding: CGFloat {
#if targetEnvironment(macCatalyst)
        24
#else
        miniPlayerMode == "fixed" ? 92 : 24
#endif
    }

    private var header: some View {
        HStack(spacing: 12) {
            SonaAvatarButton(username: username, action: openDrawer)
            SonaFilterPill(title: "全部", isSelected: selectedFilter == "全部") {
                withAnimation(.easeInOut(duration: 0.2)) { selectedFilter = "全部" }
            }
            SonaFilterPill(title: "音乐", isSelected: selectedFilter == "音乐") {
                withAnimation(.easeInOut(duration: 0.2)) { selectedFilter = "音乐" }
            }
            SonaFilterPill(title: "歌单", isSelected: selectedFilter == "歌单") {
                withAnimation(.easeInOut(duration: 0.2)) { selectedFilter = "歌单" }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var homeContent: some View {
        if selectedFilter != "歌单" {
            mediaSection(
                title: "今日推荐",
                collections: dailyCollections,
                titleDestination: dailyCollection
            )
            recommendedRadioSection
            madeForYouSection
            recommendationNavigation
            mediaSection(title: "最近播放", collections: recentCollections)
        }

        if selectedFilter != "音乐" {
            if personal.favoritesShownOnHome {
                mediaSection(
                    title: "收藏的歌曲",
                    collections: favoriteCollections,
                    titleDestination: likedSongsCollection
                )
            }
            mediaSection(title: "歌单", collections: playlistCollections)
            onlinePlaylistPlaceholder
        }

        if selectedFilter != "歌单" {
            mediaSection(title: "浏览专辑", collections: albums)
            mediaSection(title: "常听艺人", collections: artists)
        }
    }

    private var onlinePlaylistPlaceholder: some View {
        VStack(alignment: .leading, spacing: 14) {
            SonaSectionHeader(title: "在线歌单")
                .padding(.horizontal, 16)
            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundStyle(Color.sonaGreen)
                    .frame(width: 52, height: 52)
                    .background(Color.sonaSurface, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text("即将支持在线歌单")
                        .font(.subheadline.weight(.semibold))
                    Text("配置在线音源后可在这里浏览")
                        .font(.caption)
                        .foregroundStyle(Color.sonaSecondaryText)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var shortcutGrid: some View {
        if !shortcuts.isEmpty {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(shortcuts) { collection in
                    SonaMacHoverShortcutCard {
                        playCollection(collection)
                    } content: {
                        NavigationLink {
                            SonaTrackListView(
                                collection: collection,
                                playbackQueue: playbackQueue(for: collection)
                            )
                        } label: {
                            HStack(spacing: 8) {
                                if collection.id == "liked-songs" {
                                    SonaLikedCover()
                                        .frame(width: 48, height: 48)
                                } else {
                                    ArtworkView(path: collection.artworkURL, cornerRadius: 5)
                                        .frame(width: 48, height: 48)
                                }
                                Text(collection.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 48)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var recommendationNavigation: some View {
        VStack(alignment: .leading, spacing: 14) {
            SonaSectionHeader(title: "为你发现")
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(chartShortcuts) { chart in
                        NavigationLink {
                            ChartsView(initialRegion: chart.region)
                        } label: {
                            recommendationTile(
                                title: chart.title,
                                subtitle: chart.subtitle,
                                systemImage: chart.systemImage,
                                color: chart.color
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(genres, id: \.self) { genre in
                        NavigationLink {
                            GenreRecommendationView(genre: genre)
                        } label: {
                            recommendationTile(
                                title: genre,
                                subtitle: "按曲风推荐",
                                systemImage: "music.note.list",
                                color: genreColor(genre)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private var recommendedRadioSection: some View {
        if !radioCollections.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SonaSectionHeader(title: "推荐电台")
                    .padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(Array(radioCollections.enumerated()), id: \.element.id) { index, collection in
                            SonaMacHoverMediaCard {
                                playCollection(collection)
                            } content: {
                                NavigationLink {
                                    SonaTrackListView(
                                        collection: collection,
                                        playbackQueue: collection.tracks,
                                        radioColor: radioColors[index % radioColors.count]
                                    )
                                } label: {
                                    HomeRadioCard(
                                        collection: collection,
                                        color: radioColors[index % radioColors.count]
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder
    private var madeForYouSection: some View {
        if !madeForYouCollections.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SonaSectionHeader(title: "为你打造")
                    .padding(.horizontal, 16)
                LazyVStack(spacing: 16) {
                    ForEach(Array(madeForYouCollections.enumerated()), id: \.element.id) { index, collection in
                        MadeForYouCard(
                            collection: collection,
                            colors: madeForYouColors[index % madeForYouColors.count]
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var radioColors: [Color] {
        [
            Color(red: 1.00, green: 0.58, blue: 0.43),
            Color(red: 0.49, green: 0.88, blue: 0.82),
            Color(red: 0.50, green: 0.91, blue: 0.63),
            Color(red: 0.72, green: 0.64, blue: 0.96)
        ]
    }

    private var madeForYouColors: [[Color]] {
        [
            [Color(red: 0.29, green: 0.08, blue: 0.53), Color(red: 0.19, green: 0.05, blue: 0.39)],
            [Color(red: 0.00, green: 0.33, blue: 0.32), Color(red: 0.00, green: 0.22, blue: 0.22)]
        ]
    }

    private func recommendationTile(
        title: String, subtitle: String, systemImage: String, color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2.bold())
            Spacer()
            Text(title).font(.headline).lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 180, height: 118, alignment: .leading)
        .background(color.gradient, in: RoundedRectangle(cornerRadius: 10))
    }

    private func genreColor(_ genre: String) -> Color {
        let colors: [Color] = [.indigo, .orange, .teal, .purple, .blue, .brown]
        let index = genre.utf8.reduce(0) { ($0 + Int($1)) % colors.count }
        return colors[index]
    }

    @ViewBuilder
    private func mediaSection(
        title: String,
        collections: [SonaCollection],
        titleDestination: SonaCollection? = nil
    ) -> some View {
        if !collections.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                if let titleDestination {
                    NavigationLink {
                        SonaTrackListView(collection: titleDestination)
                    } label: {
                        HStack {
                            SonaSectionHeader(title: title)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(Color.sonaSecondaryText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                } else {
                    SonaSectionHeader(title: title)
                        .padding(.horizontal, 16)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(collections) { collection in
                            SonaMacHoverMediaCard {
                                playCollection(collection)
                            } content: {
                                NavigationLink {
                                    SonaTrackListView(
                                        collection: collection,
                                        playbackQueue: playbackQueue(for: collection),
                                        dailyRecommendationQueues: collection.id.hasPrefix("daily-")
                                            ? dailyCollections.map(\.tracks) : nil
                                    )
                                } label: {
                                    SonaMediaCard(collection: collection)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func playCollection(_ collection: SonaCollection) {
        homePlaylistPlaybackTask?.cancel()
        if collection.id.hasPrefix("playlist-") {
            playHomePlaylist(collection)
            return
        }

        if collection.id.hasPrefix("daily-"),
           let first = collection.tracks.first,
           let queueIndex = Int(collection.id.dropFirst("daily-".count)) {
            player.playDailyRecommendations(
                track: first,
                queues: dailyCollections.map(\.tracks),
                queueIndex: queueIndex,
                offlineURLProvider: offline.localURL(for:)
            )
            return
        }

        startCollectionPlayback(
            collection,
            queue: playbackQueue(for: collection) ?? collection.tracks
        )
    }

    private func playHomePlaylist(_ collection: SonaCollection) {
        let playlistID = String(collection.id.dropFirst("playlist-".count))
        guard let playlist = personal.playlists.first(where: { $0.id == playlistID }) else {
            return
        }
        homePlaylistPlaybackTask = Task {
            let visibleIDs = playlist.trackIDs.filter {
                !personal.hiddenTrackIDs.contains($0)
            }
            let visibleIDSet = Set(visibleIDs)
            var tracksByID = Dictionary(
                uniqueKeysWithValues: collection.tracks
                    .filter { visibleIDSet.contains($0.id) }
                    .map { ($0.id, $0) }
            )
            loadedHomePlaylistTracks.forEach {
                if visibleIDSet.contains($0.key) {
                    tracksByID[$0.key] = $0.value
                }
            }
            let initiallyAvailable = visibleIDs.compactMap { tracksByID[$0] }
            let missingIDs = visibleIDs.filter { tracksByID[$0] == nil }
            if !initiallyAvailable.isEmpty {
                startCollectionPlayback(collection, queue: initiallyAvailable)
            }
            guard !missingIDs.isEmpty, !Task.isCancelled,
                  let loaded = try? await APIClient.shared.tracks(ids: missingIDs) else {
                return
            }
            guard !Task.isCancelled else { return }
            loaded.forEach {
                tracksByID[$0.id] = $0
                loadedHomePlaylistTracks[$0.id] = $0
            }
            let queue = playlist.trackIDs.compactMap { tracksByID[$0] }
            guard !queue.isEmpty else { return }
            startCollectionPlayback(collection, queue: queue)
        }
    }

    private func startCollectionPlayback(
        _ collection: SonaCollection,
        queue: [Track]
    ) {
        guard let first = queue.first else { return }
        player.play(
            track: first,
            queue: queue,
            prioritizedQueueTitle: collection.title,
            queueContextID: collection.id,
            offlineURLProvider: offline.localURL(for:)
        )
    }

    private func playbackQueue(for collection: SonaCollection) -> [Track]? {
        if collection.id == "daily-recommendations" {
            return dailyTracks
        }
        if collection.id.hasPrefix("daily-") { return collection.tracks }
        if collection.id.hasPrefix("recent-") {
            return historyTracks.count > 1 ? historyTracks : library.tracks
        }
        if collection.id.hasPrefix("favorite-") || collection.id == "liked-songs" {
            return favoriteTracks.count > 1 ? favoriteTracks : library.tracks
        }
        return collection.tracks.count == 1 ? library.tracks : nil
    }

    private func loadRecommendations() async {
        async let loadedDaily = APIClient.shared.dailyRecommendations()
        async let loadedGenres = APIClient.shared.recommendationGenres()
        async let loadedMadeForYou = APIClient.shared.madeForYouRecommendations()
        do {
            let (daily, loadedGenreValues) = try await (loadedDaily, loadedGenres)
            dailyTracks = uniqueTracks(daily)
            genres = loadedGenreValues
        } catch {
            dailyTracks = []
            genres = []
        }
        do {
            madeForYouMixes = try await loadedMadeForYou
        } catch {
            madeForYouMixes = []
        }
    }

    private func rotateFavorites() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: favoriteRotationInterval)
            } catch {
                return
            }

            let count = min(favoriteTracks.count, 12)
            guard count > 1 else { continue }
            withAnimation(.easeInOut(duration: 0.5)) {
                favoriteRotationOffset = (favoriteRotationOffset + 1) % count
            }
        }
    }

}

private func homePlaylistPoolTitle(_ poolType: String) -> String {
    switch poolType {
    case "DISCOVERY": "发现歌曲池"
    case "CHILD": "儿童歌池"
    default: "正常歌曲池"
    }
}

private struct HomeRadioCard: View {
    let collection: SonaCollection
    let color: Color

    private let cardWidth: CGFloat = 168

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SonaRadioCover(collection: collection, color: color, size: cardWidth)

            Text(collection.subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.sonaSecondaryText)
                .lineLimit(2)
                .frame(width: cardWidth, alignment: .leading)
        }
    }
}

private struct MadeForYouCard: View {
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @State private var isQueued = false
    let collection: SonaCollection
    let colors: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                NavigationLink {
                    SonaTrackListView(
                        collection: collection,
                        playbackQueue: collection.tracks
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .top, spacing: 12) {
                            artwork
                            VStack(alignment: .leading, spacing: 5) {
                                Text(collection.title)
                                    .font(.title3.weight(.bold))
                                    .lineLimit(2)
                                Text("Sona")
                                    .font(.body)
                                    .foregroundStyle(.white.opacity(0.92))
                            }
                            .padding(.top, 4)
                            Spacer(minLength: 40)
                        }

                        Text("\(collection.tracks.count) 首歌曲 · \(collection.subtitle)")
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.76))
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    Button("播放歌单", systemImage: "play.fill") { play(shuffled: false) }
                    Button("加入播放队列", systemImage: "text.badge.plus") { addToQueue() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.bold())
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                }
            }

            HStack(spacing: 14) {
                Button { play(shuffled: true) } label: {
                    Label("试听歌单", systemImage: "speaker.wave.2.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .frame(height: 36)
                        .background(.black.opacity(0.38), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Button { addToQueue() } label: {
                    Image(systemName: isQueued ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("加入播放队列")

                Button { play(shuffled: false) } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 36, height: 36)
                        .background(.white, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("播放歌单")
            }
        }
        .padding(12)
        .frame(height: 184)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private var artwork: some View {
        ArtworkView(path: collection.artworkURL, cornerRadius: 5, thumbnailSize: 512)
            .frame(width: 88, height: 88)
            .overlay(alignment: .topLeading) {
                Image(systemName: "waveform.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(Color.sonaGreen)
                    .padding(7)
            }
            .overlay(alignment: .bottom) {
                Text(collection.title)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .background(Color.sonaGreen.opacity(0.94))
            }
            .clipped()
    }

    private func play(shuffled: Bool) {
        let queue = shuffled ? collection.tracks.shuffled() : collection.tracks
        guard let first = queue.first else { return }
        player.play(
            track: first,
            queue: queue,
            prioritizedQueueTitle: collection.title,
            queueContextID: collection.id,
            offlineURLProvider: offline.localURL(for:)
        )
    }

    private func addToQueue() {
        collection.tracks.forEach(player.addToQueue)
        withAnimation(.easeInOut(duration: 0.2)) { isQueued = true }
    }
}

private struct GenreRecommendationView: View {
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var personal: PersonalStore
    @State private var tracks: [Track] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    let genre: String

    var body: some View {
        Group {
            if isLoading && tracks.isEmpty {
                ProgressView("正在生成推荐…")
            } else if tracks.isEmpty {
                ContentUnavailableView(
                    "暂无\(genre)歌曲",
                    systemImage: "music.note.list",
                    description: Text(errorMessage ?? "管理员标注曲风后会显示在这里。")
                )
                .desktopEmptyState()
            } else {
                List(tracks) { track in
                    Button { play(track) } label: {
                        TrackRow(track: track, isFavorite: personal.favoriteIDs.contains(track.id))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.sonaBackground)
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sonaBackground)
        .navigationTitle(genre)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("播放全部", systemImage: "play.fill") {
                    if let first = tracks.first { play(first) }
                }
                .disabled(tracks.isEmpty)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tracks = try await APIClient.shared.recommendations(genre: genre)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func play(_ track: Track) {
        player.play(
            track: track,
            queue: tracks,
            prioritizedQueueTitle: "\(genre)推荐",
            offlineURLProvider: offline.localURL(for:)
        )
    }
}

private struct ChartsView: View {
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var personal: PersonalStore
    @State private var region = "ALL"
    @State private var entries: [ChartEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let regions = [
        ("ALL", "总榜"), ("CN", "中文"), ("US", "英语"), ("KR", "韩语"), ("JP", "日语")
    ]

    init(initialRegion: String = "ALL") {
        _region = State(initialValue: initialRegion)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("榜单", selection: $region) {
                ForEach(regions, id: \.0) { value, title in
                    Text(title).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            if isLoading && entries.isEmpty {
                Spacer()
                ProgressView("正在载入榜单…")
                Spacer()
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "暂无榜单数据",
                    systemImage: "chart.bar",
                    description: Text(errorMessage ?? "歌曲产生有效播放后会在这里排行。")
                )
                .desktopEmptyState()
            } else {
                List(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    Button { play(entry.track) } label: {
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.title3.bold())
                                .foregroundStyle(index < 3 ? Color.sonaGreen : Color.sonaSecondaryText)
                                .frame(width: 24)
                            TrackRow(
                                track: entry.track,
                                isFavorite: personal.favoriteIDs.contains(entry.track.id)
                            )
                            Text("\(entry.playCount) 次")
                                .font(.caption)
                                .foregroundStyle(Color.sonaSecondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.sonaBackground)
                }
                .listStyle(.plain)
            }
        }
        .background(Color.sonaBackground)
        .navigationTitle("播放榜单")
        .onChange(of: region) { _, _ in Task { await load() } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await APIClient.shared.chart(region: region)
            errorMessage = nil
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }
    }

    private func play(_ track: Track) {
        player.play(
            track: track,
            queue: entries.map(\.track),
            prioritizedQueueTitle: regions.first { $0.0 == region }?.1,
            offlineURLProvider: offline.localURL(for:)
        )
    }
}

private struct ChartShortcut: Identifiable {
    let region: String
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color

    var id: String { region }
}
