import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject private var personal: PersonalStore
    @State private var showsCreatePlaylist = false
    @State private var playlistName = ""

    var body: some View {
        NavigationStack {
            Group {
                if personal.playlists.isEmpty && personal.isLoading {
                    ProgressView("载入歌单…")
                } else if personal.playlists.isEmpty {
                    ContentUnavailableView(
                        "还没有歌单",
                        systemImage: "rectangle.stack.badge.plus",
                        description: Text("创建歌单后，在曲目菜单中添加歌曲")
                    )
                } else {
                    List {
                        ForEach(personal.playlists) { playlist in
                            NavigationLink {
                                PlaylistDetailView(playlistID: playlist.id)
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "music.note.list")
                                        .font(.title2)
                                        .foregroundStyle(Color.sonaGreen)
                                        .frame(width: 54, height: 54)
                                        .background(Color.sonaSurface, in: RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading) {
                                        Text(playlist.name).fontWeight(.semibold)
                                        Text("\(playlist.trackIDs.count) 首歌曲")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { indexes in
                            for index in indexes {
                                let id = personal.playlists[index].id
                                Task { await personal.deletePlaylist(id: id) }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await personal.refresh() }
                }
            }
            .navigationTitle("歌单")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("新建", systemImage: "plus") {
                        playlistName = ""
                        showsCreatePlaylist = true
                    }
                }
            }
            .alert("新建歌单", isPresented: $showsCreatePlaylist) {
                TextField("歌单名称", text: $playlistName)
                Button("取消", role: .cancel) { }
                Button("创建") {
                    let name = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        Task { await personal.createPlaylist(name: name) }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let message = personal.errorMessage {
                    Text(message)
                        .font(.caption)
                        .padding(10)
                        .background(.red.opacity(0.9), in: Capsule())
                        .padding()
                }
            }
        }
    }
}

private struct PlaylistDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var personal: PersonalStore
    let playlistID: String

    private var playlist: Playlist? {
        personal.playlists.first { $0.id == playlistID }
    }

    private var tracks: [Track] {
        playlist?.trackIDs.compactMap(library.track(id:)) ?? []
    }

    var body: some View {
        Group {
            if tracks.isEmpty {
                ContentUnavailableView(
                    "歌单为空",
                    systemImage: "music.note",
                    description: Text("从曲库的曲目菜单添加歌曲")
                )
            } else {
                List(tracks) { track in
                    TrackRow(
                        track: track,
                        showsOfflineBadge: offline.downloadedIDs.contains(track.id),
                        isFavorite: personal.favoriteIDs.contains(track.id)
                    )
                    .onTapGesture {
                        player.play(
                            track: track,
                            queue: tracks,
                            prioritizedQueueTitle: playlist?.name ?? "歌单",
                            offlineURLProvider: offline.localURL(for:)
                        )
                    }
                    .swipeActions {
                        Button("移除", role: .destructive) {
                            Task {
                                await personal.setTrack(
                                    track.id,
                                    in: playlistID,
                                    isIncluded: false
                                )
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(playlist?.name ?? "歌单")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct PersonalView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var personal: PersonalStore

    private var favoriteTracks: [Track] {
        library.tracks.filter { personal.favoriteIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("收藏的歌曲") {
                    if favoriteTracks.isEmpty {
                        Text("长按曲库中的歌曲即可收藏")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(favoriteTracks) { track in
                            TrackRow(
                                track: track,
                                showsOfflineBadge: offline.downloadedIDs.contains(track.id),
                                isFavorite: true
                            )
                            .onTapGesture {
                                player.play(
                                    track: track,
                                    queue: favoriteTracks,
                                    prioritizedQueueTitle: "收藏的歌曲",
                                    offlineURLProvider: offline.localURL(for:)
                                )
                            }
                            .swipeActions {
                                Button("取消收藏", role: .destructive) {
                                    Task { await personal.toggleFavorite(trackID: track.id) }
                                }
                            }
                        }
                    }
                }

                Section("最近播放") {
                    if personal.history.isEmpty {
                        Text("播放歌曲后会出现在这里")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(personal.history) { item in
                            if let track = library.track(id: item.trackID) {
                                TrackRow(
                                    track: track,
                                    showsOfflineBadge: offline.downloadedIDs.contains(track.id),
                                    isFavorite: personal.favoriteIDs.contains(track.id)
                                )
                                .onTapGesture {
                                    player.play(
                                        track: track,
                                        queue: library.tracks,
                                        offlineURLProvider: offline.localURL(for:)
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("我的")
            .refreshable { await personal.refresh() }
        }
    }
}
