import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var personal: PersonalStore
    @State private var selectedFilter = "全部"
    @State private var dailyTracks: [Track] = []
    @State private var genres: [String] = []
    @AppStorage("childMode") private var childMode = false
    let openDrawer: () -> Void

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
                subtitle: "歌单 · \(username)",
                artworkURL: tracks.first(where: { $0.artworkURL != nil })?.artworkURL,
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

    private var favoriteCollections: [SonaCollection] {
        favoriteTracks.prefix(12).map { track in
            SonaCollection(
                id: "favorite-\(track.id)",
                title: track.title,
                subtitle: track.artist,
                artworkURL: track.artworkURL,
                tracks: [track],
                shape: .square
            )
        }
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
        for (index, track) in dailyTracks.prefix(60).enumerated() {
            groups[index % groups.count].append(track)
        }
        return groups.enumerated().map { index, tracks in
            SonaCollection(
                id: "daily-\(index)",
                title: "每日推荐 \(index + 1)",
                subtitle: "每日凌晨更新 · \(tracks.count) 首",
                artworkURL: tracks.first(where: { $0.artworkURL != nil })?.artworkURL,
                artworkURLs: Array(tracks.compactMap(\.artworkURL).prefix(4)),
                tracks: tracks,
                shape: .square
            )
        }
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
            mediaSection(title: "你的歌单", collections: playlistCollections)
        }

        if selectedFilter != "歌单" {
            mediaSection(title: "浏览专辑", collections: albums)
            mediaSection(title: "常听艺人", collections: artists)
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
                    NavigationLink {
                        ChartsView()
                    } label: {
                        recommendationTile(
                            title: "排行榜",
                            subtitle: "总榜 · 韩榜 · 国榜 · 美榜 · 日榜",
                            systemImage: "chart.bar.fill",
                            color: Color(red: 0.72, green: 0.19, blue: 0.26)
                        )
                    }
                    .buttonStyle(.plain)

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
        ("ALL", "总榜"), ("KR", "韩榜"), ("CN", "国榜"), ("US", "美榜"), ("JP", "日榜")
    ]

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
