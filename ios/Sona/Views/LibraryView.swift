import SwiftData
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if library.tracks.isEmpty && library.isLoading {
                    ProgressView("载入曲库…")
                } else if library.tracks.isEmpty {
                    ContentUnavailableView(
                        "曲库为空",
                        systemImage: "music.note.house",
                        description: Text("在设置中扫描服务器音乐目录")
                    )
                } else {
                    List(library.tracks) { track in
                        TrackRow(
                            track: track,
                            showsOfflineBadge: offline.downloadedIDs.contains(track.id)
                        )
                        .onTapGesture {
                            player.play(track: track, offlineURL: offline.localURL(for: track))
                        }
                        .contextMenu {
                            if playlists.isEmpty {
                                Text("请先创建歌单")
                            } else {
                                Menu("添加到歌单", systemImage: "text.badge.plus") {
                                    ForEach(playlists) { playlist in
                                        Button(playlist.name) { playlist.add(trackID: track.id) }
                                    }
                                }
                            }
                        }
                        .task {
                            await library.loadNextPageIfNeeded(after: track)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await library.refresh(query: query) }
                }
            }
            .navigationTitle("你的曲库")
            .searchable(text: $query, prompt: "歌曲、艺人或专辑")
            .onSubmit(of: .search) {
                Task { await library.refresh(query: query) }
            }
            .onChange(of: query) { _, value in
                if value.isEmpty {
                    Task { await library.refresh() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(library.tracks.count) 首")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .overlay(alignment: .bottom) {
                if let message = library.errorMessage {
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
