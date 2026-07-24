import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var playbackTimeline: PlaybackProgress
    @EnvironmentObject private var personal: PersonalStore
    @AppStorage("miniPlayerSide") private var anchoredSide = "right"
    @AppStorage("miniPlayerY") private var storedY = 0.0
    @AppStorage("miniPlayerMode") private var miniPlayerMode = "floating"
    @AppStorage("childMode") private var childMode = false
    @AppStorage("childTheme") private var childTheme = "boy"
    @State private var dragState: FloatingMiniPlayerDragState?
    @State private var lyricLines: [LyricLine] = []
    @State private var showsQueue = false
    let open: () -> Void

    private let diameter: CGFloat = 76
    private let edgeSpacing: CGFloat = 12
    private let tabBarClearance: CGFloat = 68

    var body: some View {
        GeometryReader { proxy in
            let track = player.currentTrack
            if miniPlayerMode == "fixed" {
                VStack {
                    Spacer()
                    fixedBar(for: track)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 52)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                let playerSize = floatingPlayerSize
                let bounds = movementBounds(in: proxy.size, itemSize: playerSize)
                let baseX = anchoredSide == "left" ? bounds.minX : bounds.maxX
                let preferredY = storedY > 0 ? CGFloat(storedY) : bounds.maxY
                let baseY = clamped(preferredY, from: bounds.minY, to: bounds.maxY)
                let basePosition = CGPoint(x: baseX, y: baseY)
                let displayedPosition = dragState?.position ?? basePosition

                ZStack(alignment: .bottom) {
                    Button {
                        if track != nil { open() }
                    } label: {
                        cdArtwork(for: track)
                    }
                    .buttonStyle(.plain)
                    .disabled(track == nil)

                    HStack {
                        Button(
                            track.map { personal.favoriteIDs.contains($0.id) } == true ? "取消收藏" : "收藏",
                            systemImage: track.map { personal.favoriteIDs.contains($0.id) } == true ? "heart.fill" : "heart"
                        ) {
                            guard let track else { return }
                            Task { await personal.toggleFavorite(trackID: track.id) }
                        }
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(
                            track.map { personal.favoriteIDs.contains($0.id) } == true
                                ? (childMode ? childTint : Color.sonaGreen) : .white
                        )
                        .frame(width: 29, height: 29)
                        .background { floatingControlBackground }
                        .overlay(Circle().stroke(childMode ? childTint.opacity(0.7) : Color.sonaGreen, lineWidth: 2))
                        .buttonStyle(.plain)
                        .disabled(track == nil)

                        Spacer()

                        Button("播放列表", systemImage: "list.bullet") {
                            showsQueue = true
                        }
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 29, height: 29)
                        .background { floatingControlBackground }
                        .overlay(Circle().stroke(childMode ? childTint.opacity(0.7) : Color.sonaGreen, lineWidth: 2))
                        .buttonStyle(.plain)
                    }
                    .frame(width: playerSize.width)
                }
                    .frame(width: playerSize.width, height: playerSize.height)
                    .contentShape(RoundedRectangle(cornerRadius: playerSize.height / 2))
                    .position(displayedPosition)
                    .simultaneousGesture(
                        DragGesture(
                            minimumDistance: 0,
                            coordinateSpace: .named("miniPlayerSurface")
                        )
                            .onChanged { value in
                                var state: FloatingMiniPlayerDragState
                                if let dragState {
                                    state = dragState
                                } else {
                                    state = FloatingMiniPlayerDragState(position: basePosition)
                                    state.begin(at: value.startLocation)
                                }
                                state.move(to: value.location, within: bounds)
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) { dragState = state }
                            }
                            .onEnded { value in
                                var state = dragState ?? FloatingMiniPlayerDragState(
                                    position: basePosition
                                )
                                let result = state.snap(to: value.location, within: bounds)
                                withAnimation(.interactiveSpring(
                                    response: 0.28,
                                    dampingFraction: 0.82,
                                    blendDuration: 0.12
                                )) {
                                    dragState = nil
                                    anchoredSide = result.side.rawValue
                                    storedY = Double(result.position.y)
                                }
                            }
                    )
                    .accessibilityLabel("迷你播放器，\(track?.title ?? "暂无播放")")
                    .accessibilityHint(
                        track == nil ? "选择一首歌曲开始播放，拖动后会吸附屏幕边缘" :
                            "轻点打开播放页，拖动后会吸附屏幕边缘"
                    )
                    .accessibilityAction(named: player.isPlaying ? "暂停" : "播放") {
                        if track != nil { player.togglePlayback() }
                    }
                    .accessibilityAction(named: "上一曲") {
                        if track != nil { player.previous() }
                    }
                    .accessibilityAction(named: "下一曲") {
                        if track != nil { player.next() }
                    }
            }
        }
        .coordinateSpace(name: "miniPlayerSurface")
        .sheet(isPresented: $showsQueue) {
            PlaybackQueueView()
                .desktopSheetSize(.large)
        }
        .task(id: player.currentTrack?.id) {
            await loadLyrics(for: player.currentTrack)
        }
    }

    @ViewBuilder
    private func fixedBar(for track: Track?) -> some View {
        if childMode {
            childFixedBar(for: track)
        } else {
            standardFixedBar(for: track)
        }
    }

    private func standardFixedBar(for track: Track?) -> some View {
        let detail = currentLyric ?? track?.artist ?? "选择一首歌曲开始播放"
        return VStack(spacing: 0) {
            GeometryReader { proxy in
                Color.sonaGreen
                    .frame(width: proxy.size.width * playbackProgress)
            }
            .frame(height: 2)

            HStack(spacing: 10) {
                Button {
                    if track != nil { open() }
                } label: {
                    HStack(spacing: 10) {
                        miniArtwork(for: track)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track?.title ?? "暂无播放")
                                .font(.subheadline.bold())
                                .lineLimit(1)
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(Color.sonaSecondaryText)
                                .lineLimit(1)
                                .contentTransition(.opacity)
                                .animation(.easeInOut(duration: 0.25), value: detail)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .disabled(track == nil)
                .buttonStyle(.plain)

                HStack(spacing: 12) {
                    Button(
                        track.map { personal.favoriteIDs.contains($0.id) } == true
                            ? "取消收藏" : "收藏",
                        systemImage: track.map { personal.favoriteIDs.contains($0.id) } == true
                            ? "heart.fill" : "heart"
                    ) {
                        guard let track else { return }
                        Task { await personal.toggleFavorite(trackID: track.id) }
                    }
                    .foregroundStyle(
                        track.map { personal.favoriteIDs.contains($0.id) } == true
                            ? Color.sonaGreen : .white
                    )
                    .disabled(track == nil)

                    Button(
                        player.isPlaying ? "暂停" : "播放",
                        systemImage: player.isPlaying ? "pause.fill" : "play.fill"
                    ) {
                        player.togglePlayback()
                    }
                    .disabled(track == nil)

                    Button("播放列表", systemImage: "list.bullet") {
                        showsQueue = true
                    }
                }
                .frame(height: 44)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: 18, weight: .semibold))
            .padding(.horizontal, 12)
            .frame(height: 66)
        }
        .frame(height: 68)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13))
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    guard track != nil,
                          let action = FixedMiniPlayerSwipe.action(
                              for: value.translation
                          ) else { return }
                    switch action {
                    case .previous:
                        if player.canGoPrevious { player.previous() }
                    case .next:
                        if player.canGoNext { player.next() }
                    }
                }
        )
    }

    private func childFixedBar(for track: Track?) -> some View {
        let detail = currentLyric ?? track?.artist ?? "选择一首歌曲开始播放"
        return ZStack(alignment: .bottom) {
            Capsule()
                .fill(.ultraThinMaterial)
                .frame(height: 58)
                .padding(.leading, 82)
                .overlay(alignment: .bottom) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(childTint.opacity(0.82))
                            .frame(width: proxy.size.width * playbackProgress, height: 2)
                    }
                    .frame(height: 2)
                    .padding(.leading, 100)
                    .padding(.trailing, 12)
                }

            HStack(spacing: 4) {
                Button {
                    if track != nil { open() }
                } label: {
                    ChildMiniPlayerMascot(
                        kind: childTheme == "girl" ? .rabbit : .cat,
                        artworkPath: track?.artworkURL,
                        progress: track == nil ? 0 : playbackProgress,
                        isPlaying: player.isPlaying,
                        hasTrack: track != nil
                    )
                    .frame(width: 126, height: 74)
                }
                .buttonStyle(.plain)
                .disabled(track == nil)

                Button {
                    if track != nil { open() }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track?.title ?? "暂无播放")
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Color.sonaSecondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(track == nil)

                HStack(spacing: 11) {
                    Button(
                        track.map { personal.favoriteIDs.contains($0.id) } == true
                            ? "取消收藏" : "收藏",
                        systemImage: track.map { personal.favoriteIDs.contains($0.id) } == true
                            ? "heart.fill" : "heart"
                    ) {
                        guard let track else { return }
                        Task { await personal.toggleFavorite(trackID: track.id) }
                    }
                    .foregroundStyle(
                        track.map { personal.favoriteIDs.contains($0.id) } == true
                            ? childTint : .white
                    )
                    .disabled(track == nil)

                    Button(
                        player.isPlaying ? "暂停" : "播放",
                        systemImage: player.isPlaying ? "pause.fill" : "play.fill"
                    ) {
                        player.togglePlayback()
                    }
                    .disabled(track == nil)

                    Button("播放列表", systemImage: "list.bullet") {
                        showsQueue = true
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .padding(.trailing, 14)
            }
            .frame(height: 76)
        }
        .frame(height: 78)
        .contentShape(Capsule())
        .highPriorityGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    guard track != nil,
                          let action = FixedMiniPlayerSwipe.action(for: value.translation) else { return }
                    switch action {
                    case .previous:
                        if player.canGoPrevious { player.previous() }
                    case .next:
                        if player.canGoNext { player.next() }
                    }
                }
        )
    }

    private var currentLyric: String? {
        LyricsParser.activeLine(
            in: lyricLines,
            at: playbackTimeline.elapsed,
            duration: playbackTimeline.duration
        )?.text
    }

    @MainActor
    private func loadLyrics(for track: Track?) async {
        lyricLines = []
        guard let track, track.hasLyrics else { return }
        do {
            let lyrics = try await APIClient.shared.lyrics(for: track)
            guard !Task.isCancelled, player.currentTrack?.id == track.id else { return }
            lyricLines = LyricsParser.parse(synced: lyrics.synced, plain: lyrics.plain)
        } catch {
            lyricLines = []
        }
    }

    @ViewBuilder
    private func cdArtwork(for track: Track?) -> some View {
        if childMode {
            ChildMiniPlayerMascot(
                kind: childTheme == "girl" ? .rabbit : .cat,
                artworkPath: track?.artworkURL,
                progress: track == nil ? 0 : playbackProgress,
                isPlaying: player.isPlaying,
                hasTrack: track != nil
            )
        } else {
            ZStack {
                Circle()
                    .fill(.black)
                    .shadow(color: .black.opacity(0.55), radius: 10, y: 5)

                ArtworkView(path: track?.artworkURL, cornerRadius: diameter / 2)
                    .frame(width: diameter - 6, height: diameter - 6)
                    .clipShape(Circle())

                Circle()
                    .stroke(.white.opacity(0.28), lineWidth: 1)

                Circle()
                    .trim(from: 0, to: track == nil ? 0 : playbackProgress)
                    .stroke(Color.sonaGreen, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                playbackBadge(hasTrack: track != nil)
            }
        }
    }

    @ViewBuilder
    private func miniArtwork(for track: Track?) -> some View {
        if childMode {
            ChildMiniPlayerMascot(
                kind: childTheme == "girl" ? .rabbit : .cat,
                artworkPath: track?.artworkURL,
                progress: track == nil ? 0 : playbackProgress,
                isPlaying: player.isPlaying,
                hasTrack: track != nil
            )
            .scaleEffect(0.68)
            .frame(width: 52, height: 52)
        } else {
            ArtworkView(path: track?.artworkURL, cornerRadius: 6)
                .frame(width: 52, height: 52)
        }
    }

    private func playbackBadge(hasTrack: Bool) -> some View {
        Circle()
            .fill(.black.opacity(0.88))
            .frame(width: 25, height: 25)
            .overlay {
                Image(systemName: hasTrack ? (player.isPlaying ? "waveform" : "play.fill") : "music.note")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
            .overlay {
                Circle().stroke(.white.opacity(0.25), lineWidth: 1)
            }
    }

    private var playbackProgress: CGFloat {
        CGFloat(min(max(
            playbackTimeline.elapsed / max(playbackTimeline.duration, 1),
            0
        ), 1))
    }

    private var childTint: Color {
        childTheme == "girl" ? .pink : .cyan
    }

    @ViewBuilder
    private var floatingControlBackground: some View {
        if childMode {
            Circle().fill(.ultraThinMaterial)
        } else {
            Circle().fill(.black.opacity(0.9))
        }
    }

    private var floatingPlayerSize: CGSize {
        childMode ? CGSize(width: 112, height: 76) : CGSize(width: diameter, height: diameter)
    }

    private func movementBounds(in size: CGSize, itemSize: CGSize) -> CGRect {
        let halfWidth = itemSize.width / 2
        let halfHeight = itemSize.height / 2
        return CGRect(
            x: halfWidth + edgeSpacing,
            y: halfHeight + edgeSpacing,
            width: max(0, size.width - (halfWidth + edgeSpacing) * 2),
            height: max(0, size.height - itemSize.height - edgeSpacing - tabBarClearance)
        )
    }

    private func clamped(_ value: CGFloat, from lower: CGFloat, to upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}

private enum ChildMiniPlayerMascotKind {
    case cat
    case rabbit

    var assetName: String {
        switch self {
        case .cat: "ChildMascotCat"
        case .rabbit: "ChildMascotRabbit"
        }
    }

    var tint: Color {
        switch self {
        case .cat: .cyan
        case .rabbit: .pink
        }
    }
}

private struct ChildMiniPlayerMascot: View {
    let kind: ChildMiniPlayerMascotKind
    let artworkPath: String?
    let progress: CGFloat
    let isPlaying: Bool
    let hasTrack: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let speed = isPlaying ? 2.1 : 1.25
            let breath = sin(time * speed)
            let curiousTilt = isPlaying ? sin(time * 0.72) * 0.45 : 0

            ZStack(alignment: .bottomTrailing) {
                Ellipse()
                    .fill(.black.opacity(0.2 + breath * 0.018))
                    .frame(width: 88, height: 16)
                    .blur(radius: 5)
                    .offset(y: 1)

                Image(kind.assetName)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(
                        x: 1 - breath * 0.002,
                        y: 1 + breath * 0.012,
                        anchor: .bottom
                    )
                    .rotationEffect(.degrees(curiousTilt), anchor: .bottomLeading)
                    .offset(y: -1 - breath * 0.45)
                    .shadow(color: kind.tint.opacity(0.2), radius: 7, y: 3)

                ZStack {
                    ArtworkView(path: artworkPath, cornerRadius: 13)
                        .frame(width: 26, height: 26)
                        .clipShape(Circle())

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(kind.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Circle()
                        .fill(.black.opacity(0.58))
                        .padding(5)
                        .overlay {
                            Image(systemName: hasTrack
                                  ? (isPlaying ? "waveform" : "play.fill")
                                  : "music.note")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white)
                        }
                }
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                .offset(x: -40, y: -2 + breath * 0.35)
            }
        }
        .accessibilityHidden(true)
    }
}
