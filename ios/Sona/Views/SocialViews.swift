import AVKit
import CoreTransferable
import ImageIO
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SocialHubView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var social: SocialStore
    @State private var section = SocialSection.messages
    @State private var showsAddFriend = false
    @State private var showsComposer = false
    @State private var showsProfileEditor = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("社交", selection: $section) {
                    ForEach(SocialSection.allCases) { value in
                        Label(value.title, systemImage: value.icon).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                Divider().overlay(Color.white.opacity(0.1))
                content
            }
            .background(Color.sonaBackground.ignoresSafeArea())
            .navigationTitle("乐友圈")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showsProfileEditor = true } label: {
                        SonaAvatarView(
                            username: social.profile?.username ?? session.currentUser?.username ?? "Sona",
                            avatarPreset: social.profile?.avatarPreset ?? session.currentUser?.avatarPreset,
                            avatarURL: social.profile?.avatarURL ?? session.currentUser?.avatarURL,
                            size: 34
                        )
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("添加好友", systemImage: "person.badge.plus") { showsAddFriend = true }
                    if section == .moments {
                        Button("发布动态", systemImage: "camera.fill") { showsComposer = true }
                    }
                }
            }
            .sheet(isPresented: $showsAddFriend) { SocialAddFriendView() }
            .sheet(isPresented: $showsComposer) { SocialMomentComposerView() }
            .sheet(isPresented: $showsProfileEditor) { SocialProfileEditorView() }
            .task(id: session.currentUser?.id) {
                guard session.currentUser != nil else { social.reset(); return }
                await social.bootstrap()
            }
            .task(id: session.currentUser?.id) {
                guard session.currentUser != nil else { return }
                while !Task.isCancelled {
                    await social.heartbeat()
                    try? await Task.sleep(for: .seconds(20))
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .messages:
            SocialConversationListView()
        case .contacts:
            SocialContactListView(showsAddFriend: $showsAddFriend)
        case .moments:
            SocialMomentFeedView(showsComposer: $showsComposer)
        }
    }
}

private struct SocialConversationListView: View {
    @EnvironmentObject private var social: SocialStore

    var body: some View {
        Group {
            if social.conversations.isEmpty {
                ContentUnavailableView(
                    "还没有对话",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("先添加好友，再分享音乐和此刻心情。")
                )
            } else {
                List(social.conversations) { user in
                    NavigationLink { SocialChatView(peer: user) } label: {
                        SocialContactRow(user: user, showsMessage: true)
                    }
                    .listRowBackground(Color.sonaSurface)
                }
                .listStyle(.plain)
                .refreshable { try? await social.loadConversations() }
            }
        }
    }
}

private struct SocialContactListView: View {
    @EnvironmentObject private var social: SocialStore
    @Binding var showsAddFriend: Bool
    @State private var deleting: SocialUser?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if social.friends.isEmpty {
                VStack(spacing: 18) {
                    ContentUnavailableView(
                        "通讯录还是空的",
                        systemImage: "person.2",
                        description: Text("通过账号名找到一起听歌的朋友。")
                    )
                    Button("添加好友") { showsAddFriend = true }
                        .buttonStyle(.borderedProminent)
                        .tint(.sonaGreen)
                }
            } else {
                List(social.friends) { user in
                    NavigationLink { SocialChatView(peer: user) } label: {
                        SocialContactRow(user: user, showsLastLogin: social.profile?.isAdmin == true)
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) { deleting = user }
                    }
                    .listRowBackground(Color.sonaSurface)
                }
                .listStyle(.plain)
                .refreshable { try? await social.loadFriends() }
            }
        }
        .confirmationDialog(
            "删除好友？",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("删除好友", role: .destructive) {
                guard let user = deleting else { return }
                Task {
                    do { try await social.deleteFriend(user) }
                    catch { errorMessage = error.localizedDescription }
                    deleting = nil
                }
            }
        } message: {
            Text("只解除好友关系，历史聊天会继续保留。")
        }
        .alert("操作失败", isPresented: hasError($errorMessage)) {
            Button("知道了", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }
}

