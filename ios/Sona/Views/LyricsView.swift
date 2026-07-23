import SwiftUI

struct LyricsView: View {
    let track: Track
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerStore
    @State private var lines: [LyricLine] = []
    @State private var errorMessage: String?

    private var activeLineID: LyricLine.ID? {
        LyricsParser.activeLineID(in: lines, at: player.elapsed)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sonaSurface.ignoresSafeArea()

                if !lines.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 24) {
                                ForEach(lines) { line in
                                    lyricRow(line, isActive: line.id == activeLineID)
                                        .id(line.id)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 36)
                        }
                        .onChange(of: activeLineID) { _, value in
                            guard let value else { return }
                            withAnimation(.easeInOut(duration: 0.35)) {
                                proxy.scrollTo(value, anchor: .center)
                            }
                        }
                    }
                } else if let errorMessage {
                    ContentUnavailableView(
                        "歌词不可用",
                        systemImage: "quote.bubble",
                        description: Text(errorMessage)
                    )
                    .desktopEmptyState()
                } else {
                    ProgressView("载入歌词…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(track.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
#if targetEnvironment(macCatalyst)
                ToolbarItem(placement: .cancellationAction) {
                    ModalDismissButton("完成")
                }
#else
                ToolbarItem(placement: .topBarTrailing) {
                    ModalDismissButton("完成")
                }
#endif
            }
            .task {
                do {
                    let lyrics = try await APIClient.shared.lyrics(for: track)
                    lines = LyricsParser.parse(synced: lyrics.synced, plain: lyrics.plain)
                    if lines.isEmpty {
                        errorMessage = "没有可显示的歌词内容"
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func lyricRow(_ line: LyricLine, isActive: Bool) -> some View {
        Text(line.text)
            .font(.title3.weight(isActive ? .bold : .semibold))
            .foregroundStyle(isActive ? .white : Color.sonaSecondaryText)
            .lineSpacing(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 48)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(isActive ? Color.sonaGreen : .clear)
                    .frame(width: 32, height: 3)
            }
            .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}
