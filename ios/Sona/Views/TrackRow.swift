import SwiftUI

struct TrackRow: View {
    let track: Track
    var showsOfflineBadge = false
    var isFavorite = false
    var moreActionTitle: String?
    var moreActionSystemImage = "ellipsis.circle"
    var moreActionDisabled = false
    var moreAction: (() -> Void)?
    var deleteTitle: String?
    var deleteAction: (() -> Void)?
    var tapAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            if let tapAction {
                trackContent
                    .contentShape(Rectangle())
                    .onTapGesture(perform: tapAction)
            } else {
                trackContent
            }

            if moreAction != nil || deleteTitle != nil {
                Menu {
                    if let moreActionTitle, let moreAction {
                        Button(moreActionTitle, systemImage: moreActionSystemImage) {
                            moreAction()
                        }
                        .disabled(moreActionDisabled)
                    }
                    if let deleteTitle, let deleteAction {
                        Button(deleteTitle, systemImage: "trash", role: .destructive) {
                            deleteAction()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.sonaSecondaryText)
                        .frame(width: 28, height: 40)
                }
            } else {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.sonaSecondaryText)
                    .frame(width: 28)
            }
        }
        .contentShape(Rectangle())
    }

    private var trackContent: some View {
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
        }
    }
}
