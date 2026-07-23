import SwiftUI

struct StablePlaylistArtworkMenu<MenuLabel: View>: View, Equatable {
    let playlistID: String
    let hasSourceArtwork: Bool
    let hasManualArtwork: Bool
    let upload: () -> Void
    let useSourceArtwork: () -> Void
    let clearManualArtwork: () -> Void
    let menuLabel: MenuLabel

    init(
        playlistID: String,
        hasSourceArtwork: Bool,
        hasManualArtwork: Bool,
        upload: @escaping () -> Void,
        useSourceArtwork: @escaping () -> Void,
        clearManualArtwork: @escaping () -> Void,
        @ViewBuilder label: () -> MenuLabel
    ) {
        self.playlistID = playlistID
        self.hasSourceArtwork = hasSourceArtwork
        self.hasManualArtwork = hasManualArtwork
        self.upload = upload
        self.useSourceArtwork = useSourceArtwork
        self.clearManualArtwork = clearManualArtwork
        self.menuLabel = label()
    }

    static func == (
        lhs: StablePlaylistArtworkMenu<MenuLabel>,
        rhs: StablePlaylistArtworkMenu<MenuLabel>
    ) -> Bool {
        lhs.playlistID == rhs.playlistID
            && lhs.hasSourceArtwork == rhs.hasSourceArtwork
            && lhs.hasManualArtwork == rhs.hasManualArtwork
    }

    var body: some View {
        Menu {
            Button("上传图片", systemImage: "photo.badge.plus", action: upload)
            Label("也可从歌曲右侧菜单指定", systemImage: "music.note")
            if hasSourceArtwork {
                Divider()
                Button(
                    "使用源订阅封面",
                    systemImage: "photo.on.rectangle",
                    action: useSourceArtwork
                )
            }
            if hasManualArtwork {
                Divider()
                Button(
                    "恢复自动轮换",
                    systemImage: "arrow.triangle.2.circlepath",
                    action: clearManualArtwork
                )
            }
        } label: {
            menuLabel
        }
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
