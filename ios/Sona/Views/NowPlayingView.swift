import SwiftUI

struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var personal: PersonalStore
    @State private var showsLyrics = false
    @State private var showsQueue = false

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
                            Button("关闭", systemImage: "chevron.down") { dismiss() }
                                .labelStyle(.iconOnly)
                                .font(.title3.weight(.semibold))
                                .frame(width: 44, height: 44)
                            Spacer()
                            VStack(spacing: 2) {
                                Text(player.queueTitle)
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

                        Spacer(minLength: 8)

                        ArtworkView(path: track.artworkURL, cornerRadius: 12)
                            .frame(
                                width: min(proxy.size.width - 56, proxy.size.height * 0.42),
                                height: min(proxy.size.width - 56, proxy.size.height * 0.42)
                            )
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.16), lineWidth: 1))
                            .shadow(color: .black.opacity(0.5), radius: 22, y: 12)

                        Spacer(minLength: 22)

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
                        }

                        VStack(spacing: 5) {
                            Slider(
                                value: Binding(
                                    get: { player.elapsed },
                                    set: { player.seek(to: $0) }
                                ),
                                in: 0...max(player.duration, 1)
                            )
                            .tint(.white)
                            HStack {
                                Text(time(player.elapsed))
                                Spacer()
                                Text("-" + time(max(0, player.duration - player.elapsed)))
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
                            Text(track.qualityText)
                                .foregroundStyle(Color.sonaGreen)
                            Spacer()
                            Button("歌词", systemImage: "quote.bubble") {
                                showsLyrics = true
                            }
                            .disabled(!track.hasLyrics)
                        }
                        .font(.caption.weight(.semibold))

                        Spacer(minLength: 10)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 16)
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
            }
        }
        .sheet(isPresented: $showsQueue) {
            PlaybackQueueView()
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

struct PlaybackQueueView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var personal: PersonalStore

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
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.sonaBackground)
            .navigationTitle("播放列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("清空待播", role: .destructive) { player.clearUpcomingQueue() }
                        .disabled(player.playbackQueue.count <= 1)
                }
                ToolbarItem(placement: .confirmationAction) {
                    EditButton()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
