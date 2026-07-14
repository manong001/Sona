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
            let page = try await api.tracks(query: query, cursor: nil)
            tracks = page.items
            nextCursor = page.nextCursor
            loadedQuery = query
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadNextPageIfNeeded(after track: Track) async {
        guard track.id == tracks.last?.id, let cursor = nextCursor, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await api.tracks(query: loadedQuery, cursor: cursor)
            tracks.append(contentsOf: page.items)
            nextCursor = page.nextCursor
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
