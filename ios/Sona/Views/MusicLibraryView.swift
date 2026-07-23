import PhotosUI
import SwiftUI
import UIKit

struct MusicLibraryView: View {
    private enum Filter: String, CaseIterable {
        case playlists = "歌单"
        case subscriptions = "订阅"
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
    @State private var showsHomePlaylistPicker = false
    @State private var showsPlaylistOrder = false
    @State private var showsCreateSubscription = false
    @State private var showsSubscriptionManager = false
    @State private var subscriptions: [PlaylistSubscription] = []
    @State private var isLoadingSubscriptions = false
    @State private var needsSubscriptionRefresh = false
    @State private var subscriptionErrorMessage: String?
    @State private var playlistName = ""
    @State private var selectedSort = "TITLE"
    @State private var selectedGenre: String?
    @State private var selectedCodec: String?
    @State private var selectedMetadata: String?
    @State private var editingTrack: Track?
    @State private var pendingForceScrapePlaylist: Playlist?
    @State private var isForceScrapingPlaylist = false
    @State private var forceScrapeMessage: String?
    @State private var playlistDeletionErrorMessage: String?
    @State private var movingPlaylistID: String?
    @State private var playlistOrderErrorMessage: String?
    @AppStorage("miniPlayerMode") private var miniPlayerMode = "floating"
    let openDrawer: () -> Void
    var requestedCollectionID: String? = nil
    var libraryNavigationRequestID = 0
    var createPlaylistRequestID = 0
    @State private var navigationPath: [String] = []

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
                subtitle: subscriptionPlaylistIDs.contains(playlist.id)
                    ? "订阅歌单 · \(username)"
                    : playlist.isDirectoryPlaylist
                    ? "\(playlistPoolTitle(playlist.poolType)) · Sona"
                    : "歌单 · \(username)",
                artworkURL: sonaArtworkPaths(playlist.artworkURLs).first
                    ?? sonaFirstArtworkURL(in: tracks),
                artworkURLs: sonaArtworkPaths(playlist.artworkURLs),
                rotatesArtworkHourly: playlist.artworkTrackID == nil,
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
        case .subscriptions:
            values = playlistCollections.filter { subscriptionPlaylistIDs.contains($0.id) }
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

    private var subscriptionPlaylistIDs: Set<String> {
        Set(subscriptions.map(\.playlistId))
    }

    private var isPlaylistFilter: Bool {
        selectedFilter == .playlists || selectedFilter == .subscriptions
    }

