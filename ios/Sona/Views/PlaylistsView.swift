import SwiftData
import SwiftUI

struct PlaylistsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]
    @State private var showsCreatePlaylist = false
    @State private var playlistName = ""

    var body: some View {
        NavigationStack {
            Group {
                if playlists.isEmpty {
                    ContentUnavailableView(
                        "还没有歌单",
                        systemImage: "rectangle.stack.badge.plus",
                        description: Text("创建歌单后，在曲目菜单中添加歌曲")
                    )
                } else {
                    List {
                        ForEach(playlists) { playlist in
                            NavigationLink {
                                PlaylistDetailView(playlist: playlist)
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
                                modelContext.delete(playlists[index])
                            }
                        }
                    }
                    .listStyle(.plain)
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
                        modelContext.insert(Playlist(name: name))
                    }
                }
            }
        }
    }
}

private struct PlaylistDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    let playlist: Playlist

    private var tracks: [Track] {
        playlist.trackIDs.compactMap(library.track(id:))
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
                        showsOfflineBadge: offline.downloadedIDs.contains(track.id)
                    )
                    .onTapGesture {
                        player.play(track: track, offlineURL: offline.localURL(for: track))
                    }
                    .swipeActions {
                        Button("移除", role: .destructive) {
                            playlist.remove(trackID: track.id)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.large)
    }
}