private struct SocialContactRow: View {
    let user: SocialUser
    var showsMessage = false
    var showsLastLogin = false

    var body: some View {
        HStack(spacing: 13) {
            ZStack(alignment: .bottomTrailing) {
                SonaAvatarView(
                    username: user.username,
                    avatarPreset: user.avatarPreset,
                    avatarURL: user.avatarURL,
                    size: 52
                )
                Circle()
                    .fill(user.online ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.sonaSurface, lineWidth: 2))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(user.displayName).font(.body.weight(.semibold))
                    if user.isAdmin {
                        Text("管理员")
                            .font(.caption2.bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.sonaGreen, in: Capsule())
                    }
                }
                if showsMessage, let message = user.lastMessage {
                    Text(messagePreview(message))
                        .font(.caption)
                        .foregroundStyle(Color.sonaSecondaryText)
                        .lineLimit(1)
                } else {
                    Text(user.signature.isEmpty ? "@\(user.username)" : user.signature)
                        .font(.caption)
                        .foregroundStyle(Color.sonaSecondaryText)
                        .lineLimit(1)
                }
                if showsLastLogin {
                    Text("上次登录：\(socialDate(user.lastLoginAt))")
                        .font(.caption2)
                        .foregroundStyle(Color.sonaSecondaryText)
                }
            }
            Spacer()
            if let count = user.unreadCount, count > 0 {
                Text("\(min(count, 99))")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Color.red, in: Circle())
            }
        }
        .padding(.vertical, 4)
    }

    private func messagePreview(_ message: SocialMessage) -> String {
        if message.recalledAt != nil { return "消息已撤回" }
        switch message.kind {
        case "STICKER": return "[表情] \(message.text)"
        case "TRACK": return "[歌曲] \(message.payload?.title ?? "分享歌曲")"
        default: return message.text
        }
    }
}

