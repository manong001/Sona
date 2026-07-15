import SwiftUI

struct MusicLibraryView: View {
    private enum Filter: String, CaseIterable {
        case playlists = "歌单"
        case albums = "专辑"
        case artists = "艺人"
    }

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var personal: PersonalStore
    @State private var selectedFilter: Filter = .playlists
    @State private var showsSearch = false
    @State private var query = ""
    @State private var showsCreatePlaylist = false
    @State private var playlistName = ""
    let openDrawer: () -> Void

    private var username: String {
        session.currentUser?.username ?? "Sona"
    }

    private var favoriteTracks: [Track] {
        if !personal.favoriteTracks.isEmpty || personal.favoriteIDs.isEmpty {
            return personal.favoriteTracks
        }
        return library.tracks.filter { personal.favoriteIDs.contains($0.id) }
    }

    private var playlistCollections: [SonaCollection] {
        personal.playlists.map { playlist in
            let tracks = playlist.trackIDs.compactMap(library.track(id:))
            return SonaCollection(
                id: playlist.id,
                title: playlist.name,
                subtitle: "歌单 · \(username)",
                artworkURL: tracks.first(where: { $0.artworkURL != nil })?.artworkURL,
                tracks: tracks,
                shape: .square
            )
        }
    }

    private var collections: [SonaCollection] {
        let values: [SonaCollection]
        switch selectedFilter {
        case .playlists:
            values = playlistCollections
        case .albums:
            values = sonaAlbums(from: library.tracks)
        case .artists:
            values = sonaArtists(from: library.tracks)
        }
        guard !query.isEmpty else { return values }
        return values.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sonaBackground.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        header
                        if showsSearch {
                            librarySearchField
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        filterBar
                        sortBar
                        libraryRows
                    }
                    .padding(.bottom, 24)
                }
                .refreshable {
                    await library.refresh()
                    await personal.refresh()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert("新建歌单", isPresented: $showsCreatePlaylist) {
                TextField("歌单名称", text: $playlistName)
                Button("取消", role: .cancel) { }
                Button("创建") {
                    let name = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    Task { await personal.createPlaylist(name: name) }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            SonaAvatarButton(username: username, action: openDrawer)
            Text("音乐库")
                .font(.system(size: 31, weight: .bold))
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsSearch.toggle()
                    if !showsSearch { query = "" }
                }
            } label: {
                Image(systemName: showsSearch ? "xmark" : "magnifyingglass")
                    .font(.system(size: 23, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            Button {
                playlistName = ""
                showsCreatePlaylist = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .regular))
                    .frame(width: 44, height: 44)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var librarySearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
            TextField("搜索你的音乐库", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Color.sonaChip, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases, id: \.self) { filter in
                    SonaFilterPill(title: filter.rawValue, isSelected: selectedFilter == filter) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var sortBar: some View {
        HStack {
            Label("最近播放", systemImage: "arrow.up.arrow.down")
                .font(.subheadline.weight(.medium))
            Spacer()
            Image(systemName: "list.bullet")
                .font(.title3)
        }
        .padding(.horizontal, 16)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var libraryRows: some View {
        VStack(spacing: 3) {
            if selectedFilter == .playlists, query.isEmpty {
                NavigationLink {
                    SonaTrackListView(collection: SonaCollection(
                        id: "liked-songs",
                        title: "收藏的歌曲",
                        subtitle: "歌单 · \(username)",
                        artworkURL: favoriteTracks.first?.artworkURL,
                        tracks: favoriteTracks,
                        shape: .square
                    ))
                } label: {
                    HStack(spacing: 14) {
                        SonaLikedCover()
                            .frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("收藏的歌曲")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.white)
                            Label("歌单 · \(username)", systemImage: "pin.fill")
                                .font(.subheadline)
                                .foregroundStyle(Color.sonaSecondaryText)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 80)
                }
                .buttonStyle(.plain)
            }

            ForEach(collections) { collection in
                NavigationLink {
                    if selectedFilter == .playlists {
                        ManagedPlaylistDetailView(playlistID: collection.id)
                    } else {
                        SonaTrackListView(collection: collection)
                    }
                } label: {
                    libraryRow(collection)
                }
                .buttonStyle(.plain)
                .task {
                    guard selectedFilter != .playlists,
                          collection.id == collections.last?.id else { return }
                    await library.loadNextPage()
                }
                .contextMenu {
                    if selectedFilter == .playlists {
                        Button("删除歌单", systemImage: "trash", role: .destructive) {
                            Task { await personal.deletePlaylist(id: collection.id) }
                        }
                    }
                }
            }

            if selectedFilter != .playlists, library.isLoadingMore {
                ProgressView("载入更多…")
                    .padding(.vertical, 18)
            }

            if collections.isEmpty && !(selectedFilter == .playlists && query.isEmpty) {
                VStack(spacing: 10) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 36))
                    Text(query.isEmpty ? "这里还没有内容" : "没有找到匹配内容")
                        .font(.headline)
                }
                .foregroundStyle(Color.sonaSecondaryText)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            }
        }
    }

    private func libraryRow(_ collection: SonaCollection) -> some View {
        HStack(spacing: 14) {
            SonaCollectionArtwork(collection: collection, size: 64)
            VStack(alignment: .leading, spacing: 5) {
                Text(collection.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(collection.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.sonaSecondaryText)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 80)
        .contentShape(Rectangle())
    }
}

private struct ManagedPlaylistDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var personal: PersonalStore
    @State private var isSelecting = false
    @State private var selectedIDs = Set<String>()
    @State private var showsImporter = false
    @State private var importMessage: String?
    let playlistID: String

    private var playlist: Playlist? {
        personal.playlists.first { $0.id == playlistID }
    }

    private var tracks: [Track] {
        playlist?.trackIDs.compactMap(library.track(id:)) ?? []
    }

    var body: some View {
        ZStack {
            Color.sonaBackground.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(tracks) { track in
                        Button {
                            if isSelecting {
                                if !selectedIDs.insert(track.id).inserted { selectedIDs.remove(track.id) }
                                return
                            }
                            player.play(
                                track: track,
                                queue: tracks,
                                prioritizedQueueTitle: playlist?.name ?? "歌单",
                                queueContextID: playlistID,
                                offlineURLProvider: offline.localURL(for:)
                            )
                        } label: {
                            HStack {
                                if isSelecting {
                                    Image(systemName: selectedIDs.contains(track.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(Color.sonaGreen)
                                }
                                TrackRow(
                                    track: track,
                                    showsOfflineBadge: offline.downloadedIDs.contains(track.id),
                                    isFavorite: personal.favoriteIDs.contains(track.id)
                                )
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("从歌单中移除", systemImage: "minus.circle", role: .destructive) {
                                Task {
                                    await personal.setTrack(track.id, in: playlistID, isIncluded: false)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(playlist?.name ?? "歌单")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if session.currentUser?.isAdmin == true {
                Menu("导入", systemImage: "square.and.arrow.down") {
                    Button("扫描服务器音乐目录", systemImage: "externaldrive") {
                        Task { await importServerDirectory() }
                    }
                    Button("从 App 本地导入", systemImage: "iphone") {
                        showsImporter = true
                    }
                }
            }
            Button(isSelecting ? "完成" : "多选") {
                isSelecting.toggle()
                if !isSelecting { selectedIDs.removeAll() }
            }
            if isSelecting, !selectedIDs.isEmpty {
                Button("移除 \(selectedIDs.count) 首", role: .destructive) {
                    let ids = selectedIDs
                    Task {
                        await personal.removeTracks(ids, from: playlistID)
                        selectedIDs.removeAll()
                        isSelecting = false
                    }
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            Task { await importLocalFiles(result) }
        }
        .alert("导入结果", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("好") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    private func importServerDirectory() async {
        await library.scan()
        await personal.refresh()
        importMessage = library.errorMessage ?? "服务器音乐目录已导入正常歌曲池"
    }

    private func importLocalFiles(_ result: Result<[URL], Error>) async {
        do {
            let urls = try result.get()
            try await APIClient.shared.uploadTracks(urls: urls)
            await library.scan()
            await personal.refresh()
            importMessage = "已导入 \(urls.count) 首到正常歌曲池"
        } catch {
            importMessage = error.localizedDescription
        }
    }
}
