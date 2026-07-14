import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var personal: PersonalStore
    @AppStorage("miniPlayerSide") private var anchoredSide = "right"
    @AppStorage("miniPlayerY") private var storedY = 0.0
    @GestureState private var dragTranslation: CGSize = .zero
    @State private var showsQueue = false
    let open: () -> Void

    private let diameter: CGFloat = 76
    private let edgeSpacing: CGFloat = 12
    private let tabBarClearance: CGFloat = 68

    var body: some View {
        GeometryReader { proxy in
            if let track = player.currentTrack {
                let bounds = movementBounds(in: proxy.size)
                let baseX = anchoredSide == "left" ? bounds.minX : bounds.maxX
                let preferredY = storedY > 0 ? CGFloat(storedY) : bounds.maxY
                let baseY = clamped(preferredY, from: bounds.minY, to: bounds.maxY)

                ZStack(alignment: .bottom) {
                    Button(action: open) {
                        cdArtwork(for: track)
                    }
                    .buttonStyle(.plain)

                    HStack {
                        Button(
                            personal.favoriteIDs.contains(track.id) ? "取消收藏" : "收藏",
                            systemImage: personal.favoriteIDs.contains(track.id) ? "heart.fill" : "heart"
                        ) {
                            Task { await personal.toggleFavorite(trackID: track.id) }
                        }
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(
                            personal.favoriteIDs.contains(track.id) ? Color.sonaGreen : .white
                        )
                        .frame(width: 29, height: 29)
                        .background(.black.opacity(0.9), in: Circle())
                        .overlay(Circle().stroke(Color.sonaGreen, lineWidth: 2))
                        .buttonStyle(.plain)

                        Spacer()

                        Button("播放列表", systemImage: "list.bullet") {
                            showsQueue = true
                        }
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 29, height: 29)
                        .background(.black.opacity(0.9), in: Circle())
                        .overlay(Circle().stroke(Color.sonaGreen, lineWidth: 2))
                        .buttonStyle(.plain)
                    }
                    .frame(width: diameter)
                }
                    .frame(width: diameter, height: diameter)
                    .contentShape(Circle())
                    .position(
                        x: clamped(baseX + dragTranslation.width, from: bounds.minX, to: bounds.maxX),
                        y: clamped(baseY + dragTranslation.height, from: bounds.minY, to: bounds.maxY)
                    )
                    .gesture(
                        DragGesture(minimumDistance: 6)
                            .updating($dragTranslation) { value, state, _ in
                                state = value.translation
                            }
                            .onEnded { value in
                                let endX = clamped(
                                    baseX + value.translation.width,
                                    from: bounds.minX,
                                    to: bounds.maxX
                                )
                                anchoredSide = endX < proxy.size.width / 2 ? "left" : "right"
                                storedY = Double(clamped(
                                    baseY + value.translation.height,
                                    from: bounds.minY,
                                    to: bounds.maxY
                                ))
                            }
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.78), value: anchoredSide)
                    .accessibilityLabel("迷你播放器，\(track.title)")
                    .accessibilityHint("轻点打开播放页，拖动后会吸附屏幕边缘")
                    .accessibilityAction(named: player.isPlaying ? "暂停" : "播放") {
                        player.togglePlayback()
                    }
                    .accessibilityAction(named: "上一曲") { player.previous() }
                    .accessibilityAction(named: "下一曲") { player.next() }
            }
        }
        .sheet(isPresented: $showsQueue) {
            PlaybackQueueView()
        }
    }

    private func cdArtwork(for track: Track) -> some View {
        ZStack {
            Circle()
                .fill(.black)
                .shadow(color: .black.opacity(0.55), radius: 10, y: 5)

            ArtworkView(path: track.artworkURL, cornerRadius: diameter / 2)
                .frame(width: diameter - 6, height: diameter - 6)
                .clipShape(Circle())

            Circle()
                .stroke(.white.opacity(0.28), lineWidth: 1)

            Circle()
                .trim(from: 0, to: playbackProgress)
                .stroke(Color.sonaGreen, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Circle()
                .fill(.black.opacity(0.88))
                .frame(width: 25, height: 25)
                .overlay {
                    Image(systemName: player.isPlaying ? "waveform" : "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
                .overlay {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 1)
                }
        }
    }

    private var playbackProgress: CGFloat {
        CGFloat(min(max(player.elapsed / max(player.duration, 1), 0), 1))
    }

    private func movementBounds(in size: CGSize) -> CGRect {
        let radius = diameter / 2
        return CGRect(
            x: radius + edgeSpacing,
            y: radius + edgeSpacing,
            width: max(0, size.width - (radius + edgeSpacing) * 2),
            height: max(0, size.height - radius * 2 - edgeSpacing - tabBarClearance)
        )
    }

    private func clamped(_ value: CGFloat, from lower: CGFloat, to upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
