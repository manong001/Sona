import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var player: PlayerStore
    let open: () -> Void

    var body: some View {
        if let track = player.currentTrack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button(action: open) {
                        HStack(spacing: 10) {
                            ArtworkView(path: track.artworkURL, cornerRadius: 5)
                                .frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text("\(track.artist) · \(track.qualityText)")
                                    .font(.caption)
                                    .foregroundStyle(Color.sonaGreen)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Button("上一曲", systemImage: "backward.fill") {
                        player.previous()
                    }
                    .labelStyle(.iconOnly)
                    .frame(width: 30, height: 48)
                    .disabled(!player.canGoPrevious)
                    Button {
                        player.togglePlayback()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 21, weight: .semibold))
                    }
                    .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
                    .frame(width: 30, height: 48)
                    Button("下一曲", systemImage: "forward.fill") {
                        player.next()
                    }
                    .labelStyle(.iconOnly)
                    .frame(width: 30, height: 48)
                    .disabled(!player.canGoNext)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .frame(height: 61)
                .padding(.horizontal, 8)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Color.white.opacity(0.22)
                        Color.white.opacity(0.78)
                            .frame(
                                width: proxy.size.width * min(
                                    max(player.elapsed / max(player.duration, 1), 0),
                                    1
                                )
                            )
                    }
                }
                .frame(height: 2)
                .padding(.horizontal, 8)
            }
            .frame(height: 64)
            .background(Color.sonaPlayerSurface, in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        let horizontal = value.translation.width
                        guard abs(horizontal) > 60,
                              abs(horizontal) > abs(value.translation.height) else { return }
                        if horizontal < 0 {
                            player.next()
                        } else {
                            player.previous()
                        }
                    }
            )
        }
    }
}
