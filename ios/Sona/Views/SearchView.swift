import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var personal: PersonalStore
    @State private var query = ""
    let openDrawer: () -> Void

    private struct Category: Identifiable {
        let id: String
        let title: String
        let color: Color
        let tracks: [Track]
    }

    private var username: String {
        session.currentUser?.username ?? "Sona"
    }

    private var filteredTracks: [Track] {
        library.searchResults
    }

    private var categories: [Category] {
        let losslessCodecs = Set(["FLAC", "ALAC", "WAV", "AIFF", "APE"])
        let values = [
            Category(
                id: "lossless",
                title: "无损音乐",
                color: Color(red: 0.82, green: 0.08, blue: 0.48),
                tracks: library.tracks.filter { losslessCodecs.contains($0.codec.uppercased()) }
            ),
            Category(
                id: "lyrics",
                title: "带歌词",
                color: Color(red: 0.02, green: 0.45, blue: 0.36),
                tracks: library.tracks.filter(\.hasLyrics)
            ),
            Category(
                id: "offline",
                title: "离线音乐",
                color: Color(red: 0.45, green: 0.04, blue: 0.90),
                tracks: library.tracks.filter { offline.downloadedIDs.contains($0.id) }
            ),
            Category(
                id: "favorites",
                title: "收藏歌曲",
                color: Color(red: 0.55, green: 0.38, blue: 0.70),
                tracks: personal.favoriteTracks.isEmpty && !personal.favoriteIDs.isEmpty
                    ? library.tracks.filter { personal.favoriteIDs.contains($0.id) }
                    : personal.favoriteTracks
            ),
            Category(
                id: "albums",
                title: "完整专辑",
                color: Color(red: 0.03, green: 0.35, blue: 0.30),
                tracks: library.tracks
            ),
            Category(
                id: "all",
                title: "全部音乐",
                color: Color(red: 0.30, green: 0.42, blue: 0.03),
                tracks: library.tracks
            )
        ]
        return values.filter { !$0.tracks.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sonaBackground.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        header
                        searchField
                        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            discoveryContent
                        } else {
                            resultsContent
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: query) {
            let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                library.clearSearch()
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            await library.search(query: value)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            SonaAvatarButton(username: username, action: openDrawer)
            Text("搜索")
                .font(.system(size: 31, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .semibold))
            TextField("想听什么？", text: $query)
                .font(.system(size: 17, weight: .medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.black.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(.white, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
    }

    private var discoveryContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !categories.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    SonaSectionHeader(title: "发现新内容")
                        .padding(.horizontal, 16)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 14) {
                            ForEach(Array(categories.prefix(4))) { category in
                                NavigationLink {
                                    SonaTrackListView(
                                        collection: collection(for: category),
                                        loadsMoreFromLibrary: category.id == "all"
                                    )
                                } label: {
                                    discoveryCard(category)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    SonaSectionHeader(title: "浏览全部")
                        .padding(.horizontal, 16)
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(categories) { category in
                            NavigationLink {
                                SonaTrackListView(
                                    collection: collection(for: category),
                                    loadsMoreFromLibrary: category.id == "all"
                                )
                            } label: {
                                categoryCard(category)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        if library.isSearching && filteredTracks.isEmpty {
            ProgressView("搜索中…")
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        } else if filteredTracks.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 38))
                Text("没有找到“\(query)”")
                    .font(.headline)
                Text("试试歌曲、艺人或专辑名称")
                    .font(.subheadline)
                    .foregroundStyle(Color.sonaSecondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("歌曲")
                    .font(.title2.bold())
                    .padding(.horizontal, 16)
                ForEach(filteredTracks) { track in
                    Button {
                        player.play(
                            track: track,
                            queue: filteredTracks,
                            offlineURLProvider: offline.localURL(for:)
                        )
                    } label: {
                        TrackRow(
                            track: track,
                            showsOfflineBadge: offline.downloadedIDs.contains(track.id),
                            isFavorite: personal.favoriteIDs.contains(track.id)
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .task {
                        await library.loadNextSearchPageIfNeeded(currentTrack: track)
                    }
                }
                if library.isLoadingMoreSearch {
                    ProgressView("载入更多…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
            }
        }
    }

    private func discoveryCard(_ category: Category) -> some View {
        ZStack(alignment: .bottomLeading) {
            category.color
            if let artworkURL = category.tracks.first?.artworkURL {
                ArtworkView(path: artworkURL, cornerRadius: 6)
                    .frame(width: 138, height: 138)
                    .opacity(0.72)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
            Text("#\(category.title)")
                .font(.headline.bold())
                .foregroundStyle(.white)
                .padding(12)
        }
        .frame(width: 158, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func categoryCard(_ category: Category) -> some View {
        ZStack(alignment: .topLeading) {
            category.color
            Text(category.title)
                .font(.headline.bold())
                .foregroundStyle(.white)
                .padding(12)
                .zIndex(1)
            if let artworkURL = category.tracks.first?.artworkURL {
                ArtworkView(path: artworkURL, cornerRadius: 5)
                    .frame(width: 78, height: 78)
                    .rotationEffect(.degrees(24))
                    .offset(x: 112, y: 46)
                    .shadow(color: .black.opacity(0.3), radius: 6)
            }
        }
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func collection(for category: Category) -> SonaCollection {
        SonaCollection(
            id: category.id == "favorites" ? "liked-songs" : "category-\(category.id)",
            title: category.title,
            subtitle: "Sona · \(category.tracks.count) 首歌曲",
            artworkURL: category.tracks.first?.artworkURL,
            tracks: category.tracks,
            shape: .square
        )
    }
}
