import SwiftUI

struct PlaylistArtworkPopup: View {
    let hasSourceArtwork: Bool
    let hasManualArtwork: Bool
    let upload: () -> Void
    let useSourceArtwork: () -> Void
    let clearManualArtwork: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            popupButton("上传图片", systemImage: "photo.badge.plus", action: upload)
            HStack(spacing: 14) {
                Image(systemName: "music.note")
                    .frame(width: 24)
                Text("也可从歌曲右侧菜单指定")
                Spacer()
            }
            .font(.subheadline)
            .foregroundStyle(Color.sonaSecondaryText)
            .padding(.horizontal, 18)
            .frame(minHeight: 54)

            if hasSourceArtwork {
                Divider()
                    .overlay(Color.white.opacity(0.08))
                    .padding(.horizontal, 16)
                popupButton(
                    "使用源订阅封面",
                    systemImage: "photo.on.rectangle",
                    action: useSourceArtwork
                )
            }
            if hasManualArtwork {
                Divider()
                    .overlay(Color.white.opacity(0.08))
                    .padding(.horizontal, 16)
                popupButton(
                    "恢复自动轮换",
                    systemImage: "arrow.triangle.2.circlepath",
                    action: clearManualArtwork
                )
            }
        }
        .frame(maxWidth: 340)
        .background(Color.sonaSurface, in: RoundedRectangle(cornerRadius: 22))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
    }

    private func popupButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .frame(width: 24)
                Text(title)
                Spacer()
            }
            .font(.body)
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct TrackRow: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var personal: PersonalStore
    @State private var trashErrorMessage: String?

    let track: Track
    var showsOfflineBadge = false
    var isFavorite = false
    var allowsMoveToTrash = true
    var moreActionTitle: String?
    var moreActionSystemImage = "ellipsis.circle"
    var moreActionDisabled = false
    var moreAction: (() -> Void)?
    var deleteTitle: String?
    var deleteAction: (() -> Void)?
    var tapAction: (() -> Void)?

    @ViewBuilder
    var body: some View {
        if !allowsMoveToTrash || !personal.hiddenTrackIDs.contains(track.id) {
            HStack(spacing: 0) {
                if let tapAction {
                    trackContent
                        .contentShape(Rectangle())
                        .onTapGesture(perform: tapAction)
                } else {
                    trackContent
                }

                if moreAction != nil || deleteTitle != nil || allowsMoveToTrash {
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
                        if allowsMoveToTrash {
                            Button("移到个人垃圾桶", systemImage: "trash", role: .destructive) {
                                Task { await moveToTrash() }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.sonaSecondaryText)
                            .frame(width: 28, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("操作 \(track.title)")
                } else {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.sonaSecondaryText)
                        .frame(width: 28)
                }
            }
            .contentShape(Rectangle())
            .alert("操作失败", isPresented: Binding(
                get: { trashErrorMessage != nil },
                set: { if !$0 { trashErrorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(trashErrorMessage ?? "未知错误")
            }
        }
    }

    private func moveToTrash() async {
        guard await personal.moveTrackToTrash(track.id) else {
            trashErrorMessage = personal.errorMessage ?? "无法移到个人垃圾桶"
            return
        }
        library.removeTrack(id: track.id)
        player.removeTrack(id: track.id)
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
