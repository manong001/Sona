import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var offline: OfflineStore
    @AppStorage("childMode") private var childMode = false
    @AppStorage("childTheme") private var childTheme = "boy"
    @AppStorage("miniPlayerMode") private var miniPlayerMode = "floating"
    @AppStorage("appIconPreference") private var appIconPreference = "girl"
    @State private var showsImporter = false
    @State private var importMessage: String?
    @State private var appIconError: String?
    @State private var isCheckingUpdate = false
    @State private var releaseInfo: AppReleaseInfo?
    @State private var updateMessage: String?
    @State private var isDownloadingUpdate = false
    @State private var downloadProgress = 0.0
    @State private var downloadedPackage: SharedPackage?
    @State private var importRecords: [ImportRecord] = []
    @State private var downloadTasks: [MusicDownloadTask] = []
    @State private var isLoadingImportRecords = false

    var body: some View {
        NavigationStack {
            Form {
                if session.currentUser?.isAdmin == true {
                    Section("曲库维护") {
                        NavigationLink {
                            TrackManagementView()
                        } label: {
                            Label("歌曲入库与分类", systemImage: "tray.full")
                        }

                        Button("从 App 批量导入", systemImage: "square.and.arrow.down") {
                            showsImporter = true
                        }
                        NavigationLink {
                            MusicDownloadView()
                        } label: {
                            Label("多源音乐下载", systemImage: "arrow.down.circle")
                        }

                        Button {
                            Task { await library.scan() }
                        } label: {
                            Label(
                                library.scanStatus?.state == "RUNNING" ? "正在扫描…" : "扫描并刮削曲库",
                                systemImage: "arrow.clockwise"
                            )
                        }
                        .disabled(library.scanStatus?.state == "RUNNING")

                        if let status = library.scanStatus {
                            LabeledContent("状态", value: stateText(status.state))
                            LabeledContent("发现", value: "\(status.discovered)")
                            LabeledContent("新增 / 更新", value: "\(status.imported) / \(status.updated)")
                            LabeledContent("跳过 / 失败", value: "\(status.skipped) / \(status.failed)")
                            if let message = status.message {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            if let errors = status.errors, !errors.isEmpty {
                                DisclosureGroup("失败文件（\(errors.count)）") {
                                    ForEach(errors, id: \.self) { error in
                                        Text(error).font(.caption).foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("本地数据") {
                    NavigationLink {
                        OfflineManagementView()
                    } label: {
                        Label("离线音乐", systemImage: "arrow.down.circle")
                    }
                    NavigationLink {
                        TrashView()
                    } label: {
                        Label("个人垃圾桶", systemImage: "trash")
                    }
                }

                Section("播放体验") {
                    Picker("迷你播放器", selection: $miniPlayerMode) {
                        Text("悬浮拖动").tag("floating")
                        Text("固定在导航栏上方").tag("fixed")
                    }
                    Toggle("儿童模式", isOn: $childMode)
                    if childMode {
                        Picker("儿童主题", selection: $childTheme) {
                            Text("🚀 星空小勇士").tag("boy")
                            Text("🦄 糖果小公主").tag("girl")
                        }
                    }
                }

                Section("导入记录") {
                    if isLoadingImportRecords && importHistoryItems.isEmpty {
                        HStack {
                            ProgressView()
                            Text("正在加载导入记录…")
                                .foregroundStyle(.secondary)
                        }
                    } else if importHistoryItems.isEmpty {
                        Text("还没有导入记录")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(importHistoryItems) { item in
                            ImportHistoryRow(item: item) {
                                Task { await deleteImportHistoryItem(item) }
                            }
                        }
                    }
                }

                Section("App 图标") {
                    appIconButton(
                        title: "耳机少女",
                        subtitle: "默认",
                        previewName: "AppIconGirl",
                        preference: "girl"
                    )
                    appIconButton(
                        title: "Spotify 原生",
                        subtitle: "经典绿黑图标",
                        previewName: "AppIconSpotify",
                        preference: "spotify"
                    )
                }

                Section("账号") {
                    if let user = session.currentUser {
                        LabeledContent("当前账号", value: user.username)
                        LabeledContent("角色", value: user.isAdmin ? "管理员" : "用户")
                    }
                    NavigationLink("账户安全") {
                        AccountSecurityView()
                    }
                    if session.currentUser?.isAdmin == true {
                        NavigationLink("用户管理") {
                            UserManagementView()
                        }
                    }
                    Button("退出登录", role: .destructive) {
                        Task { await session.logout() }
                    }
                }

                Section("关于") {
                    LabeledContent("应用", value: "Sona")
                    Text("本地标签优先；MusicBrainz、LRCLIB、Cover Art Archive 与多源候选仅补全缺失信息。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("App 更新") {
                    LabeledContent("当前版本", value: "\(currentVersion) (\(currentBuild))")

                    Button("检查更新", systemImage: "arrow.clockwise") {
                        Task { await checkForUpdate() }
                    }
                    .disabled(isCheckingUpdate || isDownloadingUpdate)

                    if isCheckingUpdate {
                        HStack {
                            ProgressView()
                            Text("正在检查服务器版本…")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let release = releaseInfo,
                       release.isNewer(thanVersion: currentVersion, build: currentBuild) {
                        if let version = release.version, let build = release.build {
                            LabeledContent("发现新版本", value: "\(version) (\(build))")
                        }
                        if let fileSize = release.fileSizeText {
                            LabeledContent("安装包大小", value: fileSize)
                        }
                        if let notes = release.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Button("下载并分享 IPA", systemImage: "square.and.arrow.down") {
                            Task { await downloadUpdate(release) }
                        }
                        .disabled(isDownloadingUpdate)
                    }

                    if isDownloadingUpdate {
                        ProgressView(value: downloadProgress)
                        Text("下载进度 \(Int(downloadProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let updateMessage {
                        Text(updateMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.sonaBackground)
            .tint(.sonaGreen)
            .navigationTitle("设置")
            .toolbarBackground(Color.sonaBackground, for: .navigationBar)
            .onAppear {
                appIconPreference = UIApplication.shared.alternateIconName == "SpotifyIcon"
                    ? "spotify" : "girl"
                Task { await loadImportRecords() }
            }
            .task(id: activeImportRecordKey) {
                guard importHistoryItems.contains(where: { $0.isRunning }) else { return }
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(2))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    await loadImportRecords()
                    if !importHistoryItems.contains(where: { $0.isRunning }) { break }
                }
            }
            .fileImporter(
                isPresented: $showsImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                Task { await importLocalFiles(result) }
            }
            .alert("导入结果", isPresented: Binding(
                get: { importMessage != nil }, set: { if !$0 { importMessage = nil } }
            )) { Button("好") { importMessage = nil } } message: { Text(importMessage ?? "") }
            .alert("图标切换失败", isPresented: Binding(
                get: { appIconError != nil }, set: { if !$0 { appIconError = nil } }
            )) { Button("好") { appIconError = nil } } message: { Text(appIconError ?? "") }
            .sheet(item: $downloadedPackage) { package in
                AppShareSheet(items: [package.url])
            }
        }
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
    }

    private var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
    }

    private var importHistoryItems: [ImportHistoryItem] {
        (importRecords.map(ImportHistoryItem.record) + downloadTasks.map(ImportHistoryItem.download))
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var activeImportRecordKey: String {
        importHistoryItems
            .filter(\.isRunning)
            .map(\.id)
            .joined(separator: "|")
    }

    @MainActor
    private func loadImportRecords() async {
        guard !isLoadingImportRecords else { return }
        isLoadingImportRecords = true
        defer { isLoadingImportRecords = false }
        async let recordsRequest = APIClient.shared.importRecords()
        async let tasksRequest = APIClient.shared.musicDownloadTasks()
        do {
            let (records, tasks) = try await (recordsRequest, tasksRequest)
            importRecords = records
            downloadTasks = tasks
        } catch {
            if isCancellation(error) { return }
            importMessage = "加载导入记录失败：\(error.localizedDescription)"
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if Task.isCancelled || error is CancellationError { return true }
        let value = error as NSError
        if value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled {
            return true
        }
        if value.domain == NSPOSIXErrorDomain && value.code == POSIXErrorCode.ECANCELED.rawValue {
            return true
        }
        if value.domain == NSCocoaErrorDomain && value.code == NSUserCancelledError {
            return true
        }
        let message = error.localizedDescription.lowercased()
        return message == "cancelled" || message == "canceled" || message.contains("cancellationerror")
    }

    private func importLocalFiles(_ result: Result<[URL], Error>) async {
        do {
            let urls = try result.get()
            let record = try? await APIClient.shared.createImportRecord(
                type: .localFiles,
                source: "\(urls.count) 个本地文件",
                target: "正常歌曲池",
                total: urls.count
            )
            let upload = await APIClient.shared.uploadTracks(urls: urls)
            guard upload.succeeded > 0 else {
                if let record {
                    let _ = try? await APIClient.shared.updateImportRecord(
                        id: record.id,
                        update: ImportRecordUpdate(
                            state: .failed,
                            succeeded: 0,
                            failed: upload.failed,
                            message: upload.message ?? "文件上传失败"
                        )
                    )
                }
                await loadImportRecords()
                importMessage = upload.message ?? "文件上传失败"
                return
            }
            if let record {
                let _ = try? await APIClient.shared.updateImportRecord(
                    id: record.id,
                    update: ImportRecordUpdate(
                        state: .running,
                        succeeded: upload.succeeded,
                        failed: upload.failed,
                        message: "正在扫描曲库…"
                    )
                )
            }
            await library.scan()
            if let errorMessage = library.errorMessage {
                if let record {
                    let _ = try? await APIClient.shared.updateImportRecord(
                        id: record.id,
                        update: scanRecordUpdate(
                            state: .failed,
                            status: library.scanStatus,
                            succeeded: upload.succeeded,
                            failed: upload.failed + max(library.scanStatus?.failed ?? 0, 1),
                            message: errorMessage
                        )
                    )
                }
                await loadImportRecords()
                importMessage = errorMessage
                return
            }
            if let record {
                let _ = try? await APIClient.shared.updateImportRecord(
                    id: record.id,
                    update: scanRecordUpdate(
                        state: .completed,
                        status: library.scanStatus,
                        succeeded: upload.succeeded,
                        failed: upload.failed,
                        message: upload.failed > 0 ? "部分文件上传失败" : "已完成"
                    )
                )
            }
            await loadImportRecords()
            importMessage = upload.failed == 0
                ? "已导入 \(upload.succeeded) 首到正常歌曲池"
                : "已导入 \(upload.succeeded) 首，失败 \(upload.failed) 首"
        } catch {
            importMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteImportHistoryItem(_ item: ImportHistoryItem) async {
        do {
            switch item {
            case let .record(record):
                try await APIClient.shared.deleteImportRecord(id: record.id)
                importRecords.removeAll { $0.id == record.id }
            case let .download(task):
                try await APIClient.shared.deleteMusicDownloadTask(taskID: task.id)
                downloadTasks.removeAll { $0.id == task.id }
            }
        } catch {
            importMessage = "删除导入记录失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func checkForUpdate() async {
        isCheckingUpdate = true
        releaseInfo = nil
        updateMessage = nil
        do {
            let release = try await APIClient.shared.latestAppRelease()
            releaseInfo = release
            if !release.available {
                updateMessage = "服务器暂未发布安装包"
            } else if !release.isNewer(thanVersion: currentVersion, build: currentBuild) {
                updateMessage = "当前已是最新版本"
            }
        } catch {
            updateMessage = "检查更新失败：\(error.localizedDescription)"
        }
        isCheckingUpdate = false
    }

    @MainActor
    private func downloadUpdate(_ release: AppReleaseInfo) async {
        isDownloadingUpdate = true
        downloadProgress = 0
        updateMessage = nil
        do {
            let packageURL = try await APIClient.shared.downloadAppRelease(release) { value in
                downloadProgress = value
            }
            downloadProgress = 1
            isDownloadingUpdate = false
            downloadedPackage = SharedPackage(url: packageURL)
        } catch {
            isDownloadingUpdate = false
            updateMessage = "下载安装包失败：\(error.localizedDescription)"
        }
    }

    private func appIconButton(
        title: String, subtitle: String, previewName: String, preference: String
    ) -> some View {
        Button {
            setAppIcon(preference)
        } label: {
            HStack(spacing: 14) {
                Image(previewName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if appIconPreference == preference {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.sonaGreen)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!UIApplication.shared.supportsAlternateIcons)
    }

    private func setAppIcon(_ preference: String) {
        guard UIApplication.shared.supportsAlternateIcons else {
            appIconError = "当前设备不支持切换 App 图标。"
            return
        }
        let iconName = preference == "spotify" ? "SpotifyIcon" : nil
        UIApplication.shared.setAlternateIconName(iconName) { error in
            DispatchQueue.main.async {
                if let error {
                    appIconError = error.localizedDescription
                } else {
                    appIconPreference = preference
                }
            }
        }
    }

    private func stateText(_ state: String) -> String {
        switch state {
        case "RUNNING": "运行中"
        case "COMPLETED": "已完成"
        case "FAILED": "失败"
        default: "空闲"
        }
    }
}

private enum ImportHistoryItem: Identifiable {
    case record(ImportRecord)
    case download(MusicDownloadTask)

    var id: String {
        switch self {
        case let .record(record): "record-\(record.id)"
        case let .download(task): "download-\(task.id)"
        }
    }

    var createdAt: Int64 {
        switch self {
        case let .record(record): record.createdAt
        case let .download(task): task.createdAt
        }
    }

    var updatedAt: Int64 {
        switch self {
        case let .record(record): record.updatedAt
        case let .download(task): task.updatedAt
        }
    }

    var isRunning: Bool {
        switch self {
        case let .record(record): record.state == .running
        case let .download(task): task.state == .queued || task.state == .running
        }
    }
}

private struct ImportHistoryRow: View {
    let item: ImportHistoryItem
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(stateTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(stateColor)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(isFailed ? .red : .secondary)
                    .lineLimit(2)
            }
            Text(dateText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if canDelete {
                Button(role: .destructive, action: delete) {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    private var canDelete: Bool {
        if case let .record(record) = item, record.type == .playlistDirectory {
            return true
        }
        return !item.isRunning
    }

    private var title: String {
        switch item {
        case let .record(record): record.type.title
        case .download: "在线音乐下载"
        }
    }

    private var icon: String {
        switch item {
        case let .record(record):
            switch record.type {
            case .localFiles: "square.and.arrow.down"
            case .favoriteDirectory: "heart.fill"
            case .playlistDirectory: "music.note.list"
            }
        case .download: "arrow.down.circle"
        }
    }

    private var stateTitle: String {
        switch item {
        case let .record(record): record.state.title
        case let .download(task): task.state.title
        }
    }

    private var stateColor: Color {
        if isFailed { return .red }
        return item.isRunning ? .orange : .green
    }

    private var isFailed: Bool {
        switch item {
        case let .record(record): record.state == .failed
        case let .download(task): task.state == .failed
        }
    }

    private var detail: String {
        switch item {
        case let .record(record):
            var values = ["\(record.source) → \(record.target)"]
            if record.total > 0 { values.append("总计 \(record.total)") }
            values.append("成功 \(record.succeeded)")
            values.append("失败 \(record.failed)")
            if record.discovered > 0 {
                values.append("扫描：新增 \(record.imported) / 更新 \(record.updated) / 跳过 \(record.skipped)")
            }
            if record.added > 0 { values.append("已加入 \(record.added)") }
            return values.joined(separator: " · ")
        case let .download(task):
            let succeeded = task.state == .completed ? task.files.count : 0
            let failed = task.state == .failed ? 1 : 0
            return "\(task.sourceName) · \(task.title) → 正常歌曲池 · 成功 \(succeeded) · 失败 \(failed)"
        }
    }

    private var message: String? {
        switch item {
        case let .record(record): record.message
        case let .download(task): task.message
        }
    }

    private var dateText: String {
        Date(timeIntervalSince1970: TimeInterval(item.createdAt) / 1_000)
            .formatted(date: .abbreviated, time: .shortened)
    }
}

private struct SharedPackage: Identifiable {
    let id = UUID()
    let url: URL
}

private struct AppShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ viewController: UIActivityViewController, context: Context) {}
}

private struct TrackManagementView: View {
    @State private var tracks: [Track] = []
    @State private var filter = "PENDING"
    @State private var errorMessage: String?
    @State private var editingTrack: Track?

    var body: some View {
        List {
            Picker("歌曲池", selection: $filter) {
                Text("待入库").tag("PENDING")
                Text("正常").tag("NORMAL")
                Text("发现").tag("DISCOVERY")
            }
            .pickerStyle(.segmented)

            ForEach(tracks) { track in
                VStack(alignment: .leading, spacing: 8) {
                    TrackRow(track: track)
                    HStack {
                        Button("编辑元数据", systemImage: "pencil") {
                            editingTrack = track
                        }
                        Menu(track.audienceType == "CHILD" ? "儿童歌曲" : "全年龄") {
                            Button("全年龄") { update(track, pool: filter, audience: "GENERAL") }
                            Button("儿童歌曲") { update(track, pool: filter, audience: "CHILD") }
                        }
                        Spacer()
                        Menu("划入歌曲池") {
                            Button("正常池") { update(track, pool: "NORMAL", audience: track.audienceType) }
                            Button("发现池") { update(track, pool: "DISCOVERY", audience: track.audienceType) }
                            Button("待入库") { update(track, pool: "PENDING", audience: track.audienceType) }
                        }
                    }
                    HStack {
                        Menu("曲风：\(track.genre)") {
                            ForEach(
                                ["流行", "摇滚", "民谣", "电子", "嘻哈", "爵士", "古典", "R&B", "儿童", "未分类"],
                                id: \.self
                            ) { genre in
                                Button(genre) {
                                    update(
                                        track, pool: track.poolType, audience: track.audienceType,
                                        genre: genre
                                    )
                                }
                            }
                        }
                        Spacer()
                        Menu("地区：\(regionTitle(track.region))") {
                            ForEach(
                                [("CN", "中国"), ("KR", "韩国"), ("US", "美国"), ("JP", "日本"), ("OTHER", "其他")],
                                id: \.0
                            ) { region, title in
                                Button(title) {
                                    update(
                                        track, pool: track.poolType, audience: track.audienceType,
                                        region: region
                                    )
                                }
                            }
                        }
                    }
                    .font(.caption)
                }
                .swipeActions {
                    Button("真删除", role: .destructive) { delete(track) }
                }
            }
        }
        .navigationTitle("歌曲入库与分类")
        .onChange(of: filter) { _, _ in Task { await load() } }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editingTrack) { track in
            MetadataEditorView(track: track) {
                editingTrack = nil
                await load()
            }
        }
        .overlay(alignment: .bottom) {
            if let errorMessage { Text(errorMessage).foregroundStyle(.white).padding(8).background(.red, in: Capsule()) }
        }
    }

    private func load() async {
        do { tracks = try await APIClient.shared.managedTracks(poolType: filter) }
        catch { errorMessage = error.localizedDescription }
    }

    private func update(
        _ track: Track, pool: String, audience: String,
        genre: String? = nil, region: String? = nil
    ) {
        Task {
            do {
                _ = try await APIClient.shared.classifyTrack(
                    id: track.id, poolType: pool, audienceType: audience,
                    genre: genre, region: region
                )
                await load()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func regionTitle(_ region: String) -> String {
        switch region {
        case "CN": "中国"
        case "KR": "韩国"
        case "US": "美国"
        case "JP": "日本"
        default: "其他"
        }
    }

    private func delete(_ track: Track) {
        Task {
            do {
                try await APIClient.shared.deleteTrack(id: track.id, isAdmin: true)
                tracks.removeAll { $0.id == track.id }
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct MetadataEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let track: Track
    let saved: () async -> Void
    @State private var title: String
    @State private var artist: String
    @State private var album: String
    @State private var trackNumber: String
    @State private var genre: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(track: Track, saved: @escaping () async -> Void) {
        self.track = track
        self.saved = saved
        _title = State(initialValue: track.title)
        _artist = State(initialValue: track.artist)
        _album = State(initialValue: track.album)
        _trackNumber = State(initialValue: track.trackNumber.map(String.init) ?? "")
        _genre = State(initialValue: track.genre)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基础信息") {
                    TextField("标题", text: $title)
                    TextField("艺人", text: $artist)
                    TextField("专辑", text: $album)
                    TextField("曲号", text: $trackNumber).keyboardType(.numberPad)
                    TextField("曲风", text: $genre)
                }
                Section {
                    Button("清除人工修改并重新刮削", role: .destructive) {
                        Task { await rescrape() }
                    }
                } footer: {
                    Text("只修改 Sona 数据库，不会写入原始音频文件。")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("编辑元数据")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(isSaving || title.isBlank || artist.isBlank || album.isBlank || genre.isBlank)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await APIClient.shared.editTrackMetadata(
                id: track.id, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                artist: artist.trimmingCharacters(in: .whitespacesAndNewlines),
                album: album.trimmingCharacters(in: .whitespacesAndNewlines),
                trackNumber: Int(trackNumber), genre: genre.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            await saved()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func rescrape() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await APIClient.shared.rescrapeTrack(id: track.id)
            await saved()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

private struct OfflineManagementView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var offline: OfflineStore
    @State private var tracks: [Track] = []

    var body: some View {
        List {
            Section {
                LabeledContent("已下载", value: "\(offline.downloadedIDs.count) 首")
                LabeledContent(
                    "占用空间",
                    value: ByteCountFormatter.string(fromByteCount: offline.storageBytes, countStyle: .file)
                )
                if !offline.failedDownloadIDs.isEmpty {
                    Button("重试失败的 \(offline.failedDownloadIDs.count) 首") {
                        let failed = library.tracks.filter { offline.failedDownloadIDs.contains($0.id) }
                        Task { await offline.downloadAll(failed) }
                    }
                }
                Button("清空全部离线音乐", role: .destructive) {
                    offline.removeAll()
                    tracks.removeAll()
                }
                    .disabled(offline.downloadedIDs.isEmpty)
            }
            Section("离线歌曲") {
                ForEach(tracks) { track in
                    TrackRow(track: track, showsOfflineBadge: true)
                        .swipeActions {
                            Button("移除", role: .destructive) {
                                offline.remove(track)
                                tracks.removeAll { $0.id == track.id }
                            }
                        }
                }
            }
        }
        .navigationTitle("离线音乐")
        .task { await loadTracks() }
        .refreshable { await loadTracks() }
    }

    private func loadTracks() async {
        var values = library.tracks.filter { offline.downloadedIDs.contains($0.id) }
        let known = Set(values.map(\.id))
        for id in offline.downloadedIDs.subtracting(known) {
            if let track = try? await APIClient.shared.track(id: id) {
                values.append(track)
            }
        }
        tracks = values.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
}

private struct TrashView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var tracks: [Track] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if tracks.isEmpty {
                ContentUnavailableView("垃圾桶为空", systemImage: "trash")
            }
            ForEach(tracks) { track in
                TrackRow(track: track)
                    .swipeActions {
                        Button("恢复") { Task { await restore(track) } }.tint(.green)
                    }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .navigationTitle("个人垃圾桶")
        .toolbar {
            Button("全部恢复") {
                Task {
                    for track in tracks { try? await APIClient.shared.restoreTrack(id: track.id) }
                    await load()
                    await library.refresh()
                }
            }
            .disabled(tracks.isEmpty)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { tracks = try await APIClient.shared.trashTracks() }
        catch { errorMessage = error.localizedDescription }
    }

    private func restore(_ track: Track) async {
        do {
            try await APIClient.shared.restoreTrack(id: track.id)
            tracks.removeAll { $0.id == track.id }
            await library.refresh()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct AccountSecurityView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""

    var body: some View {
        Form {
            Section("修改密码") {
                SecureField("当前密码", text: $currentPassword)
                    .textContentType(.password)
                SecureField("新密码（至少 8 位）", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("再次输入新密码", text: $confirmation)
                    .textContentType(.newPassword)
                Button("修改密码") {
                    Task {
                        _ = await session.changePassword(
                            currentPassword: currentPassword,
                            newPassword: newPassword
                        )
                    }
                }
                .disabled(
                    session.isSubmitting ||
                    currentPassword.isEmpty ||
                    newPassword.count < 8 ||
                    newPassword != confirmation
                )
            }

            if let message = session.errorMessage {
                Section {
                    Text(message).foregroundStyle(.red)
                }
            }

            Section {
                Button("退出所有设备", role: .destructive) {
                    Task { await session.logoutAll() }
                }
            } footer: {
                Text("修改密码也会使所有已登录设备退出。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.sonaBackground)
        .tint(.sonaGreen)
        .navigationTitle("账户安全")
    }
}

private struct UserManagementView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var users: [ManagedUser] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showsCreate = false
    @State private var newUsername = ""
    @State private var newPassword = ""
    @State private var newRole: UserRole = .user
    @State private var resetUser: ManagedUser?
    @State private var resetPassword = ""
    @State private var deleteUser: ManagedUser?

    var body: some View {
        List {
            if users.isEmpty && isLoading {
                ProgressView("载入用户…")
            } else {
                ForEach(users) { user in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.username).fontWeight(.semibold)
                            if canManage(user) {
                                Menu {
                                    Button(
                                        user.role == .admin ? "设为普通用户" : "设为管理员",
                                        systemImage: user.role == .admin
                                            ? "person.badge.minus"
                                            : "person.badge.key"
                                    ) {
                                        Task {
                                            await setRole(
                                                user,
                                                role: user.role == .admin ? .user : .admin
                                            )
                                        }
                                    }
                                } label: {
                                    Label(user.role.title, systemImage: "chevron.up.chevron.down")
                                        .font(.caption)
                                        .foregroundStyle(Color.sonaGreen)
                                }
                            } else {
                                Text(user.role.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(user.enabled ? "正常" : "已停用")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(user.enabled ? Color.sonaGreen : .secondary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if canManage(user) {
                            Button(user.enabled ? "停用" : "启用") {
                                Task { await setEnabled(user, enabled: !user.enabled) }
                            }
                            .tint(user.enabled ? .orange : .green)
                            Button("删除", role: .destructive) {
                                deleteUser = user
                            }
                        }
                    }
                    .contextMenu {
                        if canManage(user) {
                            Button("重置密码", systemImage: "key") {
                                resetPassword = ""
                                resetUser = user
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.sonaBackground)
        .tint(.sonaGreen)
        .navigationTitle("用户管理")
        .toolbar {
            Button("新建用户", systemImage: "person.badge.plus") {
                newUsername = ""
                newPassword = ""
                newRole = .user
                showsCreate = true
            }
        }
        .refreshable { await loadUsers() }
        .task { await loadUsers() }
        .sheet(isPresented: $showsCreate) {
            NavigationStack {
                Form {
                    Section("账号") {
                        TextField("用户名", text: $newUsername)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("密码（至少 8 位）", text: $newPassword)
                    }
                    Section("角色") {
                        Picker("用户角色", selection: $newRole) {
                            ForEach(UserRole.allCases) { role in
                                Text(role.title).tag(role)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    if let errorMessage {
                        Section {
                            Text(errorMessage).foregroundStyle(.red)
                        }
                    }
                }
                .navigationTitle("新建用户")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showsCreate = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("创建") { Task { await createUser() } }
                            .disabled(newUsername.count < 2 || newPassword.count < 8)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .alert("重置密码", isPresented: resetAlertBinding) {
            SecureField("新密码（至少 8 位）", text: $resetPassword)
            Button("取消", role: .cancel) { resetUser = nil }
            Button("重置") { Task { await performPasswordReset() } }
                .disabled(resetPassword.count < 8)
        } message: {
            Text("该用户的所有设备会退出登录。")
        }
        .confirmationDialog(
            "删除用户 \(deleteUser?.username ?? "")？",
            isPresented: deleteDialogBinding,
            titleVisibility: .visible
        ) {
            Button("删除用户及个人数据", role: .destructive) {
                Task { await performDelete() }
            }
            Button("取消", role: .cancel) { deleteUser = nil }
        }
        .overlay(alignment: .bottom) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .padding(10)
                    .background(.red.opacity(0.9), in: Capsule())
                    .padding()
            }
        }
    }

    private var resetAlertBinding: Binding<Bool> {
        Binding(
            get: { resetUser != nil },
            set: { if !$0 { resetUser = nil } }
        )
    }

    private func canManage(_ user: ManagedUser) -> Bool {
        user.id != session.currentUser?.id
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { deleteUser != nil },
            set: { if !$0 { deleteUser = nil } }
        )
    }

    private func loadUsers() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            users = try await APIClient.shared.users()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createUser() async {
        do {
            users.append(try await APIClient.shared.createUser(
                username: newUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                password: newPassword,
                role: newRole
            ))
            showsCreate = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setEnabled(_ user: ManagedUser, enabled: Bool) async {
        do {
            let updated = try await APIClient.shared.setUserEnabled(id: user.id, enabled: enabled)
            replace(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setRole(_ user: ManagedUser, role: UserRole) async {
        do {
            replace(try await APIClient.shared.setUserRole(id: user.id, role: role))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performPasswordReset() async {
        guard let user = resetUser else { return }
        do {
            try await APIClient.shared.resetPassword(userID: user.id, password: resetPassword)
            resetUser = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performDelete() async {
        guard let user = deleteUser else { return }
        do {
            try await APIClient.shared.deleteUser(id: user.id)
            users.removeAll { $0.id == user.id }
            deleteUser = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replace(_ user: ManagedUser) {
        guard let index = users.firstIndex(where: { $0.id == user.id }) else { return }
        users[index] = user
    }
}