    private var libraryBottomPadding: CGFloat {
#if targetEnvironment(macCatalyst)
        24
#else
        miniPlayerMode == "fixed" ? 92 : 24
#endif
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
                    .padding(.bottom, libraryBottomPadding)
                }
                .refreshable {
                    await library.refresh()
                    await loadSubscriptions()
                    await personal.refresh()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await loadSubscriptions()
                await personal.refreshPlaylists()
            }
            .navigationDestination(for: String.self) { collectionID in
                if collectionID == "liked-songs" {
                    SonaTrackListView(collection: SonaCollection(
                        id: "liked-songs",
                        title: "收藏的歌曲",
                        subtitle: "歌单 · \(username)",
                        artworkURL: sonaFirstArtworkURL(in: favoriteTracks),
                        tracks: favoriteTracks,
                        shape: .square
                    ))
                } else {
                    ManagedPlaylistDetailView(playlistID: collectionID)
                        .id(collectionID)
                }
            }
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
        .onChange(of: libraryNavigationRequestID, initial: true) { _, requestID in
            guard requestID > 0, let requestedCollectionID else { return }
            selectedFilter = .playlists
            query = ""
            navigationPath = [requestedCollectionID]
        }
        .onChange(of: createPlaylistRequestID, initial: true) { _, requestID in
            guard requestID > 0 else { return }
            playlistName = ""
            showsCreatePlaylist = true
        }
        .sheet(item: $editingTrack) { track in
            TrackIdentityEditorView(track: track) { updated in
                library.applyTrackUpdate(updated)
                personal.applyTrackUpdate(updated)
            }
            .desktopSheetSize(.standard)
        }
        .sheet(isPresented: $showsHomePlaylistPicker) {
            HomePlaylistSelectionView()
                .environmentObject(personal)
                .desktopSheetSize(.large)
        }
        .sheet(isPresented: $showsPlaylistOrder) {
            PlaylistOrderView()
                .environmentObject(personal)
                .desktopSheetSize(.large)
        }
        .sheet(isPresented: $showsCreateSubscription) {
            CreatePlaylistSubscriptionView { subscription in
                subscriptions.removeAll { $0.id == subscription.id }
                subscriptions.insert(subscription, at: 0)
                Task { await personal.refreshPlaylists() }
            }
            .desktopSheetSize(.standard)
        }
        .sheet(isPresented: $showsSubscriptionManager) {
            PlaylistSubscriptionsView {
                Task {
                    await loadSubscriptions()
                    await personal.refreshPlaylists()
                }
            }
            .desktopSheetSize(.large)
        }
        .confirmationDialog(
            "覆盖信息刮削",
            isPresented: Binding(
                get: { pendingForceScrapePlaylist != nil },
                set: { if !$0 { pendingForceScrapePlaylist = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingForceScrapePlaylist
        ) { playlist in
            Button("覆盖刮削 \(playlist.trackIDs.count) 首歌曲", role: .destructive) {
                Task { await forceRescrape(playlist) }
            }
            Button("取消", role: .cancel) { }
        } message: { playlist in
            Text("将强制覆盖“\(playlist.name)”内所有歌曲的信息，包括人工编辑内容。")
        }
        .alert("歌单刮削", isPresented: Binding(
            get: { forceScrapeMessage != nil },
            set: { if !$0 { forceScrapeMessage = nil } }
        )) {
            Button("好") { forceScrapeMessage = nil }
        } message: {
            Text(forceScrapeMessage ?? "")
        }
        .alert("订阅操作", isPresented: Binding(
            get: { subscriptionErrorMessage != nil },
            set: { if !$0 { subscriptionErrorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(subscriptionErrorMessage ?? "未知错误")
        }
        .alert("删除歌单失败", isPresented: Binding(
            get: { playlistDeletionErrorMessage != nil },
            set: { if !$0 { playlistDeletionErrorMessage = nil } }
        )) {
            Button("好", role: .cancel) { }
        } message: {
            Text(playlistDeletionErrorMessage ?? "未知错误")
        }
        .alert("歌单排序失败", isPresented: Binding(
            get: { playlistOrderErrorMessage != nil },
            set: { if !$0 { playlistOrderErrorMessage = nil } }
        )) {
            Button("好", role: .cancel) { }
        } message: {
            Text(playlistOrderErrorMessage ?? "未知错误")
        }
        .overlay(alignment: .bottom) {
            if isForceScrapingPlaylist {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在覆盖刮削… \(library.scanStatus?.updated ?? 0)/\(library.scanStatus?.discovered ?? 0)")
                }
                .font(.subheadline)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 20)
            }
        }
    }

    private func loadSubscriptions() async {
        guard !isLoadingSubscriptions else {
            needsSubscriptionRefresh = true
            return
        }
        isLoadingSubscriptions = true
        defer { isLoadingSubscriptions = false }
        repeat {
            needsSubscriptionRefresh = false
            subscriptionErrorMessage = nil
            do {
                subscriptions = try await APIClient.shared.playlistSubscriptions()
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                subscriptionErrorMessage = error.localizedDescription
            }
        } while needsSubscriptionRefresh
    }

    private func syncSubscription(_ subscription: PlaylistSubscription) async {
        do {
            let updated = try await APIClient.shared.syncPlaylistSubscription(id: subscription.id)
            if let index = subscriptions.firstIndex(where: { $0.id == updated.id }) {
                subscriptions[index] = updated
            }
            await personal.refreshPlaylists()
        } catch {
            subscriptionErrorMessage = error.localizedDescription
            await loadSubscriptions()
        }
    }

    private func unsubscribe(_ subscription: PlaylistSubscription) async {
        do {
            try await APIClient.shared.deletePlaylistSubscription(id: subscription.id)
            subscriptions.removeAll { $0.id == subscription.id }
            await personal.refreshPlaylists()
        } catch {
            subscriptionErrorMessage = error.localizedDescription
        }
    }

    private func forceRescrape(_ playlist: Playlist) async {
        isForceScrapingPlaylist = true
        defer { isForceScrapingPlaylist = false }
        let succeeded = await library.forceRescrapePlaylist(id: playlist.id)
        if succeeded {
            await personal.refresh()
            let status = library.scanStatus
            forceScrapeMessage = "已处理 \(status?.discovered ?? 0) 首，更新 \(status?.updated ?? 0) 首，失败 \(status?.failed ?? 0) 首。"
        } else {
            forceScrapeMessage = library.errorMessage ?? "歌单覆盖刮削失败"
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
                if selectedFilter == .subscriptions {
                    showsCreateSubscription = true
                } else {
                    playlistName = ""
                    showsCreatePlaylist = true
                }
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
                ForEach(
                    [Filter.playlists, .songs, .albums, .artists], id: \.self
                ) { filter in
                    if filter == .playlists && isPlaylistFilter {
                        playlistSubscriptionFilter
                    } else {
                        SonaFilterPill(title: filter.rawValue, isSelected: selectedFilter == filter) {
                            selectFilter(filter)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var playlistSubscriptionFilter: some View {
        HStack(spacing: 0) {
            joinedFilterButton(
                title: Filter.playlists.rawValue,
                isSelected: isPlaylistFilter
            ) {
                selectFilter(.playlists)
            }
            joinedFilterButton(
                title: Filter.subscriptions.rawValue,
                isSelected: selectedFilter == .subscriptions
            ) {
                selectFilter(.subscriptions)
            }
        }
        .clipShape(Capsule())
    }

    private func joinedFilterButton(
        title: String, isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color.black.opacity(0.86) : .white)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(isSelected ? Color.sonaGreen : Color.sonaChip)
            .buttonStyle(.plain)
    }

    private func selectFilter(_ filter: Filter) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedFilter = filter
        }
    }

    private var sortBar: some View {
        HStack {
            if selectedFilter == .playlists && query.isEmpty {
                Button {
                    showsPlaylistOrder = true
                } label: {
                    Label("自定义排序", systemImage: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.medium))
                }
            } else {
                Menu {
                    sortButton("标题", value: "TITLE")
                    sortButton("艺人", value: "ARTIST")
                    sortButton("专辑", value: "ALBUM")
                    sortButton("最近加入", value: "NEWEST")
                } label: {
                    Label(sortTitle, systemImage: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.medium))
                }
            }
            Spacer()
            if isPlaylistFilter {
                Button {
                    showsHomePlaylistPicker = true
                } label: {
                    Label("首页展示", systemImage: "house")
                        .font(.subheadline.weight(.medium))
                }
            }
            if selectedFilter == .subscriptions {
                Button {
                    showsSubscriptionManager = true
                } label: {
                    Label("管理订阅", systemImage: "link")
                        .font(.subheadline.weight(.medium))
                }
            }
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
        LazyVStack(spacing: 3) {
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
                        if session.currentUser?.isAdmin == true {
                            Button("编辑歌曲名和歌手", systemImage: "pencil") {
                                editingTrack = track
                            }
                        }
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
                        artworkURL: sonaFirstArtworkURL(in: favoriteTracks),
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
                HStack(spacing: 0) {
                    NavigationLink {
                        if isPlaylistFilter {
                            ManagedPlaylistDetailView(playlistID: collection.id)
                        } else {
                            SonaTrackListView(collection: collection)
                        }
                    } label: {
                        libraryRow(collection)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if isPlaylistFilter,
                       let playlist = personal.playlists.first(where: { $0.id == collection.id }),
                       playlist.trackIDs.isEmpty,
                       canDelete(playlist) {
                        Button("删除歌单", systemImage: "trash", role: .destructive) {
                            Task { await deletePlaylist(playlist) }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .frame(width: 52, height: 80)
                    }
                }
                .task {
                    guard !isPlaylistFilter,
                          collection.id == visibleCollections.last?.id else { return }
                    await library.loadNextPage()
                }
                .contextMenu {
                    if isPlaylistFilter,
                       let playlist = personal.playlists.first(where: { $0.id == collection.id }) {
                        Button("移至首位", systemImage: "arrow.up.to.line") {
                            Task { await movePlaylistToFirst(playlist) }
                        }
                        .disabled(
                            personal.playlists.first?.id == playlist.id
                                || movingPlaylistID != nil
                        )
                        if let subscription = subscriptions.first(where: { $0.playlistId == playlist.id }) {
                            Button("立即同步", systemImage: "arrow.clockwise") {
                                Task { await syncSubscription(subscription) }
                            }
                            Button("取消订阅", systemImage: "link.badge.minus", role: .destructive) {
                                Task { await unsubscribe(subscription) }
                            }
                        }
                        if session.currentUser?.isAdmin == true {
                            Button("覆盖信息刮削", systemImage: "arrow.triangle.2.circlepath") {
                                pendingForceScrapePlaylist = playlist
                            }
                            .disabled(isForceScrapingPlaylist || playlist.trackIDs.isEmpty)
                        }
                        if canDelete(playlist) {
                            Button("删除歌单", systemImage: "trash", role: .destructive) {
                                Task { await deletePlaylist(playlist) }
                            }
                        }
                    }
                }
              }
            }

            if !isPlaylistFilter, library.isLoadingMore {
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

    private func canDelete(_ playlist: Playlist) -> Bool {
        guard !subscriptionPlaylistIDs.contains(playlist.id) else { return false }
        return !playlist.isDirectoryPlaylist ||
            (playlist.trackIDs.isEmpty && session.currentUser?.isAdmin == true)
    }

    private func deletePlaylist(_ playlist: Playlist) async {
        guard await personal.deletePlaylist(playlist) else {
            let message = personal.errorMessage ?? "无法删除该歌单"
            playlistDeletionErrorMessage = message == "Directory playlist folder is not empty"
                ? "目录中仍有文件（包括隐藏文件），只有真实空目录可以删除。"
                : message
            return
        }
        playlistDeletionErrorMessage = nil
    }

    private func movePlaylistToFirst(_ playlist: Playlist) async {
        guard movingPlaylistID == nil,
              let index = personal.playlists.firstIndex(where: { $0.id == playlist.id }),
              index > 0 else { return }
        movingPlaylistID = playlist.id
        defer { movingPlaylistID = nil }
        var ids = personal.playlists.map(\.id)
        ids.insert(ids.remove(at: index), at: 0)
        guard await personal.reorderPlaylists(ids: ids) else {
            playlistOrderErrorMessage = personal.errorMessage ?? "请稍后重试"
            return
        }
        playlistOrderErrorMessage = nil
    }
}

struct TrackIdentityEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let track: Track
    let saved: (Track) async -> Void
    @State private var title: String
    @State private var artist: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(track: Track, saved: @escaping (Track) async -> Void) {
        self.track = track
        self.saved = saved
        _title = State(initialValue: track.title)
        _artist = State(initialValue: track.artist)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("歌曲信息") {
                    TextField("歌曲名", text: $title)
                    TextField("歌手名", text: $artist)
                }
                Section {
                    Text("只修改 Sona 中显示的信息，不会写入原始音频文件。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("编辑歌曲")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalDismissButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(isSaving || normalizedTitle.isEmpty || normalizedArtist.isEmpty)
                }
            }
        }
    }

    private var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedArtist: String {
        artist.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let updated = try await APIClient.shared.editTrackMetadata(
                id: track.id,
                title: normalizedTitle,
                artist: normalizedArtist,
                album: track.album,
                trackNumber: track.trackNumber,
                genre: track.genre,
                relatedGenres: track.relatedGenres
            )
            await saved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PlaylistOrderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var personal: PersonalStore
    @State private var orderedIDs: [String] = []
    @State private var editMode: EditMode = .active
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var orderedPlaylists: [Playlist] {
        let playlistsByID = Dictionary(
            uniqueKeysWithValues: personal.playlists.map { ($0.id, $0) }
        )
        return orderedIDs.compactMap { playlistsByID[$0] }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(orderedPlaylists) { playlist in
                    HStack(spacing: 12) {
                        ArtworkView(
                            path: artworkURL(for: playlist),
                            cornerRadius: 5,
                            thumbnailSize: 192
                        )
                        .frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(playlist.name)
                                .font(.body.weight(.medium))
                            Text("\(playlist.trackIDs.count) 首歌曲")
                                .font(.caption)
                                .foregroundStyle(Color.sonaSecondaryText)
                        }
                    }
                    .frame(height: 56)
                }
                .onMove { orderedIDs.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.sonaBackground)
            .environment(\.editMode, $editMode)
            .navigationTitle("歌单排序")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalDismissButton()
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { save() }
                        .disabled(isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("正在保存…")
                        .padding(18)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .onAppear {
            orderedIDs = personal.playlists.map(\.id)
            editMode = .active
        }
        .alert("排序保存失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private func save() {
        isSaving = true
        let ids = orderedIDs
        Task {
            if await personal.reorderPlaylists(ids: ids) {
                dismiss()
            } else {
                errorMessage = personal.errorMessage ?? "请稍后重试"
                isSaving = false
            }
        }
    }

    private func artworkURL(for playlist: Playlist) -> String? {
        sonaArtworkPaths(playlist.artworkURLs).first
            ?? sonaFirstArtworkURL(in: playlist.trackIDs.compactMap(library.track(id:)))
    }
}

private struct ManagedPlaylistDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var personal: PersonalStore
    @AppStorage("miniPlayerMode") private var miniPlayerMode = "floating"
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
    @State private var editingMetadataTrack: Track?
    @State private var playlistHeaderColor = Color(red: 0.08, green: 0.22, blue: 0.16)
    @State private var showsArtworkPicker = false
    @State private var artworkPhotoItem: PhotosPickerItem?
    let playlistID: String

    private var playlist: Playlist? {
        personal.playlists.first { $0.id == playlistID }
    }

    private var tracks: [Track] {
        playlist?.trackIDs.compactMap { library.track(id: $0) ?? loadedTracks[$0] } ?? []
    }

    private var playlistArtworkURL: String? {
        guard let playlist else { return nil }
        return sonaArtworkPaths(playlist.artworkURLs).first
            ?? sonaFirstArtworkURL(in: tracks)
    }

    private var playlistBottomContentMargin: CGFloat {
#if targetEnvironment(macCatalyst)
        24
#else
        miniPlayerMode == "fixed" ? 96 : 24
#endif
    }

    var body: some View {
        ZStack {
            Color.sonaBackground.ignoresSafeArea()
            playlistHeroGradient.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 0) {
                    VStack(spacing: 0) {
                        playlistHero
                        playlistActions
                    }
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
                                moreActionTitle: playlistArtworkActionTitle(for: track),
                                moreActionSystemImage: playlist?.artworkTrackID == track.id
                                    ? "checkmark.circle.fill" : "photo",
                                moreActionDisabled: playlist?.artworkTrackID == track.id,
                                moreAction: playlistArtworkAction(for: track),
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
                            if session.currentUser?.isAdmin == true {
                                Button("编辑歌曲名和歌手", systemImage: "pencil") {
                                    editingTrack = track
                                }
                                if playlist?.isDirectoryPlaylist == true,
                                   track.metadataStatus == "NEEDS_REVIEW" {
                                    Button("编辑完整元数据", systemImage: "slider.horizontal.3") {
                                        editingMetadataTrack = track
                                    }
                                }
                            }
                            if playlist?.isDirectoryPlaylist != true {
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
            .contentMargins(
                .bottom,
                playlistBottomContentMargin,
                for: .scrollContent
            )
            .safeAreaPadding(.top, detailScrollTopPadding)

            #if targetEnvironment(macCatalyst)
            macDetailToolbar
            #endif

            if isImportingServerDirectory {
                DirectoryImportProgressOverlay(message: importProgressMessage)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(detailNavigationBarVisibility, for: .navigationBar)
        .toolbarBackground(detailNavigationBarColor, for: .navigationBar)
        .toolbarBackground(detailNavigationBarBackgroundVisibility, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("随机播放", systemImage: "shuffle") {
                    playRandom()
                }
                .disabled(tracks.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("播放全部", systemImage: "play.fill") {
                    playAll()
                }
                .disabled(tracks.isEmpty)
            }
        }
        .photosPicker(
            isPresented: $showsArtworkPicker,
            selection: $artworkPhotoItem,
            matching: .images
        )
        .onChange(of: artworkPhotoItem) { _, item in
            guard let item else { return }
            Task { await uploadPlaylistArtwork(from: item) }
        }
        .task(id: playlist?.trackIDs) { await loadMissingTracks() }
        .sheet(item: $editingDirectoryPlaylist) { playlist in
            DirectoryPlaylistEditor(playlist: playlist) { name, poolType in
                guard await personal.updateDirectoryPlaylist(
                    playlist, name: name, poolType: poolType
                ) else {
                    return personal.errorMessage ?? "保存失败，请稍后重试"
                }
                await library.refresh()
                loadedTracks = [:]
                await loadMissingTracks()
                return nil
            }
            .desktopSheetSize(.standard)
        }
        .sheet(item: $editingTrack) { track in
            TrackIdentityEditorView(track: track) { updated in
                library.applyTrackUpdate(updated)
                personal.applyTrackUpdate(updated)
                loadedTracks[updated.id] = updated
            }
            .desktopSheetSize(.standard)
        }
        .sheet(item: $editingMetadataTrack) { track in
            MetadataEditorView(track: track) {
                await library.refresh()
                loadedTracks[track.id] = nil
                await loadMissingTracks()
            }
            .desktopSheetSize(.standard)
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
            .desktopSheetSize(.large)
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

    private var playlistHeroGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: detailBackgroundColor(opacity: detailPageGradientTopOpacity), location: 0),
                .init(color: detailBackgroundColor(opacity: 0.62), location: 0.52),
                .init(color: Color.sonaBackground.opacity(0.94), location: 0.84),
                .init(color: Color.sonaBackground, location: 1)
            ]),
            startPoint: .top,
            endPoint: .center
        )
    }

    private var detailPageGradientTopOpacity: Double {
        #if targetEnvironment(macCatalyst)
        0.78
        #else
        0.98
        #endif
    }

    private var detailNavigationBarColor: Color {
        detailBackgroundColor(opacity: detailPageGradientTopOpacity)
    }

    private func detailBackgroundColor(opacity: Double) -> Color {
        #if targetEnvironment(macCatalyst)
        sonaOpaqueBlend(playlistHeaderColor, opacity: opacity)
        #else
        playlistHeaderColor.opacity(opacity)
        #endif
    }

    private var detailNavigationBarBackgroundVisibility: Visibility {
        #if targetEnvironment(macCatalyst)
        .visible
        #else
        .hidden
        #endif
    }

    private var detailNavigationBarVisibility: Visibility {
        #if targetEnvironment(macCatalyst)
        .hidden
        #else
        .visible
        #endif
    }

    private var detailScrollTopPadding: CGFloat {
        #if targetEnvironment(macCatalyst)
        72
        #else
        0
        #endif
    }

    #if targetEnvironment(macCatalyst)
    private var macDetailToolbar: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    macToolbarIcon("chevron.left")
                }
                .accessibilityLabel("返回")

                Spacer()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Spacer()
        }
    }

    private func macToolbarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.title3.bold())
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.black.opacity(0.18), in: Circle())
    }
    #endif

