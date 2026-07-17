import SwiftUI

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
                Button("刷新", systemImage: "arrow.clockwise") {
                    Task { await loadTasks(showLoading: true) }
                }
            } else {
                Button("导入歌单", systemImage: "link.badge.plus") {
                    showsPlaylistImport = true
                }
            }
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
        .onDisappear { searchTask?.cancel() }
        .sheet(isPresented: $showsPlaylistImport) {
            PlaylistDownloadImportView { result in
                tasks = result.tasks + tasks.filter { existing in
                    !result.tasks.contains(where: { $0.id == existing.id })
                }
                needsLibraryRefresh = true
                selectedSection = 1
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
            }
        }
    }

    private var searchContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("歌曲、歌手或专辑", text: $query)
                    .foregroundStyle(.black)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { submitSearch() }
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
                                isQueuing: queuedCandidateIDs.contains(candidate.id)
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
                    ForEach(tasks) { task in
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
        guard queuedCandidateIDs.insert(candidate.id).inserted else { return }
        errorMessage = nil
        defer { queuedCandidateIDs.remove(candidate.id) }
        do {
            let task = try await APIClient.shared.queueMusicDownload(candidate)
            tasks.removeAll { $0.id == task.id }
            tasks.insert(task, at: 0)
            needsLibraryRefresh = true
            selectedSection = 1
        } catch {
            errorMessage = error.localizedDescription
        }
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
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                        .foregroundStyle(Color.sonaGreen)
                }
            }
            .buttonStyle(.plain)
            .disabled(isQueuing)
            .accessibilityLabel("下载 \(candidate.title)")
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
