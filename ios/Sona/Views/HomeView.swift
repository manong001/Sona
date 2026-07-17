import SwiftUI

private let favoriteRotationInterval: Duration = .seconds(5)
private let playlistShuffleInterval: TimeInterval = 30 * 60

private func playlistShufflePeriod(at date: Date) -> Int64 {
    Int64(date.timeIntervalSince1970 / playlistShuffleInterval)
}

private func playlistShuffleKey(id: String, period: Int64) -> UInt64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in id.utf8 {
        hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
    }

    var value = hash ^ UInt64(bitPattern: period)
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
}

struct HomeView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var personal: PersonalStore
    @State private var selectedFilter = "全部"
    @State private var dailyTracks: [Track] = []
    @State private var genres: [String] = []
    @State private var favoriteRotationOffset = 0
    @State private var playlistOrderPeriod = playlistShufflePeriod(at: .now)
    @AppStorage("childMode") private var childMode = false
    let openDrawer: () -> Void

    private let chartShortcuts = [
        ChartShortcut(
            region: "ALL", title: "热歌总榜", subtitle: "全站播放热度",
            systemImage: "flame.fill", color: Color(red: 0.72, green: 0.19, blue: 0.26)
        ),
        ChartShortcut(
            region: "CN", title: "华语榜", subtitle: "华语热门歌曲",
            systemImage: "music.mic", color: Color(red: 0.74, green: 0.29, blue: 0.16)
        ),
        ChartShortcut(
            region: "US", title: "美国榜", subtitle: "美国热门歌曲",
            systemImage: "star.fill", color: Color(red: 0.20, green: 0.36, blue: 0.72)
        ),
        ChartShortcut(
            region: "KR", title: "韩国榜", subtitle: "韩国热门歌曲",
            systemImage: "waveform", color: Color(red: 0.48, green: 0.24, blue: 0.67)
        ),
        ChartShortcut(
            region: "JP", title: "日本榜", subtitle: "日本热门歌曲",
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
            artworkURL: favoriteTracks.first?.artworkURL,
            tracks: favoriteTracks,
            shape: .square
        )
    }

    private var playlistCollections: [SonaCollection] {
        personal.playlists.map { playlist in
            let tracks = playlist.trackIDs.compactMap(library.track(id:))
            return SonaCollection(
                id: "playlist-\(playlist.id)",
                title: playlist.name,
                subtitle: playlist.isDirectoryPlaylist
                    ? "\(playlist.poolType == "DISCOVERY" ? "发现歌曲池" : "正常歌曲池") · Sona"
                    : playlist.featured ? "共享歌单 · Sona" : "歌单 · \(username)",
                artworkURL: playlist.artworkURLs.first,
                artworkURLs: playlist.artworkURLs,
                rotatesArtworkHourly: true,
                tracks: tracks,
                shape: .square
            )
        }
    }

    private var shuffledPlaylistCollections: [SonaCollection] {
        playlistCollections.sorted { lhs, rhs in
            let lhsKey = playlistShuffleKey(id: lhs.id, period: playlistOrderPeriod)
            let rhsKey = playlistShuffleKey(id: rhs.id, period: playlistOrderPeriod)
            return lhsKey == rhsKey ? lhs.id < rhs.id : lhsKey < rhsKey
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
            artworkURL: dailyTracks.first(where: { $0.artworkURL != nil })?.artworkURL,
            artworkURLs: Array(dailyTracks.compactMap(\.artworkURL).prefix(4)),
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
                artworkURL: tracks.first(where: { $0.artworkURL != nil })?.artworkURL,
                artworkURLs: Array(tracks.compactMap(\.artworkURL).prefix(4)),
                tracks: tracks,
                shape: .square
            )
        }
    }

    private func dailyArtists(from tracks: [Track]) -> String {
        let artists = tracks.reduce(into: [String]()) { values, track in
            guard !values.contains(track.artist) else { return }
            values.append(track.artist)
        }
        let names = artists.prefix(3).joined(separator: "、")
        return artists.count > 3 ? "\(names) 等更多曲风" : names
    }

    private var albums: [SonaCollection] {
        Array(sonaAlbums(from: library.tracks).prefix(12))
    }

    private var artists: [SonaCollection] {
        Array(sonaArtists(from: historyTracks.isEmpty ? library.tracks : historyTracks).prefix(12))
    }

    private var shortcuts: [SonaCollection] {
        var values: [SonaCollection] = []
        if !favoriteTracks.isEmpty {
            values.append(likedSongsCollection)
        }
        values.append(contentsOf: playlistCollections.prefix(3))
        values.append(contentsOf: recentCollections.prefix(max(0, 6 - values.count)))
        return Array(values.prefix(6))
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
                        header
                        if library.tracks.isEmpty && library.isLoading {
                            ProgressView("载入你的音乐…")
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
                        } else {
                            homeContent
                        }
                    }
                    .padding(.bottom, 24)
                }
                .refreshable {
                    await personal.refresh()
                    await loadRecommendations()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: childMode) { await loadRecommendations() }
            .task { await rotateFavorites() }
            .task { await refreshPlaylistOrderAtBoundaries() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
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
        if selectedFilter != "音乐" {
            shortcutGrid
        }

        if selectedFilter != "歌单" {
            mediaSection(
                title: "今日推荐",
                collections: dailyCollections,
                titleDestination: dailyCollection
            )
            recommendationNavigation
            mediaSection(title: "最近播放", collections: recentCollections)
        }

        if selectedFilter != "音乐" {
            mediaSection(
                title: "收藏的歌曲",
                collections: favoriteCollections,
                titleDestination: likedSongsCollection
            )
            mediaSection(title: "歌单", collections: shuffledPlaylistCollections)
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
                    NavigationLink {
                        SonaTrackListView(
                            collection: collection,
                            playbackQueue: playbackQueue(for: collection)
                        )
                    } label: {
                        HStack(spacing: 10) {
                            if collection.id == "liked-songs" {
                                SonaLikedCover()
                                    .frame(width: 62, height: 62)
                            } else {
                                ArtworkView(path: collection.artworkURL, cornerRadius: 5)
                                    .frame(width: 62, height: 62)
                            }
                            Text(collection.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 62)
                        .background(Color.sonaSurface.opacity(0.95), in: RoundedRectangle(cornerRadius: 6))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
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
                    .padding(.horizontal, 16)
                }
            }
        }
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
        do {
            async let loadedDaily = APIClient.shared.dailyRecommendations()
            async let loadedGenres = APIClient.shared.recommendationGenres()
            dailyTracks = try await loadedDaily
            genres = try await loadedGenres
        } catch {
            dailyTracks = []
            genres = []
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

    private func refreshPlaylistOrderAtBoundaries() async {
        while !Task.isCancelled {
            let now = Date()
            let currentPeriod = playlistShufflePeriod(at: now)
            playlistOrderPeriod = currentPeriod

            let nextBoundary = Date(
                timeIntervalSince1970: TimeInterval(currentPeriod + 1) * playlistShuffleInterval
            )
            let nanoseconds = UInt64(
                max(0.1, nextBoundary.timeIntervalSinceNow) * 1_000_000_000
            )
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
        }
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
        ("ALL", "总榜"), ("CN", "华语"), ("US", "美国"), ("KR", "韩国"), ("JP", "日本")
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
