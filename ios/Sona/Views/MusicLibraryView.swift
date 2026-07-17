import SwiftUI

struct MusicLibraryView: View {
    private enum Filter: String, CaseIterable {
        case playlists = "歌单"
        case songs = "歌曲"
        case albums = "专辑"
        case artists = "艺人"
    }

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var personal: PersonalStore
    @State private var selectedFilter: Filter = .playlists
    @State private var showsSearch = false
    @State private var query = ""
    @State private var showsCreatePlaylist = false
    @State private var playlistName = ""
    @State private var selectedSort = "TITLE"
    @State private var selectedGenre: String?
    @State private var selectedCodec: String?
    @State private var selectedMetadata: String?
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
                subtitle: playlist.isDirectoryPlaylist
                    ? "\(playlist.poolType == "DISCOVERY" ? "发现歌曲池" : "正常歌曲池") · Sona"
                    : "歌单 · \(username)",
                artworkURL: playlist.artworkURLs.first,
                artworkURLs: playlist.artworkURLs,
                rotatesArtworkHourly: true,
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
        case .songs:
            values = []
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
                    if !showsSearch {
                        query = ""
                        Task { await library.refresh() }
                    }
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
                .onSubmit { Task { await library.refresh(query: query) } }
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
            Menu {
                sortButton("标题", value: "TITLE")
                sortButton("艺人", value: "ARTIST")
                sortButton("专辑", value: "ALBUM")
                sortButton("最近加入", value: "NEWEST")
            } label: {
                Label(sortTitle, systemImage: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.medium))
            }
            Spacer()
            Menu {
                filterButton("全部格式", codec: nil, metadata: selectedMetadata)
                ForEach(["MP3", "FLAC", "ALAC", "AAC", "WAV"], id: \.self) { codec in
                    filterButton(codec, codec: codec, metadata: selectedMetadata)
                }
                Divider()
                filterButton("全部元数据", codec: selectedCodec, metadata: nil)
                filterButton("待确认", codec: selectedCodec, metadata: "NEEDS_REVIEW")
                filterButton("人工编辑", codec: selectedCodec, metadata: "MANUAL")
                Divider()
                genreFilterButton("全部曲风", genre: nil)
                ForEach(Array(Set(library.tracks.map(\.genre))).sorted(), id: \.self) { genre in
                    genreFilterButton(genre, genre: genre)
                }
            } label: {
                Image(systemName: selectedCodec == nil && selectedMetadata == nil && selectedGenre == nil
                    ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    .font(.title3)
            }
        }
        .padding(.horizontal, 16)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var libraryRows: some View {
        let visibleCollections = collections
        VStack(spacing: 3) {
            if selectedFilter == .songs {
                ForEach(library.tracks) { track in
                    Button {
                        player.play(
                            track: track, queue: library.tracks,
                            offlineURLProvider: offline.localURL(for:)
                        )
                    } label: {
                        TrackRow(
                            track: track,
                            showsOfflineBadge: offline.downloadedIDs.contains(track.id),
                            isFavorite: personal.favoriteIDs.contains(track.id)
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .task { await library.loadNextPageIfNeeded(currentTrack: track) }
                    .contextMenu {
                        Button("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") {
                            player.playNext(track)
                        }
                        Button("添加到播放队列", systemImage: "text.badge.plus") {
                            player.addToQueue(track)
                        }
                    }
                }
            }

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

            if selectedFilter != .songs {
              ForEach(visibleCollections) { collection in
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
                          collection.id == visibleCollections.last?.id else { return }
                    await library.loadNextPage()
                }
                .contextMenu {
                    if selectedFilter == .playlists,
                       personal.playlists.first(where: { $0.id == collection.id })?.isDirectoryPlaylist != true {
                        Button("删除歌单", systemImage: "trash", role: .destructive) {
                            Task { await personal.deletePlaylist(id: collection.id) }
                        }
                    }
                }
              }
            }

            if selectedFilter != .playlists, library.isLoadingMore {
                ProgressView("载入更多…")
                    .padding(.vertical, 18)
            }

            if selectedFilter != .songs && visibleCollections.isEmpty &&
                !(selectedFilter == .playlists && query.isEmpty) {
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

    private var sortTitle: String {
        switch selectedSort {
        case "ARTIST": "艺人"
        case "ALBUM": "专辑"
        case "NEWEST": "最近加入"
        default: "标题"
        }
    }

    private func sortButton(_ title: String, value: String) -> some View {
        Button(title) {
            selectedSort = value
            Task {
                await library.applyFilters(
                    sort: value, genre: selectedGenre, codec: selectedCodec,
                    metadataStatus: selectedMetadata
                )
            }
        }
    }

    private func filterButton(
        _ title: String, codec: String?, metadata: String?
    ) -> some View {
        Button(title) {
            selectedCodec = codec
            selectedMetadata = metadata
            Task {
                await library.applyFilters(
                    sort: selectedSort, genre: selectedGenre, codec: codec,
                    metadataStatus: metadata
                )
            }
        }
    }

    private func genreFilterButton(_ title: String, genre: String?) -> some View {
        Button(title) {
            selectedGenre = genre
            Task {
                await library.applyFilters(
                    sort: selectedSort, genre: genre, codec: selectedCodec,
                    metadataStatus: selectedMetadata
                )
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
    @State private var showsServerDirectoryPicker = false
    @State private var importMessage: String?
    @State private var isImportingServerDirectory = false
    @State private var importProgressMessage = ""
    @State private var loadedTracks: [String: Track] = [:]
    @State private var editingDirectoryPlaylist: Playlist?
    @State private var editingTrack: Track?
    let playlistID: String

    private var playlist: Playlist? {
        personal.playlists.first { $0.id == playlistID }
    }

    private var tracks: [Track] {
        playlist?.trackIDs.compactMap { library.track(id: $0) ?? loadedTracks[$0] } ?? []
    }

    var body: some View {
        ZStack {
            Color.sonaBackground.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 0) {
                    playlistActions
                    ForEach(tracks) { track in
                        HStack {
                            if isSelecting {
                                Image(systemName: selectedIDs.contains(track.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Color.sonaGreen)
                            }
                            TrackRow(
                                track: track,
                                showsOfflineBadge: offline.downloadedIDs.contains(track.id),
                                isFavorite: personal.favoriteIDs.contains(track.id),
                                deleteTitle: playlist?.isDirectoryPlaylist == true ? nil : "从歌单中移除",
                                deleteAction: playlist?.isDirectoryPlaylist == true ? nil : {
                                    Task {
                                        await personal.setTrack(
                                            track.id, in: playlistID, isIncluded: false
                                        )
                                    }
                                },
                                tapAction: {
                                    if isSelecting {
                                        if !selectedIDs.insert(track.id).inserted {
                                            selectedIDs.remove(track.id)
                                        }
                                    } else {
                                        player.play(
                                            track: track,
                                            queue: tracks,
                                            prioritizedQueueTitle: playlist?.name ?? "歌单",
                                            queueContextID: playlistID,
                                            offlineURLProvider: offline.localURL(for:)
                                        )
                                    }
                                }
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .contextMenu {
                            if playlist?.isDirectoryPlaylist == true {
                                if session.currentUser?.isAdmin == true,
                                   track.metadataStatus == "NEEDS_REVIEW" {
                                    Button("编辑歌曲信息", systemImage: "pencil") {
                                        editingTrack = track
                                    }
                                }
                            } else {
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

            if isImportingServerDirectory {
                DirectoryImportProgressOverlay(message: importProgressMessage)
            }
        }
        .navigationTitle(playlist?.name ?? "歌单")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("随机播放", systemImage: "shuffle") {
                    playRandom()
                }
                .disabled(tracks.isEmpty)
            }
        }
        .task { await loadMissingTracks() }
        .sheet(item: $editingDirectoryPlaylist) { playlist in
            DirectoryPlaylistEditor(playlist: playlist) { name, poolType in
                await personal.updateDirectoryPlaylist(
                    id: playlist.id, name: name, poolType: poolType
                )
                await library.refresh()
                loadedTracks = [:]
                await loadMissingTracks()
            }
        }
        .sheet(item: $editingTrack) { track in
            MetadataEditorView(track: track) {
                await library.refresh()
                loadedTracks[track.id] = nil
                await loadMissingTracks()
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            Task { await importLocalFiles(result) }
        }
        .sheet(isPresented: $showsServerDirectoryPicker) {
            ServerDirectoryPicker { directory in
                Task { await importServerDirectory(directory) }
            }
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

    private var playlistActions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    Task { await offline.downloadAll(tracks) }
                } label: {
                    Label("全部离线", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .disabled(tracks.isEmpty)
                if playlist?.isDirectoryPlaylist == true {
                    if session.currentUser?.isAdmin == true, let playlist {
                        Button {
                            editingDirectoryPlaylist = playlist
                        } label: {
                            Label("编辑歌单", systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                        }
                    }
                } else if session.currentUser?.isAdmin == true {
                    Menu {
                        Button("扫描服务器音乐目录", systemImage: "externaldrive") {
                            showsServerDirectoryPicker = true
                        }
                        Button("从 App 本地导入", systemImage: "iphone") {
                            showsImporter = true
                        }
                    } label: {
                        Label("导入音乐", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                }

                if playlist?.isDirectoryPlaylist != true {
                    Button {
                        isSelecting.toggle()
                        if !isSelecting { selectedIDs.removeAll() }
                    } label: {
                        Label(isSelecting ? "完成" : "多选", systemImage: "checklist")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(tracks.isEmpty)
                }
            }
            .buttonStyle(.bordered)

            if playlist?.isDirectoryPlaylist != true, isSelecting, !selectedIDs.isEmpty {
                Button("移除选中的 \(selectedIDs.count) 首", role: .destructive) {
                    let ids = selectedIDs
                    Task {
                        await personal.removeTracks(ids, from: playlistID)
                        selectedIDs.removeAll()
                        isSelecting = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func playRandom() {
        let queue = tracks.shuffled()
        guard let first = queue.first else { return }
        player.play(
            track: first,
            queue: queue,
            prioritizedQueueTitle: playlist?.name ?? "歌单",
            queueContextID: playlistID,
            offlineURLProvider: offline.localURL(for:)
        )
    }

    private func loadMissingTracks() async {
        guard let playlist else { return }
        for id in playlist.trackIDs where library.track(id: id) == nil && loadedTracks[id] == nil {
            if let track = try? await APIClient.shared.track(id: id) {
                loadedTracks[id] = track
            }
        }
    }

    private func importServerDirectory(_ directory: ServerMusicDirectory) async {
        isImportingServerDirectory = true
        importProgressMessage = "正在加入已入库歌曲…"
        defer { isImportingServerDirectory = false }
        do {
            let result = try await APIClient.shared.importPlaylistDirectory(
                playlistID: playlistID,
                directory: directory.path
            )
            await library.refresh()
            await personal.refresh()
            importMessage = result.scanning == true
                ? "“\(directory.name)”已加入歌单 \(result.importedCount) 首，后台正在扫描目录"
                : "“\(directory.name)”已加入歌单 \(result.importedCount) 首"
        } catch {
            importMessage = error.localizedDescription
        }
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
            await personal.refresh()
            importMessage = upload.failed == 0
                ? "已导入 \(upload.succeeded) 首到正常歌曲池"
                : "已导入 \(upload.succeeded) 首，失败 \(upload.failed) 首"
        } catch {
            importMessage = error.localizedDescription
        }
    }
}

private struct DirectoryPlaylistEditor: View {
    @Environment(\.dismiss) private var dismiss
    let playlist: Playlist
    let saved: (String, String) async -> Void
    @State private var name: String
    @State private var poolType: String
    @State private var isSaving = false

    init(playlist: Playlist, saved: @escaping (String, String) async -> Void) {
        self.playlist = playlist
        self.saved = saved
        _name = State(initialValue: playlist.name)
        _poolType = State(initialValue: playlist.poolType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("歌单") {
                    TextField("歌单名称", text: $name)
                    LabeledContent("目录", value: playlist.directoryPath ?? "")
                }
                Section {
                    Picker("歌曲池", selection: $poolType) {
                        Text("正常歌曲池").tag("NORMAL")
                        Text("发现歌曲池").tag("DISCOVERY")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("歌曲池")
                } footer: {
                    Text("修改后，目录内全部歌曲会统一切换到所选歌曲池。")
                }
            }
            .navigationTitle("编辑歌单")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        await saved(name.trimmingCharacters(in: .whitespacesAndNewlines), poolType)
        dismiss()
    }
}

struct ServerDirectoryPicker: View {
    @Environment(\.dismiss) private var dismiss
    let select: (ServerMusicDirectory) -> Void

    var body: some View {
        NavigationStack {
            ServerDirectoryLevel(path: "") { directory in
                dismiss()
                select(directory)
            }
        }
    }
}

private struct ServerDirectoryLevel: View {
    let path: String
    let select: (ServerMusicDirectory) -> Void
    @State private var listing: ServerMusicDirectoryListing?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && listing == nil {
                ProgressView("正在读取服务器目录…")
            } else if let listing {
                List {
                    Section {
                        Button {
                            select(ServerMusicDirectory(
                                path: listing.path,
                                name: listing.name,
                                hasChildren: !listing.directories.isEmpty
                            ))
                        } label: {
                            Label("导入此目录", systemImage: "square.and.arrow.down")
                                .font(.headline)
                                .foregroundStyle(Color.sonaGreen)
                        }
                    } footer: {
                        Text("将扫描此目录及其全部子目录，并把关联歌曲加入当前列表。")
                    }

                    Section("子目录") {
                        if listing.directories.isEmpty {
                            Text("没有子目录")
                                .foregroundStyle(Color.sonaSecondaryText)
                        } else {
                            ForEach(listing.directories) { directory in
                                NavigationLink {
                                    ServerDirectoryLevel(path: directory.path, select: select)
                                } label: {
                                    Label(directory.name, systemImage: "folder.fill")
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            } else {
                ContentUnavailableView(
                    "无法读取目录",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(errorMessage ?? "请稍后重试")
                )
            }
        }
        .background(Color.sonaBackground)
        .navigationTitle(listing?.name ?? "服务器音乐目录")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            listing = try await APIClient.shared.serverMusicDirectories(path: path)
        } catch {
            listing = nil
            errorMessage = error.localizedDescription
        }
    }
}