    @ViewBuilder
    private var playlistHero: some View {
        #if targetEnvironment(macCatalyst)
        HStack(alignment: .bottom, spacing: 28) {
            playlistHeroArtwork(size: 210)
            VStack(alignment: .leading, spacing: 10) {
                Text("歌单")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))
                Text(playlist?.name ?? "歌单")
                    .font(.system(size: 42, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                playlistHeroMetadata
            }
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 22)
        #else
        VStack(alignment: .leading, spacing: 14) {
            playlistHeroArtwork(size: 280)
                .frame(maxWidth: .infinity)
            Text(playlist?.name ?? "歌单")
                .font(.title.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.78)
            playlistHeroMetadata
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        #endif
    }

    private func playlistHeroArtwork(size: CGFloat) -> some View {
        ArtworkView(
            path: playlistArtworkURL,
            cornerRadius: 6,
            thumbnailSize: 768,
            onColorResolved: { playlistHeaderColor = $0 }
        )
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.36), radius: 18, y: 9)
    }

    private var playlistHeroMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.sonaGreen)
                Text(session.currentUser?.username ?? "Sona")
                    .font(.subheadline.weight(.semibold))
            }
            Text("\(playlist?.trackIDs.count ?? 0) 首歌曲")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))
        }
    }

    private var playlistActions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if canEditPlaylistArtwork {
                    playlistArtworkMenu
                }

                Button {
                    Task { await offline.downloadAll(tracks) }
                } label: {
                    Label("全部离线", systemImage: "arrow.down.circle")
                        .frame(width: 24)
                }
                .disabled(tracks.isEmpty)
                if playlist?.isDirectoryPlaylist == true {
                    if session.currentUser?.isAdmin == true, let playlist {
                        Button {
                            editingDirectoryPlaylist = playlist
                        } label: {
                            Label("编辑歌单", systemImage: "pencil")
                                .frame(width: 24)
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
                            .frame(width: 24)
                    }
                }

                if playlist?.isDirectoryPlaylist != true {
                    Button {
                        isSelecting.toggle()
                        if !isSelecting { selectedIDs.removeAll() }
                    } label: {
                        Label(
                            isSelecting ? "完成" : "多选",
                            systemImage: isSelecting ? "checkmark" : "checklist"
                        )
                            .frame(width: 24)
                    }
                    .disabled(tracks.isEmpty)
                }

                Spacer(minLength: 0)

                #if targetEnvironment(macCatalyst)
                playlistPlaybackActions
                #endif
            }
            .buttonStyle(.bordered)
            .labelStyle(.iconOnly)

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

    #if targetEnvironment(macCatalyst)
    private var playlistPlaybackActions: some View {
        HStack(spacing: 10) {
            Button {
                playRandom()
            } label: {
                Image(systemName: "shuffle")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .accessibilityLabel("随机播放")
            .disabled(tracks.isEmpty)

            Button {
                playAll()
            } label: {
                Image(systemName: "play.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.black)
                    .frame(width: 46, height: 46)
                    .background(Color.sonaGreen, in: Circle())
            }
            .accessibilityLabel("播放全部")
            .disabled(tracks.isEmpty)
        }
        .buttonStyle(.plain)
    }
    #endif

    private var canEditPlaylistArtwork: Bool {
        guard let playlist else { return false }
        return session.currentUser?.isAdmin == true ||
            (!playlist.featured && !playlist.isDirectoryPlaylist)
    }

    private var playlistArtworkMenu: some View {
        Menu {
            Button("上传图片", systemImage: "photo.badge.plus") {
                showsArtworkPicker = true
            }
            Label("也可从歌曲右侧菜单指定", systemImage: "music.note")
            if playlist?.sourceArtworkURL != nil {
                Divider()
                Button("使用源订阅封面", systemImage: "photo.on.rectangle") {
                    Task { await personal.useSourcePlaylistArtwork(playlistID: playlistID) }
                }
            }
            if playlist?.artworkTrackID != nil {
                Divider()
                Button("恢复自动轮换", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await personal.clearPlaylistArtwork(playlistID: playlistID) }
                }
            }
        } label: {
            Label("设置歌单封面", systemImage: "photo")
                .frame(width: 24)
        }
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

    private func playAll() {
        guard let first = tracks.first else { return }
        player.play(
            track: first,
            queue: tracks,
            prioritizedQueueTitle: playlist?.name ?? "歌单",
            queueContextID: playlistID,
            offlineURLProvider: offline.localURL(for:)
        )
    }

    private func playlistArtworkActionTitle(for track: Track) -> String? {
        guard canEditPlaylistArtwork,
              track.artworkURL != nil else { return nil }
        return playlist?.artworkTrackID == track.id ? "当前歌单封面" : "用此歌曲图片作为封面"
    }

    private func playlistArtworkAction(for track: Track) -> (() -> Void)? {
        guard canEditPlaylistArtwork,
              let playlist,
              track.artworkURL != nil else { return nil }
        return {
            guard playlist.artworkTrackID != track.id else { return }
            Task {
                await personal.setPlaylistArtwork(
                    playlistID: playlist.id,
                    trackID: track.id
                )
            }
        }
    }

    private func uploadPlaylistArtwork(from item: PhotosPickerItem) async {
        defer { artworkPhotoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let jpeg = playlistArtworkJPEGData(data) else { return }
        await personal.uploadPlaylistArtwork(playlistID: playlistID, imageData: jpeg)
    }

    private func playlistArtworkJPEGData(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, 1600 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let normalized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return normalized.jpegData(compressionQuality: 0.86)
    }

    private func loadMissingTracks() async {
        guard let playlist else { return }
        let missingIDs = playlist.trackIDs.filter {
            library.track(id: $0) == nil && loadedTracks[$0] == nil
        }
        guard !missingIDs.isEmpty,
              let loaded = try? await APIClient.shared.tracks(ids: missingIDs) else { return }
        var updated = loadedTracks
        loaded.forEach { updated[$0.id] = $0 }
        loadedTracks = updated
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
    let saved: (String, String) async -> String?
    @State private var name: String
    @State private var poolType: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(playlist: Playlist, saved: @escaping (String, String) async -> String?) {
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
                        Text("儿童歌池").tag("CHILD")
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
                    ModalDismissButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .alert(
            "保存歌单失败",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "保存失败，请稍后重试")
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        if let error = await saved(
            name.trimmingCharacters(in: .whitespacesAndNewlines), poolType
        ) {
            errorMessage = error
            return
        }
        dismiss()
    }
}

private func playlistPoolTitle(_ poolType: String) -> String {
    switch poolType {
    case "DISCOVERY": "发现歌曲池"
    case "CHILD": "儿童歌池"
    default: "正常歌曲池"
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

private struct HomePlaylistSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var personal: PersonalStore
    @State private var updatingIDs: Set<String> = []
    @State private var orderedSelectedIDs: [String] = []
    @State private var editMode: EditMode = .active
    @State private var errorMessage: String?

    private var unselectedPlaylists: [Playlist] {
        personal.playlists.filter { !$0.shownOnHome }
    }

    var body: some View {
        NavigationStack {
            List {
                if !orderedSelectedIDs.isEmpty {
                    Section("已选择 · 拖动排序") {
                        ForEach(orderedSelectedIDs, id: \.self) { id in
                            homeItemRow(id)
                        }
                        .onMove(perform: moveSelectedPlaylists)
                    }
                }
                Section {
                    if !personal.favoritesShownOnHome {
                        likedSongsRow
                    }
                    ForEach(unselectedPlaylists) { playlist in
                        playlistRow(playlist)
                    }
                } footer: {
                    Text("只有勾选的歌单会展示在当前用户的首页。")
                }
            }
            .environment(\.editMode, $editMode)
            .onAppear(perform: syncSelectedOrder)
            .task {
                if personal.playlists.isEmpty {
                    await personal.refreshPlaylists()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.sonaBackground)
            .navigationTitle("首页展示")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
#if targetEnvironment(macCatalyst)
                ToolbarItem(placement: .cancellationAction) {
                    ModalDismissButton("完成")
                }
#else
                ToolbarItem(placement: .confirmationAction) {
                    ModalDismissButton("完成")
                }
#endif
            }
            .alert("设置失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func homeItemRow(_ id: String) -> some View {
        if id == "liked-songs" {
            likedSongsRow
        } else if let playlist = personal.playlists.first(where: { $0.id == id }) {
            playlistRow(playlist)
        }
    }

    private var likedSongsRow: some View {
        Button {
            toggleLikedSongs()
        } label: {
            HStack(spacing: 12) {
                SonaLikedCover()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("收藏的歌曲")
                        .foregroundStyle(.primary)
                    Text("\(personal.favoriteIDs.count) 首歌曲")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if updatingIDs.contains("liked-songs") {
                    ProgressView()
                } else {
                    Image(systemName: personal.favoritesShownOnHome
                        ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(personal.favoritesShownOnHome
                            ? Color.sonaGreen : .secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(updatingIDs.contains("liked-songs"))
    }

    private func playlistRow(_ playlist: Playlist) -> some View {
        Button {
            toggle(playlist)
        } label: {
            HStack(spacing: 12) {
                ArtworkView(
                    path: sonaArtworkPaths(playlist.artworkURLs).first
                        ?? sonaFirstArtworkURL(in: playlist.trackIDs.compactMap(library.track(id:))),
                    cornerRadius: 6,
                    thumbnailSize: 128
                )
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(playlist.name)
                        .foregroundStyle(.primary)
                    Text("\(playlist.trackIDs.count) 首歌曲")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if updatingIDs.contains(playlist.id) {
                    ProgressView()
                } else {
                    Image(systemName: playlist.shownOnHome ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(playlist.shownOnHome ? Color.sonaGreen : .secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(updatingIDs.contains(playlist.id))
    }

    private func toggle(_ playlist: Playlist) {
        updatingIDs.insert(playlist.id)
        Task {
            let succeeded = await personal.setPlaylistShownOnHome(
                id: playlist.id,
                shown: !playlist.shownOnHome
            )
            updatingIDs.remove(playlist.id)
            if succeeded {
                syncSelectedOrder()
            } else {
                errorMessage = personal.errorMessage ?? "请稍后重试"
            }
        }
    }

    private func toggleLikedSongs() {
        updatingIDs.insert("liked-songs")
        Task {
            let succeeded = await personal.setFavoritesShownOnHome(
                !personal.favoritesShownOnHome
            )
            updatingIDs.remove("liked-songs")
            if succeeded {
                syncSelectedOrder()
            } else {
                errorMessage = personal.errorMessage ?? "请稍后重试"
            }
        }
    }

    private func moveSelectedPlaylists(from offsets: IndexSet, to destination: Int) {
        orderedSelectedIDs.move(fromOffsets: offsets, toOffset: destination)
        let ids = orderedSelectedIDs
        Task {
            if !(await personal.reorderHomeItems(ids: ids)) {
                syncSelectedOrder()
                errorMessage = personal.errorMessage ?? "排序保存失败"
            }
        }
    }

    private func syncSelectedOrder() {
        var items = personal.playlists.filter(\.shownOnHome).map {
            (id: $0.id, position: $0.homePosition)
        }
        if personal.favoritesShownOnHome {
            items.append((id: "liked-songs", position: personal.favoritesHomePosition))
        }
        orderedSelectedIDs = items.sorted {
            ($0.position ?? Int.max, $0.id) < ($1.position ?? Int.max, $1.id)
        }.map(\.id)
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
                .desktopEmptyState()
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
