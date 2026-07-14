import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var personal: PersonalStore
    @State private var selectedFilter = "全部"
    let openDrawer: () -> Void

    private var username: String {
        session.currentUser?.username ?? "Sona"
    }

    private var historyTracks: [Track] {
        Array(sonaUniqueHistoryTracks(personal.history, library: library).prefix(12))
    }

    private var favoriteTracks: [Track] {
        library.tracks.filter { personal.favoriteIDs.contains($0.id) }
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

    private var albums: [SonaCollection] {
        Array(sonaAlbums(from: library.tracks).prefix(12))
    }

    private var artists: [SonaCollection] {
        Array(sonaArtists(from: historyTracks.isEmpty ? library.tracks : historyTracks).prefix(12))
    }

    private var shortcuts: [SonaCollection] {
        var values: [SonaCollection] = []
        if !favoriteTracks.isEmpty {
            values.append(SonaCollection(
                id: "liked-songs",
                title: "收藏的歌曲",
                subtitle: "歌单 · \(username)",
                artworkURL: favoriteTracks.first?.artworkURL,
                tracks: favoriteTracks,
                shape: .square
            ))
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
                            shortcutGrid
                            mediaSection(title: "最近播放", collections: recentCollections)
                            mediaSection(title: "收藏的歌曲", collections: favoriteCollections)
                            mediaSection(title: "你的歌单", collections: playlistCollections)
                            mediaSection(title: "浏览专辑", collections: albums)
                            mediaSection(title: "常听艺人", collections: artists)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .refreshable { await personal.refresh() }
            }
            .toolbar(.hidden, for: .navigationBar)
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
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
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

    @ViewBuilder
    private func mediaSection(title: String, collections: [SonaCollection]) -> some View {
        if !collections.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SonaSectionHeader(title: title)
                    .padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(collections) { collection in
                            NavigationLink {
                                SonaTrackListView(
                                    collection: collection,
                                    playbackQueue: playbackQueue(for: collection)
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
        if collection.id.hasPrefix("recent-") {
            return historyTracks.count > 1 ? historyTracks : library.tracks
        }
        if collection.id.hasPrefix("favorite-") || collection.id == "liked-songs" {
            return favoriteTracks.count > 1 ? favoriteTracks : library.tracks
        }
        return collection.tracks.count == 1 ? library.tracks : nil
    }
}
