import SwiftUI

struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @State private var showsLyrics = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [.sonaSurface, .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if let track = player.currentTrack {
                    VStack(spacing: 24) {
                        Spacer(minLength: 10)
                        ArtworkView(path: track.artworkURL, cornerRadius: 14)
                            .aspectRatio(1, contentMode: .fit)
                            .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(track.title)
                                .font(.title2.bold())
                                .lineLimit(1)
                            Text("\(track.artist) · \(track.album)")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(track.qualityText)
                                .font(.caption)
                                .foregroundStyle(Color.sonaGreen)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { player.elapsed },
                                    set: { player.seek(to: $0) }
                                ),
                                in: 0...max(player.duration, 1)
                            )
                            HStack {
                                Text(time(player.elapsed))
                                Spacer()
                                Text("-" + time(max(0, player.duration - player.elapsed)))
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 42) {
                            Button {
                                toggleOffline(track)
                            } label: {
                                Group {
                                    if offline.activeDownloads.contains(track.id) {
                                        ProgressView()
                                    } else {
                                        Image(systemName: offline.downloadedIDs.contains(track.id)
                                            ? "arrow.down.circle.fill"
                                            : "arrow.down.circle")
                                    }
                                }
                                .font(.title2)
                            }
                            Button {
                                player.togglePlayback()
                            } label: {
                                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 70))
                            }
                            Button {
                                showsLyrics = true
                            } label: {
                                Image(systemName: "quote.bubble")
                                    .font(.title2)
                            }
                            .disabled(!track.hasLyrics)
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 28)
                }
            }
            .navigationTitle("正在播放")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭", systemImage: "chevron.down") { dismiss() }
                }
            }
            .sheet(isPresented: $showsLyrics) {
                if let track = player.currentTrack {
                    LyricsView(track: track)
                }
            }
        }
    }

    private func toggleOffline(_ track: Track) {
        if offline.downloadedIDs.contains(track.id) {
            offline.remove(track)
        } else {
            Task { await offline.download(track) }
        }
    }

    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let value = max(0, Int(seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
