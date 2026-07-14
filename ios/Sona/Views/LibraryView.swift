import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var personal: PersonalStore
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
                        .contextMenu {
                            Button {
                                Task { await personal.toggleFavorite(trackID: track.id) }
                            } label: {
                                Label(
                                    personal.favoriteIDs.contains(track.id) ? "取消收藏" : "收藏",
                                    systemImage: personal.favoriteIDs.contains(track.id) ? "heart.slash" : "heart"
                                )
                            }
                            if personal.playlists.isEmpty {
                                Text("请先创建歌单")
                            } else {
                                Menu("添加到歌单", systemImage: "text.badge.plus") {
                                    ForEach(personal.playlists) { playlist in
                                        Button(playlist.name) {
                                            Task {
                                                await personal.setTrack(
                                                    track.id,
                                                    in: playlist.id,
                                                    isIncluded: true
                                                )
                                            }
                                        }
                                    }
                                }
                            }
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
                    Text(library.isLoading ? "已载入 \(library.tracks.count) 首…" : "\(library.tracks.count) 首")
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
