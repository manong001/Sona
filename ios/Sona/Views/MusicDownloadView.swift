import SwiftUI

struct MusicDownloadView: View {
    @State private var query = ""
    @State private var sources: [DownloadSource] = []
    @State private var candidates: [DownloadCandidate] = []
    @State private var tasks: [MusicDownloadTask] = []
    @State private var queuedCandidateIDs: Set<String> = []
    @State private var selectedSource: String?
    @State private var visibleCandidateCount = 20
    @State private var selectedSection = 0
    @State private var isSearching = false
    @State private var isLoadingTasks = false
    @State private var errorMessage: String?

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
            }
        }
        .task {
            async let sourceRequest: Void = loadSources()
            async let taskRequest: Void = loadTasks(showLoading: true)
            _ = await (sourceRequest, taskRequest)
        }
        .task(id: activeTaskKey) {
            guard tasks.contains(where: { $0.state == .queued || $0.state == .running }) else {
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await loadTasks(showLoading: false)
                if !tasks.contains(where: { $0.state == .queued || $0.state == .running }) {
                    break
                }
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
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.black)
                TextField("歌曲、歌手或专辑", text: $query)
                    .foregroundStyle(.black)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.gray)
                    }
                    .buttonStyle(.plain)
                }
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

    private func search() async {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, !isSearching else { return }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            candidates = try await APIClient.shared.searchMusicDownloads(query: keyword).items
            visibleCandidateCount = candidatePageSize
        } catch {
            errorMessage = error.localizedDescription
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
        AsyncImage(url: url.flatMap { URL(string: $0) }) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Color.sonaSurface
                    Image(systemName: "music.note")
                        .foregroundStyle(Color.sonaSecondaryText)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