private struct SocialAddFriendView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore
    @State private var query = ""
    @State private var results: [SocialUser] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(results) { user in
                HStack {
                    SocialContactRow(user: user)
                    Button(user.friend == true ? "已添加" : "添加") { add(user) }
                        .buttonStyle(.borderedProminent)
                        .tint(.sonaGreen)
                        .disabled(user.friend == true)
                }
                .listRowBackground(Color.sonaSurface)
            }
            .overlay {
                if isSearching { ProgressView() }
                else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, prompt: "输入账号名或昵称")
            .onSubmit(of: .search) { search() }
            .onChange(of: query) { _, value in
                if value.isEmpty { results = [] }
            }
            .navigationTitle("添加好友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
            .alert("操作失败", isPresented: hasError($errorMessage)) {
                Button("知道了", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func search() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        Task {
            isSearching = true
            defer { isSearching = false }
            do { results = try await social.searchUsers(value) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func add(_ user: SocialUser) {
        Task {
            do {
                try await social.addFriend(username: user.username)
                results = try await social.searchUsers(query)
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

struct SocialChatView: View {
    @EnvironmentObject private var social: SocialStore
    let peer: SocialUser
    @State private var draft = ""
    @State private var showsTrackPicker = false
    @State private var errorMessage: String?

    private var values: [SocialMessage] { social.messages[peer.id] ?? [] }
    private var canSend: Bool { social.friends.contains(where: { $0.id == peer.id }) }

    var body: some View {
        VStack(spacing: 0) {
            if !canSend {
                Text("好友关系已解除，历史聊天保留")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color.orange.opacity(0.12))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(values) { message in
                            SocialMessageBubble(message: message)
                                .id(message.id)
                                .contextMenu {
                                    if message.canRecall {
                                        Button("撤回", systemImage: "arrow.uturn.backward") {
                                            recall(message)
                                        }
                                    }
                                }
                        }
                    }
                    .padding(14)
                }
                .onChange(of: values.count) { _, _ in
                    if let id = values.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    ForEach(["🎵", "❤️", "👏", "✨", "😂", "🥹", "🔥", "👍"], id: \.self) { value in
                        Button(value) { sendSticker(value) }
                    }
                } label: { Image(systemName: "face.smiling") }
                Button { showsTrackPicker = true } label: { Image(systemName: "music.note") }
                TextField(canSend ? "发送消息" : "已解除好友关系", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.sonaSurface, in: RoundedRectangle(cornerRadius: 18))
                Button { sendText() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(!canSend || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .foregroundStyle(Color.sonaGreen)
            .padding(10)
            .background(Color.sonaBackgroundDeep)
            .disabled(!canSend)
        }
        .background(Color.sonaBackground)
        .navigationTitle(peer.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsTrackPicker) { SocialTrackShareView(peerId: peer.id) }
        .task {
            try? await social.loadMessages(with: peer.id)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                try? await social.loadMessages(with: peer.id)
            }
        }
        .alert("消息发送失败", isPresented: hasError($errorMessage)) {
            Button("知道了", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func sendText() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        draft = ""
        Task { do { try await social.sendText(value, to: peer.id) } catch { errorMessage = error.localizedDescription } }
    }

    private func sendSticker(_ value: String) {
        Task { do { try await social.sendSticker(value, to: peer.id) } catch { errorMessage = error.localizedDescription } }
    }

    private func recall(_ message: SocialMessage) {
        Task { do { try await social.recall(message, peerId: peer.id) } catch { errorMessage = error.localizedDescription } }
    }
}

private struct SocialMessageBubble: View {
    let message: SocialMessage

    var body: some View {
        HStack {
            if message.mine { Spacer(minLength: 54) }
            Group {
                if message.recalledAt != nil {
                    Label(
                        message.mine ? "你撤回了一条消息" : "对方撤回了一条消息",
                        systemImage: "arrow.uturn.backward"
                    )
                    .font(.caption)
                    .foregroundStyle(Color.sonaSecondaryText)
                } else if message.kind == "TRACK", let track = message.payload {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("分享歌曲", systemImage: "music.note")
                            .font(.caption.bold())
                            .foregroundStyle(Color.sonaGreen)
                        Text(track.title).font(.body.bold()).lineLimit(1)
                        Text(track.artist).font(.caption).foregroundStyle(Color.sonaSecondaryText)
                    }
                    .frame(maxWidth: 230, alignment: .leading)
                } else {
                    Text(message.text)
                        .font(message.kind == "STICKER" ? .system(size: 34) : .body)
                }
            }
            .padding(message.kind == "STICKER" && message.recalledAt == nil ? 4 : 12)
            .background(
                message.kind == "STICKER" && message.recalledAt == nil
                    ? Color.clear
                    : message.mine ? Color.sonaGreen.opacity(0.9) : Color.sonaSurface,
                in: RoundedRectangle(cornerRadius: 16)
            )
            if !message.mine { Spacer(minLength: 54) }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SocialTrackShareView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var social: SocialStore
    let peerId: String
    @State private var query = ""
    @State private var errorMessage: String?

    private var tracks: [Track] {
        guard !query.isEmpty else { return library.tracks }
        return library.tracks.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.artist.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(tracks) { track in
                Button {
                    Task {
                        do { try await social.share(track: track, with: peerId); dismiss() }
                        catch { errorMessage = error.localizedDescription }
                    }
                } label: { TrackRow(track: track) }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.sonaSurface)
            }
            .searchable(text: $query, prompt: "搜索歌曲")
            .navigationTitle("分享歌曲")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .task { if library.tracks.isEmpty { await library.refresh() } }
            .alert("分享失败", isPresented: hasError($errorMessage)) {
                Button("知道了", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }
}

private struct SocialMomentFeedView: View {
    @EnvironmentObject private var social: SocialStore
    @Binding var showsComposer: Bool

    var body: some View {
        Group {
            if social.moments.isEmpty {
                VStack(spacing: 18) {
                    ContentUnavailableView(
                        "朋友圈还没有内容",
                        systemImage: "camera.aperture",
                        description: Text("发布第一条图片、GIF、实况照片或视频动态。")
                    )
                    Button("发布动态") { showsComposer = true }
                        .buttonStyle(.borderedProminent)
                        .tint(.sonaGreen)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(social.moments) { SocialMomentCard(moment: $0) }
                    }
                    .padding(12)
                }
                .refreshable { try? await social.loadMoments() }
            }
        }
    }
}

private struct SocialMomentCard: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var social: SocialStore
    let moment: SocialMoment
    @State private var comment = ""
    @State private var showsComment = false
    @State private var selectedMedia: SocialMediaSelection?
    @State private var errorMessage: String?

    private var displayedMedia: [SocialMedia] {
        moment.media.filter { !($0.kind == "LIVE_PHOTO" && $0.component == "video") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SonaAvatarView(
                    username: moment.user.username,
                    avatarPreset: moment.user.avatarPreset,
                    avatarURL: moment.user.avatarURL,
                    size: 44
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(moment.user.displayName).font(.subheadline.bold())
                    Text(socialDate(moment.createdAt)).font(.caption2).foregroundStyle(Color.sonaSecondaryText)
                }
                Spacer()
                if moment.user.id == session.currentUser?.id || session.currentUser?.isAdmin == true {
                    Menu {
                        Button("删除动态", systemImage: "trash", role: .destructive) { deleteMoment() }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
            if !moment.text.isEmpty { Text(moment.text).font(.body) }
            if !displayedMedia.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: min(3, displayedMedia.count)), spacing: 4) {
                    ForEach(displayedMedia) { media in
                        SocialMediaTile(media: media)
                            .frame(minHeight: displayedMedia.count == 1 ? 230 : 110)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture { selectedMedia = selection(for: media) }
                    }
                }
            }
            HStack(spacing: 18) {
                Button { like() } label: {
                    Label("\(moment.likes.count)", systemImage: moment.liked ? "heart.fill" : "heart")
                }
                Button { showsComment.toggle() } label: {
                    Label("\(moment.comments.count)", systemImage: "bubble.right")
                }
            }
            .foregroundStyle(moment.liked ? Color.sonaGreen : Color.sonaSecondaryText)
            if !moment.likes.isEmpty {
                Text("♥ " + moment.likes.map(\.displayName).joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(Color.sonaGreen)
            }
            ForEach(moment.comments) { value in
                Text("**\(value.user.displayName)：**\(value.body)").font(.caption)
            }
            if showsComment {
                HStack {
                    TextField("写评论…", text: $comment)
                        .textFieldStyle(.roundedBorder)
                    Button("发送") { sendComment() }
                        .disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(14)
        .background(Color.sonaSurface, in: RoundedRectangle(cornerRadius: 18))
        .sheet(item: $selectedMedia) { SocialMediaViewer(selection: $0) }
        .alert("操作失败", isPresented: hasError($errorMessage)) {
            Button("知道了", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func selection(for media: SocialMedia) -> SocialMediaSelection {
        let motion = media.kind == "LIVE_PHOTO"
            ? moment.media.first { $0.kind == "LIVE_PHOTO" && $0.groupId == media.groupId && $0.component == "video" }
            : nil
        return SocialMediaSelection(media: media, motion: motion)
    }

    private func like() {
        Task { do { try await social.setMomentLiked(moment, liked: !moment.liked) } catch { errorMessage = error.localizedDescription } }
    }

    private func deleteMoment() {
        Task { do { try await social.deleteMoment(moment) } catch { errorMessage = error.localizedDescription } }
    }

    private func sendComment() {
        let value = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        comment = ""
        showsComment = false
        Task { do { try await social.comment(momentId: moment.id, body: value) } catch { errorMessage = error.localizedDescription } }
    }
}

private struct SocialMediaSelection: Identifiable {
    let media: SocialMedia
    let motion: SocialMedia?
    var id: String { media.id }
}

private struct SocialMediaTile: View {
    @EnvironmentObject private var social: SocialStore
    let media: SocialMedia

    var body: some View {
        ZStack {
            if media.kind == "VIDEO" {
                LinearGradient(colors: [.black, .indigo.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "play.fill").font(.title2).foregroundStyle(.white)
            } else if let url = social.resolvedURL(media.url) {
                SocialRemoteAnimatedImage(url: url).scaledToFill()
            }
            if media.kind == "GIF" || media.kind == "LIVE_PHOTO" {
                VStack {
                    HStack {
                        Spacer()
                        Text(media.kind == "GIF" ? "GIF" : "LIVE")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .frame(height: 20)
                            .background(.black.opacity(0.62), in: Capsule())
                            .padding(6)
                    }
                    Spacer()
                }
            }
        }
        .clipped()
    }
}

private struct SocialRemoteAnimatedImage: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable() }
            else { Color.sonaBackground.overlay { ProgressView() } }
        }
        .task(id: url) {
            guard let data = try? await APIClient.shared.data(at: url.absoluteString) else { return }
            image = animatedImage(data: data)
        }
    }

    private func animatedImage(data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return UIImage(data: data) }
        guard CGImageSourceGetCount(source) > 1 else { return UIImage(data: data) }
        var frames: [UIImage] = []
        var duration = 0.0
        for index in 0..<CGImageSourceGetCount(source) {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let values = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = values?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
                ?? gif?[kCGImagePropertyGIFDelayTime] as? Double ?? 0.1
            duration += max(0.02, delay)
            frames.append(UIImage(cgImage: frame))
        }
        return UIImage.animatedImage(with: frames, duration: duration)
    }
}

private struct SocialMediaViewer: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore
    let selection: SocialMediaSelection

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let url = social.resolvedURL(selection.media.url) {
                    if selection.media.kind == "LIVE_PHOTO",
                       let motion = selection.motion,
                       let motionURL = social.resolvedURL(motion.url) {
                        SocialRemoteLivePhoto(
                            photoURL: url,
                            motionURL: motionURL,
                            photoName: selection.media.originalName,
                            motionName: motion.originalName
                        )
                    } else if selection.media.kind == "VIDEO" {
                        SocialVideoPlayer(url: url)
                    } else {
                        SocialRemoteAnimatedImage(url: url).scaledToFit()
                    }
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}

private struct SocialVideoPlayer: View {
    @State private var player: AVPlayer

    init(url: URL) {
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPCookiesKey": cookies])
        _player = State(initialValue: AVPlayer(playerItem: AVPlayerItem(asset: asset)))
    }

    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player.play() }
            .onDisappear { player.pause() }
    }
}

private struct SocialMomentComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore
    @State private var text = ""
    @State private var imageItems: [PhotosPickerItem] = []
    @State private var videoItems: [PhotosPickerItem] = []
    @State private var isPublishing = false
    @State private var progressText = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("记录此刻…", text: $text, axis: .vertical).lineLimit(5...12)
                }
                Section("媒体") {
                    PhotosPicker(
                        selection: $imageItems,
                        maxSelectionCount: 9,
                        matching: .any(of: [.images, .livePhotos])
                    ) {
                        Label("图片 / GIF / 实况照片", systemImage: "photo.on.rectangle.angled")
                    }
                    LabeledContent("已选图片", value: "\(imageItems.count) / 9")
                    PhotosPicker(selection: $videoItems, maxSelectionCount: 3, matching: .videos) {
                        Label("视频", systemImage: "video.fill")
                    }
                    LabeledContent("已选视频", value: "\(videoItems.count) / 3")
                    Text("图片最多 9 张，视频最多 3 个，单个视频最大 1GB。GIF 与实况照片会保留原格式。")
                        .font(.caption)
                        .foregroundStyle(Color.sonaSecondaryText)
                }
                if isPublishing {
                    Section { HStack { ProgressView(); Text(progressText) } }
                }
            }
            .navigationTitle("发布朋友圈")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(isPublishing) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发布") { publish() }
                        .disabled(isPublishing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imageItems.isEmpty && videoItems.isEmpty)
                }
            }
            .alert("发布失败", isPresented: hasError($errorMessage)) {
                Button("知道了", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func publish() {
        Task {
            isPublishing = true
            defer { isPublishing = false }
            do {
                var mediaIds: [String] = []
                for (index, item) in imageItems.enumerated() {
                    progressText = "正在上传第 \(index + 1) / \(imageItems.count) 张图片"
                    let isGIF = item.supportedContentTypes.contains { $0.conforms(to: .gif) }
                    let isLive = item.supportedContentTypes.contains {
                        $0.identifier.localizedCaseInsensitiveContains("live-photo")
                    }
                    if isLive {
                        let groupId = UUID().uuidString
                        let components = try await SocialLivePhotoExporter.files(for: item)
                        defer { components.forEach { try? FileManager.default.removeItem(at: $0.url) } }
                        for component in components {
                            let media = try await social.uploadMedia(
                                fileURL: component.url,
                                filename: component.filename,
                                kind: "LIVE_PHOTO",
                                mimeType: component.mimeType,
                                groupId: groupId,
                                component: component.component
                            )
                            mediaIds.append(media.id)
                        }
                    } else {
                        guard let data = try await item.loadTransferable(type: Data.self) else {
                            throw SocialServiceError(message: "无法读取选中的图片")
                        }
                        let type = item.supportedContentTypes.first(where: { $0.preferredMIMEType != nil })
                        let ext = type?.preferredFilenameExtension ?? (isGIF ? "gif" : "jpg")
                        let media = try await social.uploadMedia(
                            data: data,
                            filename: "moment-\(UUID().uuidString).\(ext)",
                            kind: isGIF ? "GIF" : "IMAGE",
                            mimeType: type?.preferredMIMEType ?? (isGIF ? "image/gif" : "image/jpeg")
                        )
                        mediaIds.append(media.id)
                    }
                }
                for (index, item) in videoItems.enumerated() {
                    progressText = "正在上传第 \(index + 1) / \(videoItems.count) 个视频"
                    guard let file = try await item.loadTransferable(type: SocialPickedVideo.self) else {
                        throw SocialServiceError(message: "无法读取选中的视频")
                    }
                    defer { try? FileManager.default.removeItem(at: file.url) }
                    let size = try file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 1024 * 1024 * 1024 else {
                        throw SocialServiceError(message: "单个视频不能超过 1GB")
                    }
                    let type = item.supportedContentTypes.first(where: { $0.conforms(to: .movie) })
                    let ext = type?.preferredFilenameExtension ?? "mov"
                    let media = try await social.uploadMedia(
                        fileURL: file.url,
                        filename: "moment-\(UUID().uuidString).\(ext)",
                        kind: "VIDEO",
                        mimeType: type?.preferredMIMEType ?? "video/quicktime"
                    )
                    mediaIds.append(media.id)
                }
                progressText = "正在发布"
                try await social.publishMoment(
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    mediaIds: mediaIds
                )
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

private enum SocialLivePhotoExporter {
    struct Component {
        let url: URL
        let filename: String
        let mimeType: String
        let component: String
    }

    static func files(for item: PhotosPickerItem) async throws -> [Component] {
        guard let identifier = item.itemIdentifier else {
            throw SocialServiceError(message: "无法读取实况照片标识")
        }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else {
            throw SocialServiceError(message: "实况照片已不在相册中")
        }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let photo = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto }),
              let motion = resources.first(where: { $0.type == .pairedVideo || $0.type == .fullSizePairedVideo }) else {
            throw SocialServiceError(message: "该照片缺少实况配对视频")
        }
        return [
            try await export(photo, component: "photo"),
            try await export(motion, component: "video"),
        ]
    }

    private static func export(_ resource: PHAssetResource, component: String) async throws -> Component {
        let original = resource.originalFilename.isEmpty ? "live-\(component)" : resource.originalFilename
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("sona-live-\(UUID().uuidString)-\(original)")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(for: resource, toFile: target, options: nil) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        let mime = UTType(resource.uniformTypeIdentifier)?.preferredMIMEType
            ?? (component == "photo" ? "image/heic" : "video/quicktime")
        return Component(url: target, filename: original, mimeType: mime, component: component)
    }
}

private struct SocialRemoteLivePhoto: View {
    let photoURL: URL
    let motionURL: URL
    let photoName: String
    let motionName: String
    @State private var livePhoto: PHLivePhoto?

    var body: some View {
        Group {
            if let livePhoto { SocialLivePhotoPlayer(livePhoto: livePhoto) }
            else { ProgressView().tint(.white) }
        }
        .task(id: "\(photoURL.absoluteString)|\(motionURL.absoluteString)") {
            do {
                let photoFile = try await download(photoURL, name: photoName)
                let motionFile = try await download(motionURL, name: motionName)
                livePhoto = try await requestLivePhoto(resources: [photoFile, motionFile])
            } catch { livePhoto = nil }
        }
    }

    private func download(_ url: URL, name: String) async throws -> URL {
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = true
        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard (response as? HTTPURLResponse).map({ 200..<300 ~= $0.statusCode }) == true else {
            throw SocialServiceError(message: "实况照片下载失败")
        }
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("sona-remote-live-\(UUID().uuidString)-\(URL(fileURLWithPath: name).lastPathComponent)")
        try FileManager.default.moveItem(at: temporary, to: target)
        return target
    }

    private func requestLivePhoto(resources: [URL]) async throws -> PHLivePhoto {
        try await withCheckedThrowingContinuation { continuation in
            let gate = SocialContinuationGate()
            PHLivePhoto.request(
                withResourceFileURLs: resources,
                placeholderImage: nil,
                targetSize: CGSize(width: 1600, height: 1600),
                contentMode: .aspectFit
            ) { value, info in
                guard info[PHLivePhotoInfoIsDegradedKey] as? Bool != true else { return }
                gate.finish {
                    if let value { continuation.resume(returning: value) }
                    else { continuation.resume(throwing: SocialServiceError(message: "实况照片合成失败")) }
                }
            }
        }
    }
}

private final class SocialContinuationGate {
    private let lock = NSLock()
    private var finished = false

    func finish(_ action: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        action()
    }
}

private struct SocialLivePhotoPlayer: UIViewRepresentable {
    let livePhoto: PHLivePhoto

    func makeUIView(context: Context) -> PHLivePhotoView { PHLivePhotoView() }

    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        view.contentMode = .scaleAspectFit
        view.livePhoto = livePhoto
        view.startPlayback(with: .full)
    }
}

private struct SocialProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var session: SessionStore
    @State private var displayName = ""
    @State private var signature = ""
    @State private var preset: AvatarPreset?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("公开资料") {
                    TextField("昵称", text: $displayName)
                    TextField("个性签名", text: $signature, axis: .vertical).lineLimit(2...4)
                }
                Section("社交头像") {
                    Picker("预设头像", selection: $preset) {
                        Text("保持当前头像").tag(AvatarPreset?.none)
                        ForEach(AvatarPreset.allCases) { value in
                            Text("\(value.symbol) \(value.title)").tag(Optional(value))
                        }
                    }
                    Text("自定义图片头像可在个人抽屉的“编辑头像”中上传。")
                        .font(.caption)
                        .foregroundStyle(Color.sonaSecondaryText)
                }
            }
            .navigationTitle("编辑社交资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(isSaving) }
            }
            .onAppear {
                displayName = social.profile?.displayName ?? ""
                signature = social.profile?.signature ?? ""
                preset = AvatarPreset(rawValue: social.profile?.avatarPreset ?? "")
            }
            .alert("保存失败", isPresented: hasError($errorMessage)) {
                Button("知道了", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await social.updateProfile(
                    displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                    signature: signature.trimmingCharacters(in: .whitespacesAndNewlines),
                    avatarPreset: preset?.rawValue
                )
                await session.restore()
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

private func socialDate(_ milliseconds: Int64?) -> String {
    guard let milliseconds else { return "暂无记录" }
    return Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
        .formatted(date: .abbreviated, time: .shortened)
}

private func hasError(_ value: Binding<String?>) -> Binding<Bool> {
    Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
}
