import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var tracks: [Track] = [] {
        didSet { trackLookup = LibraryTrackLookup(tracks) }
    }
    @Published private(set) var nextCursor: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var searchResults: [Track] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingMoreSearch = false
    @Published private(set) var scanStatus: ScanStatus?
    @Published var errorMessage: String?
    @Published private(set) var sort = "TITLE"
    @Published private(set) var genreFilter: String?
    @Published private(set) var codecFilter: String?
    @Published private(set) var metadataFilter: String?

    private let api: APIClient
    private var trackLookup = LibraryTrackLookup([])
    private var loadedQuery = ""
    private var searchQuery = ""
    private var searchCursor: String?
    private var searchGeneration = 0
    private var artworkPrefetchTask: Task<Void, Never>?

    init(api: APIClient = .shared) {
        self.api = api
    }

    func refresh(query: String = "") async {
        guard !isLoading, !isLoadingMore else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await api.tracks(
                query: query, cursor: nil, sort: sort, genre: genreFilter,
                codec: codecFilter, metadataStatus: metadataFilter
            )
            tracks = page.items
            nextCursor = page.nextCursor
            loadedQuery = query
            prefetchArtwork(for: tracks)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadNextPageIfNeeded(currentTrack: Track) async {
        guard let index = tracks.firstIndex(where: { $0.id == currentTrack.id }) else { return }
        let threshold = max(tracks.count - 10, 0)
        guard index >= threshold else { return }
        await loadNextPage()
    }

    func loadNextPage() async {
        guard !isLoading, !isLoadingMore, let cursor = nextCursor else { return }
        isLoadingMore = true
        errorMessage = nil
        defer { isLoadingMore = false }
        do {
            let page = try await api.tracks(
                query: loadedQuery, cursor: cursor, sort: sort, genre: genreFilter,
                codec: codecFilter, metadataStatus: metadataFilter
            )
            let loadedIDs = Set(tracks.map(\.id))
            tracks.append(contentsOf: page.items.filter { !loadedIDs.contains($0.id) })
            nextCursor = page.nextCursor
            prefetchArtwork(for: tracks)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func search(query: String) async {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            clearSearch()
            return
        }
        searchGeneration += 1
        let generation = searchGeneration
        searchQuery = value
        searchCursor = nil
        searchResults = []
        isSearching = true
        isLoadingMoreSearch = false
        errorMessage = nil
        do {
            let page = try await api.tracks(query: value, cursor: nil)
            guard generation == searchGeneration else { return }
            searchResults = page.items
            searchCursor = page.nextCursor
            isSearching = false
        } catch {
            guard generation == searchGeneration else { return }
            searchResults = []
            searchCursor = nil
            isSearching = false
            errorMessage = error.localizedDescription
        }
    }

    func clearSearch() {
        searchGeneration += 1
        searchQuery = ""
        searchCursor = nil
        searchResults = []
        isSearching = false
        isLoadingMoreSearch = false
    }

    func loadNextSearchPageIfNeeded(currentTrack: Track) async {
        guard let index = searchResults.firstIndex(where: { $0.id == currentTrack.id }) else { return }
        let threshold = max(searchResults.count - 10, 0)
        guard index >= threshold else { return }
        await loadNextSearchPage()
    }

    private func loadNextSearchPage() async {
        guard !isSearching, !isLoadingMoreSearch, let cursor = searchCursor else { return }
        let generation = searchGeneration
        let query = searchQuery
        isLoadingMoreSearch = true
        errorMessage = nil
        do {
            let page = try await api.tracks(query: query, cursor: cursor)
            guard generation == searchGeneration else { return }
            let loadedIDs = Set(searchResults.map(\.id))
            searchResults.append(contentsOf: page.items.filter { !loadedIDs.contains($0.id) })
            searchCursor = page.nextCursor
            isLoadingMoreSearch = false
        } catch {
            guard generation == searchGeneration else { return }
            isLoadingMoreSearch = false
            errorMessage = error.localizedDescription
        }
    }

    func scan(directory: String = "", mode: ScrapeMode = .missingOnly) async {
        errorMessage = nil
        do {
            scanStatus = try await api.startScan(directory: directory, mode: mode)
            repeat {
                try await Task.sleep(for: .seconds(1))
                scanStatus = try await api.scanStatus()
            } while scanStatus?.state == "RUNNING"
            if scanStatus?.state == "FAILED" {
                errorMessage = scanStatus?.message ?? "服务器音乐目录扫描失败"
                return
            }
            await refresh(query: loadedQuery)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func forceRescrapePlaylist(id: String) async -> Bool {
        errorMessage = nil
        do {
            scanStatus = try await api.forceRescrapePlaylist(id: id)
            repeat {
                try await Task.sleep(for: .seconds(1))
                scanStatus = try await api.scanStatus()
            } while scanStatus?.state == "RUNNING"
            if scanStatus?.state == "FAILED" {
                errorMessage = scanStatus?.message ?? "歌单覆盖刮削失败"
                return false
            }
            await refresh(query: loadedQuery)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func applyFilters(
        sort: String, genre: String?, codec: String?, metadataStatus: String?
    ) async {
        self.sort = sort
        genreFilter = genre
        codecFilter = codec
        metadataFilter = metadataStatus
        await refresh(query: loadedQuery)
    }

    func track(id: String) -> Track? {
        trackLookup.track(id: id)
    }

    func applyTrackUpdate(_ track: Track) {
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[index] = track
        }
        if let index = searchResults.firstIndex(where: { $0.id == track.id }) {
            searchResults[index] = track
        }
        prefetchArtwork(for: [track])
    }

    private func prefetchArtwork(for tracks: [Track]) {
        let urls = tracks.compactMap {
            sonaArtworkURL(path: $0.artworkURL, thumbnailSize: 768)
        }
        guard !urls.isEmpty else { return }

        artworkPrefetchTask?.cancel()
        artworkPrefetchTask = Task(priority: .utility) {
            await RemoteImageCache.shared.prefetch(urls: urls)
        }
    }
}

@MainActor
final class PersonalStore: ObservableObject {
    @Published private(set) var favoriteIDs: Set<String> = []
    @Published private(set) var favoriteTracks: [Track] = []
    @Published private(set) var isLoadingMoreFavorites = false
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var history: [HistoryItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let api: APIClient
    private var favoriteNextCursor: String?

    init(api: APIClient = .shared) {
        self.api = api
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            favoriteIDs = Set(try await api.favorites().trackIDs)
            let favoritePage = try await api.favoriteTracks(cursor: nil)
            favoriteTracks = favoritePage.items
            favoriteNextCursor = favoritePage.nextCursor
            playlists = try await api.playlists()
            history = try await api.history().items
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyTrackUpdate(_ track: Track) {
        if let index = favoriteTracks.firstIndex(where: { $0.id == track.id }) {
            favoriteTracks[index] = track
        }
    }

    func toggleFavorite(trackID: String) async {
        let shouldAdd = !favoriteIDs.contains(trackID)
        _ = await setFavorite(trackID: trackID, isFavorite: shouldAdd)
    }

    @discardableResult
    func setFavorite(trackID: String, isFavorite: Bool) async -> Bool {
        do {
            try await api.setFavorite(trackID: trackID, isFavorite: isFavorite)
            if isFavorite {
                favoriteIDs.insert(trackID)
            } else {
                favoriteIDs.remove(trackID)
                favoriteTracks.removeAll { $0.id == trackID }
            }
            favoriteIDs = Set(try await api.favorites().trackIDs)
            let favoritePage = try await api.favoriteTracks(cursor: nil)
            favoriteTracks = favoritePage.items
            favoriteNextCursor = favoritePage.nextCursor
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func removeFavorites(trackIDs: Set<String>) async {
        guard !trackIDs.isEmpty else { return }
        do {
            try await api.removeFavorites(trackIDs: Array(trackIDs))
            favoriteIDs.subtract(trackIDs)
            favoriteTracks.removeAll { trackIDs.contains($0.id) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadNextFavoritePageIfNeeded(currentTrack: Track) async {
        guard let index = favoriteTracks.firstIndex(where: { $0.id == currentTrack.id }) else { return }
        let threshold = max(favoriteTracks.count - 10, 0)
        guard index >= threshold else { return }
        await loadNextFavoritePage()
    }

    func loadAllFavoriteTracks() async -> [Track] {
        guard !isLoadingMoreFavorites else { return favoriteTracks }
        isLoadingMoreFavorites = true
        defer { isLoadingMoreFavorites = false }
        while let cursor = favoriteNextCursor {
            do {
                let page = try await api.favoriteTracks(cursor: cursor)
                appendFavoriteTracks(page.items)
                favoriteNextCursor = page.nextCursor
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }
        return favoriteTracks
    }

    func createPlaylist(name: String) async {
        do {
            playlists.append(try await api.createPlaylist(name: name))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deletePlaylist(id: String) async {
        do {
            try await api.deletePlaylist(id: id)
            playlists.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateDirectoryPlaylist(id: String, name: String, poolType: String) async {
        do {
            let updated = try await api.updateDirectoryPlaylist(
                id: id, name: name, poolType: poolType
            )
            guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
            playlists[index] = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setTrack(_ trackID: String, in playlistID: String, isIncluded: Bool) async {
        do {
            try await api.setPlaylistTrack(
                playlistID: playlistID,
                trackID: trackID,
                isIncluded: isIncluded
            )
            guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
            var trackIDs = playlists[index].trackIDs
            if isIncluded, !trackIDs.contains(trackID) {
                trackIDs.append(trackID)
            } else if !isIncluded {
                trackIDs.removeAll { $0 == trackID }
            }
            let playlist = playlists[index]
            playlists[index] = Playlist(
                id: playlist.id,
                name: playlist.name,
                trackIDs: trackIDs,
                artworkURLs: playlist.artworkURLs,
                artworkTrackID: playlist.artworkTrackID,
                createdAt: playlist.createdAt,
                featured: playlist.featured,
                directoryPath: playlist.directoryPath,
                poolType: playlist.poolType
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func setPlaylistArtwork(playlistID: String, trackID: String) async -> Bool {
        do {
            let updated = try await api.setPlaylistArtwork(
                playlistID: playlistID,
                trackID: trackID
            )
            guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else {
                return false
            }
            playlists[index] = updated
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func removeTracks(_ trackIDs: Set<String>, from playlistID: String) async {
        guard !trackIDs.isEmpty else { return }
        do {
            try await api.removePlaylistTracks(
                playlistID: playlistID,
                trackIDs: Array(trackIDs)
            )
            guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
            let playlist = playlists[index]
            playlists[index] = Playlist(
                id: playlist.id,
                name: playlist.name,
                trackIDs: playlist.trackIDs.filter { !trackIDs.contains($0) },
                artworkURLs: playlist.artworkURLs,
                artworkTrackID: playlist.artworkTrackID,
                createdAt: playlist.createdAt,
                featured: playlist.featured,
                directoryPath: playlist.directoryPath,
                poolType: playlist.poolType
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func notePlayback(trackID: String) {
        history.insert(
            HistoryItem(trackID: trackID, playedAt: Int64(Date().timeIntervalSince1970 * 1_000)),
            at: 0
        )
        if history.count > 100 {
            history.removeLast(history.count - 100)
        }
    }

    func reset() {
        favoriteIDs = []
        favoriteTracks = []
        favoriteNextCursor = nil
        isLoadingMoreFavorites = false
        playlists = []
        history = []
        errorMessage = nil
    }

    private func loadNextFavoritePage() async {
        guard !isLoadingMoreFavorites, let cursor = favoriteNextCursor else { return }
        isLoadingMoreFavorites = true
        defer { isLoadingMoreFavorites = false }
        do {
            let page = try await api.favoriteTracks(cursor: cursor)
            appendFavoriteTracks(page.items)
            favoriteNextCursor = page.nextCursor
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func appendFavoriteTracks(_ tracks: [Track]) {
        let loadedIDs = Set(favoriteTracks.map(\.id))
        favoriteTracks.append(contentsOf: tracks.filter { !loadedIDs.contains($0.id) })
    }
}
