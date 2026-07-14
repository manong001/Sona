import SwiftUI

struct TrackRow: View {
    let track: Track
    var showsOfflineBadge = false
    var isFavorite = false

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(path: track.artworkURL, cornerRadius: 6)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if showsOfflineBadge {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Color.sonaGreen)
                    }
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(Color.sonaGreen)
                    }
                    Text("\(track.artist) · \(track.album)")
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.sonaSecondaryText)
                .frame(width: 28)
        }
        .contentShape(Rectangle())
    }
}
