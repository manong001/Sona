import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var nextCursor: String?
    @Published private(set) var isLoading = false
    @Published private(set) var scanStatus: ScanStatus?
    @Published var errorMessage: String?

    private let api: APIClient
    private var loadedQuery = ""

    init(api: APIClient = .shared) {
        self.api = api
    }

    func refresh(query: String = "") async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var page = try await api.tracks(query: query, cursor: nil)
            tracks = page.items
            nextCursor = page.nextCursor
            loadedQuery = query
            while let cursor = nextCursor {
                page = try await api.tracks(query: query, cursor: cursor)
                tracks.append(contentsOf: page.items)
                nextCursor = page.nextCursor
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func scan() async {
        do {
            scanStatus = try await api.startScan()
            repeat {
                try await Task.sleep(for: .seconds(1))
                scanStatus = try await api.scanStatus()
            } while scanStatus?.state == "RUNNING"
            await refresh(query: loadedQuery)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func track(id: String) -> Track? {
        tracks.first { $0.id == id }
    }
}

@MainActor
final class PersonalStore: ObservableObject {
    @Published private(set) var favoriteIDs: Set<String> = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var history: [HistoryItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let api: APIClient

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
            playlists = try await api.playlists()
            history = try await api.history().items
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleFavorite(trackID: String) async {
        let shouldAdd = !favoriteIDs.contains(trackID)
        do {
            try await api.setFavorite(trackID: trackID, isFavorite: shouldAdd)
            if shouldAdd {
                favoriteIDs.insert(trackID)
            } else {
                favoriteIDs.remove(trackID)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
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
                createdAt: playlist.createdAt
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func recordPlayback(trackID: String) async {
        do {
            try await api.recordPlayback(trackID: trackID)
            history.insert(
                HistoryItem(trackID: trackID, playedAt: Int64(Date().timeIntervalSince1970 * 1_000)),
                at: 0
            )
            if history.count > 100 {
                history.removeLast(history.count - 100)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reset() {
        favoriteIDs = []
        playlists = []
        history = []
        errorMessage = nil
    }
}
