import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var personal: PersonalStore
    @State private var query = ""
    @State private var onlineCandidates: [DownloadCandidate] = []
    @State private var queuedCandidateIDs: Set<String> = []
    @State private var candidateStates: [String: MusicDownloadState] = [:]
    @State private var isSearchingOnline = false
    @State private var onlineSearchGeneration = 0
    @State private var searchErrorMessage: String?
    @State private var showsAddedToast = false
    @State private var addedToastTask: Task<Void, Never>?
    let openDrawer: () -> Void

    private struct Category: Identifiable {
        let id: String
        let title: String
        let color: Color
        let tracks: [Track]
    }

    private var username: String {
        session.currentUser?.username ?? "Sona"
    }

    private var filteredTracks: [Track] {
        library.searchResults
    }

    private var categories: [Category] {
        let losslessCodecs = Set(["FLAC", "ALAC", "WAV", "AIFF", "APE"])
        let values = [
            Category(
                id: "lossless",
                title: "无损音乐",
                color: Color(red: 0.82, green: 0.08, blue: 0.48),
                tracks: library.tracks.filter { losslessCodecs.contains($0.codec.uppercased()) }
            ),
            Category(
                id: "lyrics",
                title: "带歌词",
                color: Color(red: 0.02, green: 0.45, blue: 0.36),
                tracks: library.tracks.filter(\.hasLyrics)
            ),
            Category(
                id: "offline",
                title: "离线音乐",
                color: Color(red: 0.45, green: 0.04, blue: 0.90),
                tracks: library.tracks.filter { offline.downloadedIDs.contains($0.id) }
            ),
            Category(
                id: "favorites",
                title: "收藏歌曲",
                color: Color(red: 0.55, green: 0.38, blue: 0.70),
                tracks: personal.favoriteTracks.isEmpty && !personal.favoriteIDs.isEmpty
                    ? library.tracks.filter { personal.favoriteIDs.contains($0.id) }
                    : personal.favoriteTracks
            ),
            Category(
                id: "albums",
                title: "完整专辑",
                color: Color(red: 0.03, green: 0.35, blue: 0.30),
                tracks: library.tracks
            ),
            Category(
                id: "all",
                title: "全部音乐",
                color: Color(red: 0.30, green: 0.42, blue: 0.03),
                tracks: library.tracks
            )
        ]
        return values.filter { !$0.tracks.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sonaBackground.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        header
                        searchField
                        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            discoveryContent
                        } else {
                            resultsContent
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .overlay(alignment: .bottom) {
            if let searchErrorMessage {
                Text(searchErrorMessage)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.red.opacity(0.92), in: Capsule())
                    .padding()
                    .onTapGesture { self.searchErrorMessage = nil }
            } else if showsAddedToast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("已添加到下载任务")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.sonaGreen, in: Capsule())
                .padding()
            }
        }
        .task(id: query) {
            let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
            onlineSearchGeneration += 1
            let generation = onlineSearchGeneration
            onlineCandidates = []
            candidateStates = [:]
            isSearchingOnline = false
            searchErrorMessage = nil
            guard !value.isEmpty else {
                library.clearSearch()
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            await library.search(query: value)
            guard !Task.isCancelled,
                  query.trimmingCharacters(in: .whitespacesAndNewlines) == value,
                  library.searchResults.isEmpty else { return }
            await searchOnline(query: value, generation: generation)
        }
        .onDisappear { addedToastTask?.cancel() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            SonaAvatarButton(username: username, action: openDrawer)
            Text("搜索")
                .font(.system(size: 31, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .semibold))
            TextField("想听什么？", text: $query)
                .font(.system(size: 17, weight: .medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.black.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(.white, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
    }

    private var discoveryContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !categories.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    SonaSectionHeader(title: "发现新内容")
                        .padding(.horizontal, 16)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 14) {
                            ForEach(Array(categories.prefix(4))) { category in
                                NavigationLink {
                                    SonaTrackListView(
                                        collection: collection(for: category),
                                        loadsMoreFromLibrary: category.id == "all"
                                    )
                                } label: {
                                    discoveryCard(category)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    SonaSectionHeader(title: "浏览全部")
                        .padding(.horizontal, 16)
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(categories) { category in
                            NavigationLink {
                                SonaTrackListView(
                                    collection: collection(for: category),
                                    loadsMoreFromLibrary: category.id == "all"
                                )
                            } label: {
                                categoryCard(category)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        if library.isSearching && filteredTracks.isEmpty {
            ProgressView("搜索中…")
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        } else if !filteredTracks.isEmpty {
            localResults
        } else if !onlineCandidates.isEmpty {
            onlineResults
        } else if isSearchingOnline {
            ProgressView("本地未找到，正在搜索网络歌曲…")
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 38))
                Text("没有找到“\(query)”")
                    .font(.headline)
                Text("试试歌曲、艺人或专辑名称")
                    .font(.subheadline)
                    .foregroundStyle(Color.sonaSecondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        }
    }

    private var localResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("歌曲")
                .font(.title2.bold())
                .padding(.horizontal, 16)
            ForEach(filteredTracks) { track in
                TrackRow(
                    track: track,
                    showsOfflineBadge: offline.downloadedIDs.contains(track.id),
                    isFavorite: personal.favoriteIDs.contains(track.id),
                    allowsMoveToTrash: false,
                    showsFavoriteButton: true,
                    favoriteAction: {
                        Task { await personal.toggleFavorite(trackID: track.id) }
                    },
                    addToPlaylists: Array(
                        personal.playlists
                            .filter { !$0.isDirectoryPlaylist }
                            .prefix(10)
                    ),
                    addToPlaylistAction: { playlist in
                        Task {
                            await personal.setTrack(
                                track.id,
                                in: playlist.id,
                                isIncluded: true
                            )
                        }
                    },
                    tapAction: {
                        player.play(
                            track: track,
                            queue: filteredTracks,
                            offlineURLProvider: offline.localURL(for:)
                        )
                    }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .task {
                    await library.loadNextSearchPageIfNeeded(currentTrack: track)
                }
            }
            if library.isLoadingMoreSearch {
                ProgressView("载入更多…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
        }
    }

    private var onlineResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("网络歌曲")
                    .font(.title2.bold())
                Spacer()
                Text("点击下载后自动加入曲库")
                    .font(.caption)
                    .foregroundStyle(Color.sonaSecondaryText)
            }
            .padding(.horizontal, 16)
            ForEach(onlineCandidates) { candidate in
                SearchDownloadCandidateRow(
                    candidate: candidate,
                    isQueuing: queuedCandidateIDs.contains(candidate.id),
                    downloadState: downloadState(for: candidate)
                ) {
                    Task { await queue(candidate) }
                }
            }
            if isSearchingOnline {
                ProgressView("正在补充其他平台结果…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
        }
    }

    private func searchOnline(query: String, generation: Int) async {
        isSearchingOnline = true
        defer {
            if generation == onlineSearchGeneration {
                isSearchingOnline = false
            }
        }
        do {
            let sources = try await APIClient.shared.musicDownloadSources()
            guard generation == onlineSearchGeneration, !Task.isCancelled else { return }
            let sourceGroups = sources.isEmpty ? [[]] : sources.map { [$0.id] }
            var errors: [String] = []

            await withTaskGroup(of: ([DownloadCandidate], String?).self) { group in
                for sourceGroup in sourceGroups {
                    group.addTask {
                        do {
                            let items = try await APIClient.shared.searchMusicDownloads(
                                query: query,
                                sources: sourceGroup,
                                timeout: 30
                            ).items
                            return (items, nil)
                        } catch is CancellationError {
                            return ([], nil)
                        } catch let error as URLError where error.code == .cancelled {
                            return ([], nil)
                        } catch {
                            return ([], error.localizedDescription)
                        }
                    }
                }

                for await (items, error) in group {
                    guard generation == onlineSearchGeneration,
                          !Task.isCancelled,
                          self.query.trimmingCharacters(in: .whitespacesAndNewlines) == query else {
                        group.cancelAll()
                        return
                    }
                    var candidateIDs = Set(onlineCandidates.map(\.id))
                    onlineCandidates.append(contentsOf: items.filter {
                        candidateIDs.insert($0.id).inserted
                    })
                    if !items.isEmpty {
                        searchErrorMessage = nil
                    }
                    if let error { errors.append(error) }
                }
            }
            if onlineCandidates.isEmpty, let error = errors.first {
                searchErrorMessage = error
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            searchErrorMessage = error.localizedDescription
        }
    }

    private func queue(_ candidate: DownloadCandidate) async {
        guard downloadState(for: candidate) == nil else { return }
        guard queuedCandidateIDs.insert(candidate.id).inserted else { return }
        searchErrorMessage = nil
        defer { queuedCandidateIDs.remove(candidate.id) }
        do {
            let task = try await APIClient.shared.queueMusicDownload(candidate)
            candidateStates[candidate.id] = task.state
            showAddedToast()
        } catch {
            searchErrorMessage = error.localizedDescription
        }
    }

    private func downloadState(for candidate: DownloadCandidate) -> MusicDownloadState? {
        if let state = candidateStates[candidate.id] {
            return state
        }
        return candidate.downloadState == .failed ? nil : candidate.downloadState
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

    private func discoveryCard(_ category: Category) -> some View {
        ZStack(alignment: .bottomLeading) {
            category.color
            if let artworkURL = sonaFirstArtworkURL(in: category.tracks) {
                ArtworkView(path: artworkURL, cornerRadius: 6)
                    .frame(width: 138, height: 138)
                    .opacity(0.72)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
            Text("#\(category.title)")
                .font(.headline.bold())
                .foregroundStyle(.white)
                .padding(12)
        }
        .frame(width: 158, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func categoryCard(_ category: Category) -> some View {
        ZStack(alignment: .topLeading) {
            category.color
            Text(category.title)
                .font(.headline.bold())
                .foregroundStyle(.white)
                .padding(12)
                .zIndex(1)
            if let artworkURL = sonaFirstArtworkURL(in: category.tracks) {
                ArtworkView(path: artworkURL, cornerRadius: 5)
                    .frame(width: 78, height: 78)
                    .rotationEffect(.degrees(24))
                    .offset(x: 112, y: 46)
                    .shadow(color: .black.opacity(0.3), radius: 6)
            }
        }
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func collection(for category: Category) -> SonaCollection {
        SonaCollection(
            id: category.id == "favorites" ? "liked-songs" : "category-\(category.id)",
            title: category.title,
            subtitle: "Sona · \(category.tracks.count) 首歌曲",
            artworkURL: sonaFirstArtworkURL(in: category.tracks),
            tracks: category.tracks,
            shape: .square
        )
    }
}

private struct SearchDownloadCandidateRow: View {
    let candidate: DownloadCandidate
    let isQueuing: Bool
    let downloadState: MusicDownloadState?
    let queue: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CachedRemoteImage(url: candidate.artworkUrl.flatMap(URL.init(string:))) { image in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ZStack {
                    Color.sonaSurface
                    Image(systemName: "music.note")
                        .foregroundStyle(Color.sonaSecondaryText)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text([candidate.artist, candidate.album]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(candidate.sourceName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.sonaGreen)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(Color.sonaGreen.opacity(0.12), in: Capsule())
                .lineLimit(1)
            Button(action: queue) {
                if isQueuing {
                    ProgressView()
                        .tint(.sonaGreen)
                } else if let downloadState {
                    Image(systemName: downloadState == .completed
                        ? "checkmark.circle.fill"
                        : "clock.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(Color.sonaGreen)
                }
            }
            .font(.title2)
            .buttonStyle(.plain)
            .disabled(isQueuing || downloadState != nil)
            .accessibilityLabel(downloadState == .completed
                ? "已下载 \(candidate.title)"
                : downloadState != nil
                    ? "已在下载列表 \(candidate.title)"
                    : "下载 \(candidate.title)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(minHeight: 60)
    }
}
