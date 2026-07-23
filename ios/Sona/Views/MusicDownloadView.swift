import SwiftUI
import UIKit

struct MusicDownloadView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var personal: PersonalStore
    @State private var query = ""
    @State private var sources: [DownloadSource] = []
    @State private var candidates: [DownloadCandidate] = []
    @State private var tasks: [MusicDownloadTask] = []
    @State private var queuedCandidateIDs: Set<String> = []
    @State private var selectedSource: String?
    @State private var visibleCandidateCount = 20
    @State private var selectedSection = 0
    @State private var isSearching = false
    @State private var isLoadingOtherSources = false
    @State private var searchGeneration = 0
    @State private var searchTask: Task<Void, Never>?
    @State private var isLoadingTasks = false
    @State private var errorMessage: String?
    @State private var showsPlaylistImport = false
    @State private var needsLibraryRefresh = false
    @State private var showsAddedToast = false
    @State private var addedToastTask: Task<Void, Never>?
    @State private var showsClearTasksConfirmation = false
    @State private var isClearingTasks = false

    private let candidatePageSize = 20

    var body: some View {
        VStack(spacing: 0) {
            Picker("内容", selection: $selectedSection) {
                Text("搜索").tag(0)
                Text("下载任务").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if selectedSection == 0 {
                searchContent
            } else {
                taskContent
            }
        }
        .background(Color.sonaBackground.ignoresSafeArea())
        .navigationTitle("音乐下载")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if selectedSection == 1 {
                Button("清空", systemImage: "trash", role: .destructive) {
                    showsClearTasksConfirmation = true
                }
                .disabled(tasks.isEmpty || isClearingTasks)
                Button("刷新", systemImage: "arrow.clockwise") {
                    Task { await loadTasks(showLoading: true) }
                }
            } else {
                Button("导入歌单", systemImage: "link.badge.plus") {
                    showsPlaylistImport = true
                }
            }
        }
        .confirmationDialog(
            "清空全部下载任务？",
            isPresented: $showsClearTasksConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空下载队列", role: .destructive) {
                Task { await clearTasks() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("等待中和下载中的任务也会取消，已下载入库的音乐不会删除。")
        }
        .task {
            async let sourceRequest: Void = loadSources()
            async let taskRequest: Void = loadTasks(showLoading: true)
            _ = await (sourceRequest, taskRequest)
        }
        .task(id: activeTaskKey) {
            guard tasks.contains(where: { $0.state == .queued || $0.state == .running }) else {
                await refreshLibraryAfterDownloadsIfNeeded()
                return
            }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await loadTasks(showLoading: false)
                if !tasks.contains(where: { $0.state == .queued || $0.state == .running }) {
                    break
                }
            }
        }
        .onDisappear {
            searchTask?.cancel()
            addedToastTask?.cancel()
        }
        .sheet(isPresented: $showsPlaylistImport) {
            PlaylistDownloadImportView { result in
                tasks = result.tasks + tasks.filter { existing in
                    !result.tasks.contains(where: { $0.id == existing.id })
                }
                needsLibraryRefresh = true
                showAddedToast()
            }
        }
        .overlay(alignment: .bottom) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.red.opacity(0.92), in: Capsule())
                    .padding()
                    .onTapGesture { self.errorMessage = nil }
            } else if showsAddedToast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("已添加")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.sonaGreen, in: Capsule())
                .padding()
            }
        }
    }

    private var searchContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                LiveSearchTextField(text: $query, onSubmit: submitSearch)
                    .frame(maxWidth: .infinity, minHeight: 34)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.gray)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: submitSearch) {
                    Text(isSearching ? "重新搜索" : "搜索")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 52, minHeight: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .tint(.sonaGreen)
                .foregroundStyle(.black)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !sources.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                sourceChip(title: "全部", source: nil)
                                ForEach(sources) { source in
                                    sourceChip(title: source.name, source: source.id)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 10)
                    }

                    if isSearching {
                        HStack {
                            Spacer()
                            ProgressView("正在搜索多个来源…")
                                .tint(.sonaGreen)
                            Spacer()
                        }
                        .padding(.top, 70)
                    } else if filteredCandidates.isEmpty && isLoadingOtherSources {
                        HStack {
                            Spacer()
                            ProgressView("正在搜索其他平台…")
                                .tint(.sonaGreen)
                            Spacer()
                        }
                        .padding(.top, 70)
                    } else if filteredCandidates.isEmpty {
                        ContentUnavailableView(
                            candidates.isEmpty ? "搜索你的下一首歌" : "该平台暂无结果",
                            systemImage: "music.note.list",
                            description: Text(
                                candidates.isEmpty
                                    ? "支持咪咕、网易云、QQ、酷我和千千音乐"
                                    : "请选择其他平台或重新搜索"
                            )
                        )
                        .padding(.top, 55)
                    } else {
                        ForEach(visibleCandidates) { candidate in
                            DownloadCandidateRow(
                                candidate: candidate,
                                isQueuing: queuedCandidateIDs.contains(candidate.id),
                                downloadState: downloadState(for: candidate)
                            ) {
                                Task { await queue(candidate) }
                            }
                            Divider().overlay(Color.white.opacity(0.08))
                                .padding(.leading, 84)
                        }
                        if hasMoreCandidates {
                            ProgressView("载入更多音源…")
                                .tint(.sonaGreen)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                            .onAppear { loadNextCandidatePage() }
                        }
                        if isLoadingOtherSources {
                            ProgressView("正在补充其他平台结果…")
                                .tint(.sonaGreen)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private var taskContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isLoadingTasks && tasks.isEmpty {
                    ProgressView("载入下载任务…")
                        .tint(.sonaGreen)
                        .padding(.top, 80)
                } else if tasks.isEmpty {
                    ContentUnavailableView(
                        "还没有下载任务",
                        systemImage: "arrow.down.circle",
                        description: Text("从搜索结果中选择歌曲开始下载")
                    )
                    .padding(.top, 55)
                } else {
                    ForEach(sortedTasks) { task in
                        MusicDownloadTaskRow(task: task) {
                            Task { await retry(task) }
                        }
                        Divider().overlay(Color.white.opacity(0.08))
                            .padding(.leading, 78)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable { await loadTasks(showLoading: false) }
    }

    private var activeTaskKey: String {
        tasks
            .filter { $0.state == .queued || $0.state == .running }
            .map { "\($0.id):\($0.state.rawValue)" }
            .joined(separator: "|")
    }

    private var sortedTasks: [MusicDownloadTask] {
        tasks.sorted { left, right in
            let leftPriority = taskPriority(left.state)
            let rightPriority = taskPriority(right.state)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
            return left.id < right.id
        }
    }

    private func taskPriority(_ state: MusicDownloadState) -> Int {
        switch state {
        case .running: 0
        case .queued: 1
        case .completed, .failed: 2
        }
    }

    private var filteredCandidates: [DownloadCandidate] {
        guard let selectedSource else { return candidates }
        return candidates.filter { $0.source == selectedSource }
    }

    private var visibleCandidates: [DownloadCandidate] {
        Array(filteredCandidates.prefix(visibleCandidateCount))
    }

    private var hasMoreCandidates: Bool {
        visibleCandidateCount < filteredCandidates.count
    }

    private func sourceChip(title: String, source: String?) -> some View {
        let isSelected = selectedSource == source
        return Button {
            selectedSource = source
            visibleCandidateCount = candidatePageSize
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.black : Color.white)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(isSelected ? Color.sonaGreen : Color.sonaChip, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func loadNextCandidatePage() {
        visibleCandidateCount = min(
            visibleCandidateCount + candidatePageSize,
            filteredCandidates.count
        )
    }

    private func loadSources() async {
        do {
            sources = try await APIClient.shared.musicDownloadSources()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitSearch() {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        searchTask?.cancel()
        isSearching = true
        isLoadingOtherSources = false
        errorMessage = nil
        candidates = []
        visibleCandidateCount = candidatePageSize
        searchGeneration += 1
        let generation = searchGeneration
        searchTask = Task { await search(keyword: keyword, generation: generation) }
    }

    private func search(keyword: String, generation: Int) async {
        let sourceIDs = sources.map(\.id)
        let sourceGroups = sourceIDs.isEmpty ? [[]] : sourceIDs.map { [$0] }
        var errors: [String] = []
        isLoadingOtherSources = sourceGroups.count > 1

        await withTaskGroup(of: ([DownloadCandidate], String?).self) { group in
            for sourceGroup in sourceGroups {
                group.addTask {
                    do {
                        let items = try await APIClient.shared.searchMusicDownloads(
                            query: keyword,
                            sources: sourceGroup
                        ).items
                        return (items, nil)
                    } catch {
                        return ([], error.localizedDescription)
                    }
                }
            }
            var completedSourceCount = 0
            for await (result, error) in group {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                guard generation == searchGeneration else {
                    group.cancelAll()
                    return
                }
                completedSourceCount += 1
                isSearching = false
                isLoadingOtherSources = completedSourceCount < sourceGroups.count
                let existingIDs = Set(candidates.map(\.id))
                candidates.append(contentsOf: result.filter { !existingIDs.contains($0.id) })
                if !result.isEmpty {
                    errorMessage = nil
                }
                if let error { errors.append(error) }
            }
        }
        guard generation == searchGeneration else { return }
        isSearching = false
        isLoadingOtherSources = false
        if candidates.isEmpty, let error = errors.first {
            errorMessage = error
        }
    }

    private func queue(_ candidate: DownloadCandidate) async {
        guard downloadState(for: candidate) == nil else { return }
        guard queuedCandidateIDs.insert(candidate.id).inserted else { return }
        errorMessage = nil
        defer { queuedCandidateIDs.remove(candidate.id) }
        do {
            let task = try await APIClient.shared.queueMusicDownload(candidate)
            tasks.removeAll { $0.id == task.id }
            tasks.insert(task, at: 0)
            needsLibraryRefresh = true
            showAddedToast()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func showAddedToast() {
        addedToastTask?.cancel()
        showsAddedToast = true
        addedToastTask = Task {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            showsAddedToast = false
        }
    }

    private func downloadState(for candidate: DownloadCandidate) -> MusicDownloadState? {
        if let task = tasks.first(where: {
            $0.title.localizedCaseInsensitiveCompare(candidate.title) == .orderedSame
                && $0.artist.localizedCaseInsensitiveCompare(candidate.artist) == .orderedSame
        }) {
            return task.state == .failed ? nil : task.state
        }
        return candidate.downloadState
    }

    private func loadTasks(showLoading: Bool) async {
        if showLoading { isLoadingTasks = true }
        defer { if showLoading { isLoadingTasks = false } }
        do {
            tasks = try await APIClient.shared.musicDownloadTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearTasks() async {
        guard !isClearingTasks else { return }
        isClearingTasks = true
        errorMessage = nil
        defer { isClearingTasks = false }
        do {
            try await APIClient.shared.clearMusicDownloadTasks()
            tasks.removeAll()
            candidates.removeAll()
            queuedCandidateIDs.removeAll()
        } catch {
            errorMessage = error.localizedDescription
            await loadTasks(showLoading: false)
        }
    }

    private func retry(_ task: MusicDownloadTask) async {
        do {
            let updated = try await APIClient.shared.retryMusicDownload(taskID: task.id)
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = updated
            }
            needsLibraryRefresh = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshLibraryAfterDownloadsIfNeeded() async {
        guard needsLibraryRefresh else { return }
        needsLibraryRefresh = false
        async let libraryRequest: Void = library.refresh()
        async let personalRequest: Void = personal.refresh()
        _ = await (libraryRequest, personalRequest)
    }
}

struct PlaylistSubscriptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var personal: PersonalStore
    @State private var subscriptions: [PlaylistSubscription] = []
    @State private var syncingIDs: Set<String> = []
    @State private var downloadingMissingIDs: Set<String> = []
    @State private var isLoading = true
    @State private var showsCreate = false
    @State private var renamingSubscription: PlaylistSubscription?
    @State private var inspectingSubscription: PlaylistSubscription?
    @State private var errorMessage: String?
    let changed: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && subscriptions.isEmpty {
                    ProgressView("正在载入订阅…")
                } else if subscriptions.isEmpty {
                    ContentUnavailableView(
                        "还没有在线歌单订阅",
                        systemImage: "link.badge.plus",
                        description: Text("订阅公开歌单后，Sona 会按周期匹配本地曲库。")
                    )
                } else {
                    List {
                        ForEach(subscriptions) { subscription in
                            subscriptionRow(subscription)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        Task { await delete(subscription) }
                                    } label: {
                                        Label("取消订阅", systemImage: "trash")
                                    }
                                    .tint(.red)
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.sonaBackground)
            .navigationTitle("在线歌单订阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("添加", systemImage: "plus") { showsCreate = true }
                }
            }
            .task { await load() }
            .task(id: hasActiveDownloads) {
                await monitorDownloads()
            }
            .refreshable { await load() }
            .sheet(isPresented: $showsCreate) {
                CreatePlaylistSubscriptionView { subscription in
                    subscriptions.removeAll { $0.id == subscription.id }
                    subscriptions.insert(subscription, at: 0)
                    Task { await personal.refreshPlaylists() }
                    changed()
                }
            }
            .sheet(item: $renamingSubscription) { subscription in
                RenamePlaylistSubscriptionView(subscription: subscription) { name in
                    let updated = try await APIClient.shared.renamePlaylistSubscription(
                        id: subscription.id, name: name
                    )
                    if let index = subscriptions.firstIndex(where: { $0.id == updated.id }) {
                        subscriptions[index] = updated
                    }
                    changed()
                }
            }
            .sheet(item: $inspectingSubscription) { subscription in
                PlaylistSubscriptionItemsView(subscription: subscription) { updated in
                    if let index = subscriptions.firstIndex(where: { $0.id == updated.id }) {
                        subscriptions[index] = updated
                    }
                    Task { await personal.refreshPlaylists() }
                    changed()
                }
            }
            .alert("操作失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private func subscriptionRow(_ subscription: PlaylistSubscription) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkView(path: artworkURL(for: subscription), cornerRadius: 6, thumbnailSize: 256)
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(subscription.name).font(.headline)
                        Text("\(poolTitle(subscription.poolType)) · 每 \(subscription.syncIntervalHours) 小时同步")
                            .font(.caption)
                            .foregroundStyle(Color.sonaSecondaryText)
                    }
                    Spacer()
                    Button {
                        renamingSubscription = subscription
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task { await sync(subscription) }
                    } label: {
                        if syncingIDs.contains(subscription.id) {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(syncingIDs.contains(subscription.id))
                }
                Text("共 \(subscription.itemCount) 首 · 已匹配 \(subscription.matchedCount) · 缺少 \(subscription.missingCount)")
                    .font(.subheadline)
                if subscription.lastSyncedAt == nil && subscription.lastError == nil {
                    Label("正在后台首次同步", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(Color.sonaSecondaryText)
                } else if subscription.downloadingCount > 0 {
                    Label(downloadStatus(subscription), systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(Color.sonaGreen)
                } else if subscription.autoDownload {
                    Label("缺少音源时自动下载", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(Color.sonaGreen)
                }
                if let error = subscription.lastError, !error.isEmpty {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                }
                if subscription.missingCount > 0 {
                    Button {
                        Task { await downloadMissing(subscription) }
                    } label: {
                        Label(
                            downloadingMissingIDs.contains(subscription.id)
                                ? "正在添加到下载列表…"
                                : "下载缺少的 \(subscription.missingCount) 首",
                            systemImage: "arrow.down.circle.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.sonaGreen)
                    .disabled(
                        syncingIDs.contains(subscription.id)
                            || downloadingMissingIDs.contains(subscription.id)
                    )
                }
                if (subscription.suggestedCount ?? 0) > 0 {
                    Button {
                        inspectingSubscription = subscription
                    } label: {
                        Label(
                            "确认相似歌曲 \(subscription.suggestedCount ?? 0) 首",
                            systemImage: "questionmark.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.sonaBackground)
        .contextMenu {
            Button("修改名称", systemImage: "pencil") {
                renamingSubscription = subscription
            }
            Button("立即同步", systemImage: "arrow.clockwise") {
                Task { await sync(subscription) }
            }
            Button("取消订阅", systemImage: "link.badge.minus", role: .destructive) {
                Task { await delete(subscription) }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        async let playlistRefresh: Void = personal.refreshPlaylists()
        do {
            subscriptions = try await APIClient.shared.playlistSubscriptions()
        } catch {
            errorMessage = error.localizedDescription
        }
        await playlistRefresh
    }

    private func artworkURL(for subscription: PlaylistSubscription) -> String? {
        guard let playlist = personal.playlists.first(where: {
            $0.id == subscription.playlistId
        }) else { return nil }
        return sonaArtworkPaths(playlist.artworkURLs).first
    }

    private var hasActiveDownloads: Bool {
        subscriptions.contains { $0.downloadingCount > 0 }
    }

    private func monitorDownloads() async {
        guard hasActiveDownloads else { return }
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(2))
                let updated = try await APIClient.shared.playlistSubscriptions()
                let completed = !updated.contains { $0.downloadingCount > 0 }
                subscriptions = updated
                if completed {
                    await personal.refreshPlaylists()
                    changed()
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                continue
            }
        }
    }

    private func sync(_ subscription: PlaylistSubscription) async {
        syncingIDs.insert(subscription.id)
        defer { syncingIDs.remove(subscription.id) }
        do {
            let updated = try await APIClient.shared.syncPlaylistSubscription(id: subscription.id)
            if let index = subscriptions.firstIndex(where: { $0.id == updated.id }) {
                subscriptions[index] = updated
            }
            await personal.refreshPlaylists()
            changed()
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }

    private func downloadMissing(_ subscription: PlaylistSubscription) async {
        downloadingMissingIDs.insert(subscription.id)
        defer { downloadingMissingIDs.remove(subscription.id) }
        do {
            let updated = try await APIClient.shared.downloadMissingPlaylistSubscription(
                id: subscription.id
            )
            if let index = subscriptions.firstIndex(where: { $0.id == updated.id }) {
                subscriptions[index] = updated
            }
            await personal.refreshPlaylists()
            changed()
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }

    private func delete(_ subscription: PlaylistSubscription) async {
        do {
            try await APIClient.shared.deletePlaylistSubscription(id: subscription.id)
            subscriptions.removeAll { $0.id == subscription.id }
            await personal.refreshPlaylists()
            changed()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func poolTitle(_ poolType: String) -> String {
        switch poolType {
        case "DISCOVERY": "发现歌曲池"
        case "CHILD": "儿童歌池"
        default: "正常歌曲池"
        }
    }

    private func downloadStatus(_ subscription: PlaylistSubscription) -> String {
        guard let running = subscription.runningCount,
              let queued = subscription.queuedCount else {
            return "\(subscription.downloadingCount) 首正在下载"
        }
        var parts: [String] = []
        if running > 0 { parts.append("\(running) 首下载中") }
        if queued > 0 { parts.append("\(queued) 首排队中") }
        return parts.joined(separator: " · ")
    }
}

private struct PlaylistSubscriptionItemsView: View {
    @Environment(\.dismiss) private var dismiss
    let subscription: PlaylistSubscription
    let updated: (PlaylistSubscription) -> Void
    @State private var items: [PlaylistSubscriptionItem] = []
    @State private var workingItemKeys: Set<String> = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    ProgressView("正在查找本地候选…")
                } else {
                    List(items) { item in
                        itemRow(item)
                            .listRowBackground(Color.sonaBackground)
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.sonaBackground)
            .navigationTitle("匹配订阅歌曲")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .alert("操作失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    @ViewBuilder
    private func itemRow(_ item: PlaylistSubscriptionItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.headline)
                    Text(item.artist).font(.subheadline).foregroundStyle(Color.sonaSecondaryText)
                }
                Spacer()
                stateLabel(item.state)
            }
            if item.state == "SUGGESTED" {
                ForEach(item.suggestions) { suggestion in
                    Button {
                        Task { await select(suggestion, for: item) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title).foregroundStyle(.primary)
                                Text("\(suggestion.artist) · \(suggestion.durationText)")
                                    .font(.caption)
                                    .foregroundStyle(Color.sonaSecondaryText)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(Color.sonaGreen)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(workingItemKeys.contains(item.itemKey))
                }
                Button(role: .destructive) {
                    Task { await download(item) }
                } label: {
                    Label("都不对，下载原曲", systemImage: "arrow.down.circle")
                }
                .disabled(workingItemKeys.contains(item.itemKey))
            }
        }
        .padding(.vertical, 5)
    }

    private func stateLabel(_ state: String) -> some View {
        let value: (String, Color) = switch state {
        case "MATCHED": ("已匹配", Color.sonaGreen)
        case "SUGGESTED": ("待确认", .orange)
        case "DOWNLOADING": ("下载中", Color.sonaGreen)
        default: ("缺少", Color.sonaSecondaryText)
        }
        return Text(value.0).font(.caption).foregroundStyle(value.1)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await APIClient.shared.playlistSubscriptionItems(id: subscription.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func select(
        _ suggestion: PlaylistSubscriptionMatchSuggestion,
        for item: PlaylistSubscriptionItem
    ) async {
        workingItemKeys.insert(item.itemKey)
        defer { workingItemKeys.remove(item.itemKey) }
        do {
            let subscription = try await APIClient.shared.selectPlaylistSubscriptionMatch(
                id: subscription.id, itemKey: item.itemKey, trackId: suggestion.trackId
            )
            updated(subscription)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func download(_ item: PlaylistSubscriptionItem) async {
        workingItemKeys.insert(item.itemKey)
        defer { workingItemKeys.remove(item.itemKey) }
        do {
            let subscription = try await APIClient.shared.downloadPlaylistSubscriptionItem(
                id: subscription.id, itemKey: item.itemKey
            )
            updated(subscription)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RenamePlaylistSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    let subscription: PlaylistSubscription
    let saved: (String) async throws -> Void
    @State private var name: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(subscription: PlaylistSubscription, saved: @escaping (String) async throws -> Void) {
        self.subscription = subscription
        self.saved = saved
        _name = State(initialValue: subscription.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("歌单名称") {
                    TextField("歌单名称", text: $name)
                }
                Section {
                    Text("只修改 Sona 中的名称，不会修改来源平台的公开歌单。")
                        .font(.caption)
                        .foregroundStyle(Color.sonaSecondaryText)
                }
            }
            .navigationTitle("修改订阅歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(isSaving || normalizedName.isEmpty)
                }
            }
            .alert("修改失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await saved(normalizedName)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CreatePlaylistSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sourceURL = ""
    @State private var name = ""
    @State private var poolType = "NORMAL"
    @State private var autoDownload = false
    @State private var syncIntervalHours = 24
    @State private var isSaving = false
    @State private var errorMessage: String?
    let created: (PlaylistSubscription) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("公开歌单") {
                    TextField("粘贴歌单链接", text: $sourceURL, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("本地歌单名称（可选）", text: $name)
                }
                Section {
                    Picker("歌曲池", selection: $poolType) {
                        Text("正常歌曲池").tag("NORMAL")
                        Text("发现歌曲池").tag("DISCOVERY")
                        Text("儿童歌池").tag("CHILD")
                    }
                    Picker("同步频率", selection: $syncIntervalHours) {
                        Text("每 6 小时").tag(6)
                        Text("每 12 小时").tag(12)
                        Text("每天").tag(24)
                        Text("每 3 天").tag(72)
                    }
                    Toggle("缺少音源时自动下载", isOn: $autoDownload)
                } header: {
                    Text("同步设置")
                } footer: {
                    Text("关闭自动下载时只匹配本地曲库；外部歌单删除歌曲时，只移除歌单关系，不删除本地音频。")
                }
            }
            .navigationTitle("添加歌单订阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("订阅") { Task { await save() } }
                        .disabled(trimmedURL.isEmpty || isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("正在创建订阅…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("订阅失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private var trimmedURL: String {
        sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedName: String? {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let subscription = try await APIClient.shared.createPlaylistSubscription(
                sourceURL: trimmedURL,
                name: trimmedName,
                poolType: poolType,
                autoDownload: autoDownload,
                syncIntervalHours: syncIntervalHours
            )
            created(subscription)
            dismiss()
            Task { await refreshAfterInitialSync(id: subscription.id) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshAfterInitialSync(id: String) async {
        for _ in 0..<60 {
            do {
                try await Task.sleep(for: .seconds(1))
                let subscriptions = try await APIClient.shared.playlistSubscriptions()
                guard let subscription = subscriptions.first(where: { $0.id == id }) else {
                    return
                }
                if subscription.lastSyncedAt != nil || subscription.lastError != nil {
                    created(subscription)
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                continue
            }
        }
    }
}

private struct LiveSearchTextField: UIViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = "歌曲、歌手或专辑"
        textField.textColor = .black
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.returnKeyType = .search
        textField.delegate = context.coordinator
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.parent = self
        if textField.text != text {
            textField.text = text
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: LiveSearchTextField

        init(parent: LiveSearchTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textChanged(textField)
            parent.onSubmit()
            return true
        }
    }
}

private struct PlaylistDownloadImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var preview: DownloadPlaylistPreview?
    @State private var isParsing = false
    @State private var isQueuing = false
    @State private var errorMessage: String?
    let queued: (PlaylistDownloadQueueResponse) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("粘贴歌单链接", text: $url, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    Text("支持咪咕、网易云、QQ、酷我和千千音乐公开歌单")
                        .font(.caption)
                        .foregroundStyle(Color.sonaSecondaryText)
                    Button {
                        Task { await parse() }
                    } label: {
                        if isParsing {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Label("解析并预览", systemImage: "doc.text.magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.sonaGreen)
                    .foregroundStyle(.black)
                    .disabled(trimmedURL.isEmpty || isParsing || isQueuing)
                }
                .padding(16)

                if let preview {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(preview.name).font(.headline)
                            Text("已识别 \(preview.items.count) 首歌曲")
                                .font(.caption)
                                .foregroundStyle(Color.sonaSecondaryText)
                        }
                        Spacer()
                        Button {
                            Task { await queue(preview) }
                        } label: {
                            if isQueuing {
                                ProgressView()
                            } else {
                                Text("全部导入")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.sonaGreen)
                        .foregroundStyle(.black)
                        .disabled(isQueuing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                    List(preview.items) { candidate in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.title).font(.subheadline.weight(.semibold))
                            Text("\(candidate.artist) · \(candidate.sourceName)")
                                .font(.caption)
                                .foregroundStyle(Color.sonaSecondaryText)
                        }
                        .listRowBackground(Color.sonaBackground)
                    }
                    .listStyle(.plain)
                } else {
                    ContentUnavailableView(
                        "等待歌单链接",
                        systemImage: "music.note.list",
                        description: Text("解析完成后可确认曲目，再批量下载并创建同名歌单。")
                    )
                    .frame(maxHeight: .infinity)
                }
            }
            .background(Color.sonaBackground)
            .navigationTitle("歌单链接导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .alert("导入失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parse() async {
        isParsing = true
        errorMessage = nil
        defer { isParsing = false }
        do {
            preview = try await APIClient.shared.previewDownloadPlaylist(url: trimmedURL)
        } catch {
            preview = nil
            errorMessage = error.localizedDescription
        }
    }

    private func queue(_ preview: DownloadPlaylistPreview) async {
        isQueuing = true
        errorMessage = nil
        defer { isQueuing = false }
        do {
            let result = try await APIClient.shared.queueDownloadPlaylist(
                name: preview.name,
                items: preview.items
            )
            queued(result)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DownloadCandidateRow: View {
    let candidate: DownloadCandidate
    let isQueuing: Bool
    let downloadState: MusicDownloadState?
    let queue: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RemoteArtwork(url: candidate.artworkUrl, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text([candidate.artist, candidate.album]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Color.sonaSecondaryText)
                    .lineLimit(1)
                Text([candidate.sourceName, candidate.quality, candidate.fileSizeText, candidate.durationText]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Color.sonaGreen)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(action: queue) {
                if isQueuing {
                    ProgressView().tint(.sonaGreen)
                } else if let downloadState {
                    Image(systemName: downloadState == .completed
                        ? "checkmark.circle.fill"
                        : "clock.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                        .foregroundStyle(Color.sonaGreen)
                }
            }
            .buttonStyle(.plain)
            .disabled(isQueuing || downloadState != nil)
            .accessibilityLabel(downloadState == .completed
                ? "已下载 \(candidate.title)"
                : downloadState != nil
                    ? "已在下载列表 \(candidate.title)"
                    : "下载 \(candidate.title)")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 76)
    }
}

private struct MusicDownloadTaskRow: View {
    let task: MusicDownloadTask
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RemoteArtwork(url: task.artworkUrl, size: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text("\(task.artist) · \(task.sourceName)")
                    .font(.subheadline)
                    .foregroundStyle(Color.sonaSecondaryText)
                    .lineLimit(1)
                if let message = task.message, task.state == .failed {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else if let file = task.files.first {
                    Text(file)
                        .font(.caption)
                        .foregroundStyle(Color.sonaSecondaryText)
                        .lineLimit(1)
                } else {
                    Text(task.quality)
                        .font(.caption)
                        .foregroundStyle(Color.sonaSecondaryText)
                }
            }
            Spacer(minLength: 4)
            statusView
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 72)
    }

    @ViewBuilder
    private var statusView: some View {
        switch task.state {
        case .queued:
            Label(task.state.title, systemImage: "clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        case .running:
            VStack(spacing: 4) {
                ProgressView().tint(.sonaGreen)
                Text(task.state.title).font(.caption2)
            }
        case .completed:
            Label(task.state.title, systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.sonaGreen)
        case .failed:
            Button(action: retry) {
                Label("重试", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }
}

private struct RemoteArtwork: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        CachedRemoteImage(url: url.flatMap(URL.init(string:))) { image in
            Image(uiImage: image).resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Color.sonaSurface
                Image(systemName: "music.note")
                    .foregroundStyle(Color.sonaSecondaryText)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
