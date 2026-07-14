import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var player: PlayerStore
    let open: () -> Void

    var body: some View {
        if let track = player.currentTrack {
            Button(action: open) {
                VStack(spacing: 0) {
                    ProgressView(
                        value: player.elapsed,
                        total: max(player.duration, 1)
                    )
                    .progressViewStyle(.linear)
                    HStack(spacing: 10) {
                        ArtworkView(path: track.artworkURL, cornerRadius: 4)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            player.togglePlayback()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .background(.ultraThinMaterial)
            }
            .buttonStyle(.plain)
        }
    }
}
