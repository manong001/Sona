import SwiftUI

struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var playbackProgress: PlaybackProgress
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var personal: PersonalStore
    @State private var showsLyrics = false
    @State private var showsQueue = false
    @State private var lyricLines: [LyricLine] = []
    @State private var isSeeking = false
    @State private var seekPreview = 0.0
    @State private var seekCommitTask: Task<Void, Never>?
    @State private var feedbackToUndo: RecommendationFeedback?
    @State private var feedbackMessage: String?
    @State private var isUpdatingRecommendation = false
    var onClose: (() -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [Color.sonaSurface.opacity(0.98), Color(red: 0.05, green: 0.05, blue: 0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if let track = player.currentTrack {
                    VStack(spacing: 0) {
                        HStack {
                            Button("关闭", systemImage: "chevron.down") {
                                if let onClose {
                                    onClose()
                                } else {
                                    dismiss()
                                }
                            }
                                .labelStyle(.iconOnly)
                                .font(.title3.weight(.semibold))
                                .frame(width: 44, height: 44)
                            Spacer()
                            VStack(spacing: 2) {
                                Text(displayQueueTitle)
                                    .font(.caption.bold())
                                Text("正在播放")
                                    .font(.caption2)
                                    .foregroundStyle(Color.sonaSecondaryText)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("播放列表", systemImage: "list.bullet") {
                                showsQueue = true
                            }
                            .labelStyle(.iconOnly)
                            .font(.title3.weight(.semibold))
                            .frame(width: 44, height: 44)
                        }
                        .padding(.top, 8)

                        Spacer(minLength: 8)

                        ArtworkView(path: track.artworkURL, cornerRadius: 12)
                            .frame(
                                width: artworkSize(in: proxy.size),
                                height: artworkSize(in: proxy.size)
                            )
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.16), lineWidth: 1))
                            .shadow(color: .black.opacity(0.5), radius: 22, y: 12)

                        Spacer(minLength: 18)

                        Button {
                            showsLyrics = true
                        } label: {
                            Text(currentLyric ?? (track.hasLyrics ? "载入歌词…" : "暂无歌词"))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(
                                    currentLyric == nil ? Color.sonaSecondaryText : .white
                                )
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .contentTransition(.opacity)
                                .animation(.easeInOut(duration: 0.25), value: currentLyric)
                        }
                        .disabled(!track.hasLyrics)
                        .padding(.bottom, 16)

                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(track.title)
                                    .font(.title3.bold())
                                    .lineLimit(1)
                                Text("\(track.artist) · \(track.album)")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.sonaSecondaryText)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                Task { await personal.toggleFavorite(trackID: track.id) }
                            } label: {
                                Image(systemName: personal.favoriteIDs.contains(track.id) ? "heart.fill" : "heart")
                                    .font(.title2)
                                    .foregroundStyle(
                                        personal.favoriteIDs.contains(track.id) ? Color.sonaGreen : .white
                                    )
                                    .frame(width: 44, height: 44)
                            }
                            Menu {
                                Button(
                                    RecommendationFeedbackType.track.title,
                                    systemImage: "hand.thumbsdown"
                                ) {
                                    Task { await submitFeedback(.track, for: track) }
                                }
                                Button(
                                    RecommendationFeedbackType.artist.title,
                                    systemImage: "person.crop.circle.badge.minus"
                                ) {
                                    Task { await submitFeedback(.artist, for: track) }
                                }
                                Button(
                                    RecommendationFeedbackType.genre.title,
                                    systemImage: "guitars"
                                ) {
                                    Task { await submitFeedback(.genre, for: track) }
                                }
                                .disabled(track.genre == "未分类")
                            } label: {
                                if isUpdatingRecommendation {
                                    ProgressView().frame(width: 44, height: 44)
                                } else {
                                    Image(systemName: "ellipsis")
                                        .font(.title3)
                                        .frame(width: 44, height: 44)
                                }
                            }
                            .disabled(isUpdatingRecommendation)
                        }

                        VStack(spacing: 5) {
                            Slider(
                                value: Binding(
                                    get: {
                                        isSeeking ? seekPreview : playbackProgress.elapsed
                                    },
                                    set: { seekPreview = $0 }
                                ),
                                in: 0...max(playbackProgress.duration, 1),
                                onEditingChanged: { editing in
                                    if editing {
                                        seekCommitTask?.cancel()
                                        seekPreview = playbackProgress.elapsed
                                        isSeeking = true
                                    } else {
                                        let trackID = track.id
                                        let displayedDuration = playbackProgress.duration
                                        seekCommitTask = Task { @MainActor in
                                            await Task.yield()
                                            guard !Task.isCancelled,
                                                  player.currentTrack?.id == trackID else { return }
                                            let target = seekPreview
                                            isSeeking = false
                                            player.seek(
                                                to: target,
                                                displayedDuration: displayedDuration
                                            )
                                        }
                                    }
                                }
                            )
                            .tint(.white)
                            .id(track.id)
                            HStack {
                                Text(time(isSeeking ? seekPreview : playbackProgress.elapsed))
                                Spacer()
                                Text("-" + time(max(
                                    0,
                                    playbackProgress.duration
                                        - (isSeeking ? seekPreview : playbackProgress.elapsed)
                                )))
                            }
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Color.sonaSecondaryText)
                        }
                        .padding(.top, 12)

                        HStack {
                            Button {
                                player.toggleShuffle()
                            } label: {
                                Image(systemName: "shuffle")
                                    .foregroundStyle(player.playbackMode == .shuffle ? Color.sonaGreen : .white)
                            }
                            Spacer()
                            Button("上一曲", systemImage: "backward.fill") { player.previous() }
                                .labelStyle(.iconOnly)
                                .font(.system(size: 27))
                                .disabled(!player.canGoPrevious)
                            Spacer()
                            Button {
                                player.togglePlayback()
                            } label: {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(.black)
                                    .frame(width: 68, height: 68)
                                    .background(.white, in: Circle())
                            }
                            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
                            Spacer()
                            Button("下一曲", systemImage: "forward.fill") { player.next() }
                                .labelStyle(.iconOnly)
                                .font(.system(size: 27))
                                .disabled(!player.canGoNext)
                            Spacer()
                            Button {
                                player.toggleRepeatOne()
                            } label: {
                                Image(systemName: "repeat.1")
                                    .foregroundStyle(player.playbackMode == .repeatOne ? Color.sonaGreen : .white)
                            }
                        }
                        .font(.title3)
                        .frame(height: 88)

                        HStack {
                            Button {
                                toggleOffline(track)
                            } label: {
                                if offline.activeDownloads.contains(track.id) {
                                    ProgressView()
                                } else {
                                    Label(
                                        offline.downloadedIDs.contains(track.id) ? "已离线" : "离线下载",
                                        systemImage: offline.downloadedIDs.contains(track.id)
                                            ? "arrow.down.circle.fill"
                                            : "arrow.down.circle"
                                    )
                                }
                            }
                            Spacer()
                            Button("相似续听", systemImage: "infinity") {
                                player.continueWithSimilarTracks()
                            }
                            .foregroundStyle(Color.sonaGreen)
                            Spacer()
                            Button("歌词", systemImage: "quote.bubble") {
                                showsLyrics = true
                            }
                            .disabled(!track.hasLyrics)
                        }
                        .font(.caption.weight(.semibold))

                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 35).onEnded { value in
                    if value.translation.width > 70, player.currentTrack?.hasLyrics == true {
                        showsLyrics = true
                    }
                }
            )
        }
        .sheet(isPresented: $showsLyrics) {
            if let track = player.currentTrack {
                LyricsView(track: track)
                    .desktopSheetSize(.large)
            }
        }
        .sheet(isPresented: $showsQueue) {
            PlaybackQueueView()
                .desktopSheetSize(.large)
        }
        .task(id: player.currentTrack?.id) {
            seekCommitTask?.cancel()
            seekCommitTask = nil
            isSeeking = false
            seekPreview = 0
            await loadLyrics(for: player.currentTrack)
        }
        .alert("推荐已调整", isPresented: Binding(
            get: { feedbackMessage != nil },
            set: { if !$0 { feedbackMessage = nil } }
        )) {
            if feedbackToUndo != nil {
                Button("撤销") { Task { await undoFeedback() } }
            }
            Button("好", role: .cancel) {}
        } message: {
            Text(feedbackMessage ?? "")
        }
    }

    private var displayQueueTitle: String {
        player.queueTitle == player.queueContextID ? "歌单" : player.queueTitle
    }

    private var currentLyric: String? {
        LyricsParser.activeLine(
            in: lyricLines,
            at: playbackProgress.elapsed,
            duration: playbackProgress.duration
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

    private func toggleOffline(_ track: Track) {
        if offline.downloadedIDs.contains(track.id) {
            offline.remove(track)
        } else {
            Task { await offline.download(track) }
        }
    }

    @MainActor
    private func submitFeedback(
        _ type: RecommendationFeedbackType, for track: Track
    ) async {
        isUpdatingRecommendation = true
        defer { isUpdatingRecommendation = false }
        do {
            let feedback = try await APIClient.shared.addRecommendationFeedback(
                type: type, trackID: track.id
            )
            feedbackToUndo = feedback
            feedbackMessage = "\(type.title)：\(feedback.displayValue)"
            if type == .track {
                player.next()
            }
        } catch {
            feedbackToUndo = nil
            feedbackMessage = "操作失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func undoFeedback() async {
        guard let feedback = feedbackToUndo else { return }
        do {
            try await APIClient.shared.removeRecommendationFeedback(id: feedback.id)
            feedbackToUndo = nil
            feedbackMessage = nil
        } catch {
            feedbackMessage = "撤销失败：\(error.localizedDescription)"
        }
    }

    private func artworkSize(in size: CGSize) -> CGFloat {
        max(1, min(max(0, size.width - 56), max(0, size.height * 0.42)))
    }

    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let value = max(0, Int(seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct PlaybackQueueView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var personal: PersonalStore
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(player.playbackQueue.enumerated()), id: \.element.id) { index, track in
                        Button {
                            player.playQueuedTrack(track)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Color.sonaSecondaryText)
                                    .frame(width: 24, alignment: .trailing)
                                TrackRow(
                                    track: track,
                                    showsOfflineBadge: offline.downloadedIDs.contains(track.id),
                                    isFavorite: personal.favoriteIDs.contains(track.id)
                                )
                                if player.currentTrack?.id == track.id {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundStyle(Color.sonaGreen)
                                }
                                if player.automaticallyAddedTrackIDs.contains(track.id) {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Label("智能续播", systemImage: "sparkles")
                                            .font(.caption2.bold())
                                            .foregroundStyle(Color.sonaGreen)
                                        if let reason = player.automaticRecommendationReasons[track.id] {
                                            Text(reason)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onMove { player.moveQueueItems(from: $0, to: $1) }
                    .onDelete { player.removeQueueItems(at: $0) }
                } header: {
                    Text("\(player.queueTitle) · \(player.playbackQueue.count) 首")
                }

                if player.isLoadingQueue {
                    HStack {
                        Spacer()
                        ProgressView("正在随机补充歌曲…")
                        Spacer()
                    }
                }

                if let message = player.queueErrorMessage {
                    Text(message).foregroundStyle(.red)
                }

                if !player.automaticallyAddedTrackIDs.isEmpty {
                    Button("撤回最近智能续播", systemImage: "arrow.uturn.backward") {
                        player.undoLastAutomaticAdditions()
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.sonaBackground)
            .environment(\.editMode, $editMode)
            .navigationTitle("播放列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("清空待播", role: .destructive) { player.clearUpcomingQueue() }
                        .disabled(player.playbackQueue.count <= 1)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        editMode == .active ? "完成" : "编辑",
                        systemImage: editMode == .active ? "checkmark" : "pencil"
                    ) {
                        editMode = editMode == .active ? .inactive : .active
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
