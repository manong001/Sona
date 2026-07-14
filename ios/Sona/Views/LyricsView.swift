import SwiftUI

struct LyricsView: View {
    let track: Track
    @Environment(\.dismiss) private var dismiss
    @State private var lyrics: Lyrics?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let text = lyrics?.synced ?? lyrics?.plain {
                    Text(text)
                        .font(.title3.weight(.semibold))
                        .lineSpacing(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                } else if let errorMessage {
                    ContentUnavailableView(
                        "歌词不可用",
                        systemImage: "quote.bubble",
                        description: Text(errorMessage)
                    )
                } else {
                    ProgressView("载入歌词…")
                        .padding(.top, 80)
                }
            }
            .background(Color.sonaSurface)
            .navigationTitle(track.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                do {
                    lyrics = try await APIClient.shared.lyrics(for: track)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
