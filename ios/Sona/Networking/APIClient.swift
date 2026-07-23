import Foundation

final class APIClient {
    static let shared = APIClient()
    static let defaultServerURL = "http://sosee.eu.cc:6699"

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpCookieStorage = .shared
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
    }

    var serverURL: URL {
        let configured = UserDefaults.standard.string(forKey: "serverURL") ?? Self.defaultServerURL
        return URL(string: configured.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            ?? URL(string: Self.defaultServerURL)!
    }

    func url(for path: String) -> URL {
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }
        return URL(string: path, relativeTo: serverURL)?.absoluteURL
            ?? serverURL.appending(
                path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            )
    }

    func currentUser() async throws -> UserResponse {
        try await request(path: "/api/v1/auth/me")
    }

    func login(username: String, password: String) async throws -> UserResponse {
        struct Body: Encodable {
            let username: String
            let password: String
        }
        return try await request(
            path: "/api/v1/auth/login",
            method: "POST",
            body: try encoder.encode(Body(username: username, password: password))
        )
    }

    func logout() async throws {
        try await requestVoid(path: "/api/v1/auth/logout", method: "POST")
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        struct Body: Encodable {
            let currentPassword: String
            let newPassword: String
        }
        try await requestVoid(
            path: "/api/v1/auth/password",
            method: "PUT",
            body: try encoder.encode(Body(currentPassword: currentPassword, newPassword: newPassword))
        )
    }

    func logoutAll() async throws {
        try await requestVoid(path: "/api/v1/auth/logout-all", method: "POST")
    }

    func users() async throws -> [ManagedUser] {
        try await request(path: "/api/v1/users")
    }

    func createUser(username: String, password: String, role: UserRole) async throws -> ManagedUser {
        struct Body: Encodable {
            let username: String
            let password: String
            let role: UserRole
        }
        return try await request(
            path: "/api/v1/users",
            method: "POST",
            body: try encoder.encode(Body(username: username, password: password, role: role))
        )
    }

    func setUserEnabled(id: String, enabled: Bool) async throws -> ManagedUser {
        struct Body: Encodable { let enabled: Bool }
        return try await request(
            path: "/api/v1/users/\(id)",
            method: "PATCH",
            body: try encoder.encode(Body(enabled: enabled))
        )
    }

    func setUserRole(id: String, role: UserRole) async throws -> ManagedUser {
        struct Body: Encodable { let role: UserRole }
        return try await request(
            path: "/api/v1/users/\(id)/role",
            method: "PATCH",
            body: try encoder.encode(Body(role: role))
        )
    }

    func updateUserProfile(
        id: String, username: String, role: UserRole, enabled: Bool,
        avatarPreset: String?
    ) async throws -> ManagedUser {
        struct Body: Encodable {
            let username: String
            let role: UserRole
            let enabled: Bool
            let avatarPreset: String?
        }
        return try await request(
            path: "/api/v1/users/\(id)/profile",
            method: "PUT",
            body: try encoder.encode(Body(
                username: username, role: role, enabled: enabled,
                avatarPreset: avatarPreset
            ))
        )
    }

    func uploadUserAvatar(userID: String, imageData: Data) async throws -> ManagedUser {
        try await uploadAvatar(path: "/api/v1/users/\(userID)/avatar", imageData: imageData)
    }

    func setOwnAvatarPreset(_ preset: AvatarPreset) async throws -> UserResponse {
        struct Body: Encodable { let preset: String }
        return try await request(
            path: "/api/v1/auth/avatar", method: "PUT",
            body: try encoder.encode(Body(preset: preset.rawValue))
        )
    }

    func uploadOwnAvatar(imageData: Data) async throws -> UserResponse {
        try await uploadAvatar(path: "/api/v1/auth/avatar", imageData: imageData)
    }

    func resetPassword(userID: String, password: String) async throws {
        struct Body: Encodable { let password: String }
        try await requestVoid(
            path: "/api/v1/users/\(userID)/password",
            method: "PUT",
            body: try encoder.encode(Body(password: password))
        )
    }

    func deleteUser(id: String) async throws {
        try await requestVoid(path: "/api/v1/users/\(id)", method: "DELETE")
    }

    func favorites() async throws -> FavoritesResponse {
        try await request(path: "/api/v1/me/favorites")
    }

    func favoriteTracks(cursor: String?) async throws -> TrackPage {
        var components = URLComponents(
            url: url(for: "/api/v1/me/favorites/tracks"),
            resolvingAgainstBaseURL: false
        )!
        var queryItems = [URLQueryItem(name: "limit", value: "50")]
        queryItems.append(URLQueryItem(name: "childMode", value: childModeValue))
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components.queryItems = queryItems
        return try await request(url: components.url!)
    }

    func setFavorite(trackID: String, isFavorite: Bool) async throws {
        try await requestVoid(
            path: "/api/v1/me/favorites/\(trackID)",
            method: isFavorite ? "PUT" : "DELETE"
        )
    }

    func setFavoritesShownOnHome(_ shown: Bool) async throws {
        try await requestVoid(
            path: "/api/v1/me/home-items/liked-songs",
            method: shown ? "PUT" : "DELETE"
        )
    }

    func removeFavorites(trackIDs: [String]) async throws {
        struct Body: Encodable { let trackIds: [String] }
        try await requestVoid(
            path: "/api/v1/me/favorites",
            method: "DELETE",
            body: try encoder.encode(Body(trackIds: trackIDs))
        )
    }

    func importFavorites(directory: String) async throws -> DirectoryImportResponse {
        struct Body: Encodable { let path: String }
        return try await request(
            path: "/api/v1/me/favorites/import-directory",
            method: "POST",
            body: try encoder.encode(Body(path: directory))
        )
    }

    func playlists() async throws -> [Playlist] {
        var components = URLComponents(
            url: url(for: "/api/v1/me/playlists"), resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "childMode", value: childModeValue)
        ]
        return try await request(url: components.url!, timeout: 60)
    }

    func createPlaylist(name: String) async throws -> Playlist {
        struct Body: Encodable { let name: String }
        return try await request(
            path: "/api/v1/me/playlists",
            method: "POST",
            body: try encoder.encode(Body(name: name))
        )
    }

    func deletePlaylist(id: String, directoryPath: String? = nil) async throws {
        var components = URLComponents(
            url: url(for: "/api/v1/me/playlists/\(id)"), resolvingAgainstBaseURL: false
        )!
        if let directoryPath {
            components.queryItems = [URLQueryItem(name: "directoryPath", value: directoryPath)]
        }
        try await requestVoid(path: components.url!.absoluteString, method: "DELETE")
    }

    func setPlaylistShownOnHome(id: String, shown: Bool) async throws {
        try await requestVoid(
            path: "/api/v1/me/playlists/\(id)/home",
            method: shown ? "PUT" : "DELETE"
        )
    }

    func reorderHomeItems(ids: [String]) async throws {
        struct Body: Encodable { let itemIds: [String] }
        try await requestVoid(
            path: "/api/v1/me/playlists/home-order",
            method: "PUT",
            body: try encoder.encode(Body(itemIds: ids))
        )
    }

    func reorderPlaylists(ids: [String]) async throws {
        struct Body: Encodable { let playlistIds: [String] }
        var components = URLComponents(
            url: url(for: "/api/v1/me/playlists/order"), resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "childMode", value: childModeValue)
        ]
        try await requestVoid(
            path: components.url!.absoluteString,
            method: "PUT",
            body: try encoder.encode(Body(playlistIds: ids))
        )
    }

    func updateDirectoryPlaylist(
        id: String,
        directoryPath: String?,
        name: String,
        poolType: String
    ) async throws -> Playlist {
        struct Body: Encodable { let name: String; let poolType: String }
        var components = URLComponents(
            url: url(for: "/api/v1/me/playlists/\(id)"), resolvingAgainstBaseURL: false
        )!
        if let directoryPath {
            components.queryItems = [URLQueryItem(name: "directoryPath", value: directoryPath)]
        }
        return try await request(
            url: components.url!,
            method: "PATCH",
            body: try encoder.encode(Body(name: name, poolType: poolType))
        )
    }

    func forceRescrapePlaylist(id: String) async throws -> ScanStatus {
        try await request(
            path: "/api/v1/me/playlists/\(id)/rescrape",
            method: "POST"
        )
    }

    func setPlaylistTrack(playlistID: String, trackID: String, isIncluded: Bool) async throws {
        try await requestVoid(
            path: "/api/v1/me/playlists/\(playlistID)/tracks/\(trackID)",
            method: isIncluded ? "PUT" : "DELETE"
        )
    }

    func setPlaylistArtwork(playlistID: String, trackID: String) async throws -> Playlist {
        try await request(
            path: "/api/v1/me/playlists/\(playlistID)/artwork/\(trackID)",
            method: "PUT"
        )
    }

    func uploadPlaylistArtwork(playlistID: String, imageData: Data) async throws -> Playlist {
        try await uploadAvatar(
            path: "/api/v1/me/playlists/\(playlistID)/artwork",
            imageData: imageData
        )
    }

    func clearPlaylistArtwork(playlistID: String) async throws -> Playlist {
        try await request(
            path: "/api/v1/me/playlists/\(playlistID)/artwork",
            method: "DELETE"
        )
    }

    func useSourcePlaylistArtwork(playlistID: String) async throws -> Playlist {
        try await request(
            path: "/api/v1/me/playlists/\(playlistID)/artwork/source",
            method: "PUT"
        )
    }

    func removePlaylistTracks(playlistID: String, trackIDs: [String]) async throws {
        struct Body: Encodable { let trackIds: [String] }
        try await requestVoid(
            path: "/api/v1/me/playlists/\(playlistID)/tracks",
            method: "DELETE",
            body: try encoder.encode(Body(trackIds: trackIDs))
        )
    }

    func importPlaylistDirectory(
        playlistID: String,
        directory: String
    ) async throws -> DirectoryImportResponse {
        struct Body: Encodable { let path: String }
        return try await request(
            path: "/api/v1/me/playlists/\(playlistID)/import-directory",
            method: "POST",
            body: try encoder.encode(Body(path: directory))
        )
    }

    func history() async throws -> HistoryResponse {
        try await request(path: "/api/v1/me/history")
    }

    func recordPlayback(trackID: String, listenedMs: Int64, progressPercent: Double) async throws {
        struct Body: Encodable {
            let listenedMs: Int64
            let progressPercent: Double
        }
        try await requestVoid(
            path: "/api/v1/me/history/\(trackID)",
            method: "POST",
            body: try encoder.encode(Body(listenedMs: listenedMs, progressPercent: progressPercent))
        )
    }

    func playbackState() async throws -> PlaybackState? {
        var request = URLRequest(url: url(for: "/api/v1/me/playback-state"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 204 { return nil }
        try validate(response: response, data: data)
        return try decoder.decode(PlaybackState.self, from: data)
    }

    func savePlaybackState(
        queueType: String, queueContextID: String?, trackID: String,
        queueTrackIDs: [String], progressMs: Int64
    ) async throws {
        struct Body: Encodable {
            let queueType: String
            let queueContextId: String?
            let trackId: String
            let queueTrackIds: [String]
            let progressMs: Int64
        }
        try await requestVoid(
            path: "/api/v1/me/playback-state",
            method: "PUT",
            body: try encoder.encode(Body(
                queueType: queueType,
                queueContextId: queueContextID,
                trackId: trackID,
                queueTrackIds: queueTrackIDs,
                progressMs: progressMs
            ))
        )
    }

    func recordPlayedBatch(queueType: String, queueContextID: String?) async throws {
        struct Body: Encodable { let queueType: String; let queueContextId: String? }
        try await requestVoid(
            path: "/api/v1/me/playback-batches",
            method: "POST",
            body: try encoder.encode(Body(queueType: queueType, queueContextId: queueContextID))
        )
    }

    func tracks(
        query: String, cursor: String?, sort: String = "TITLE",
        genre: String? = nil, codec: String? = nil, metadataStatus: String? = nil
    ) async throws -> TrackPage {
        var components = URLComponents(url: url(for: "/api/v1/tracks"), resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "limit", value: "50")]
        queryItems.append(URLQueryItem(name: "childMode", value: childModeValue))
        queryItems.append(URLQueryItem(name: "sort", value: sort))
        if !query.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        if let genre { queryItems.append(URLQueryItem(name: "genre", value: genre)) }
        if let codec { queryItems.append(URLQueryItem(name: "codec", value: codec)) }
        if let metadataStatus {
            queryItems.append(URLQueryItem(name: "metadataStatus", value: metadataStatus))
        }
        components.queryItems = queryItems
        return try await request(url: components.url!)
    }

    func randomTracks(limit: Int = 50, childMode: Bool? = nil) async throws -> [Track] {
        var components = URLComponents(
            url: url(for: "/api/v1/tracks/random"),
            resolvingAgainstBaseURL: false
        )!
        let modeValue = childMode.map { $0 ? "true" : "false" } ?? childModeValue
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "childMode", value: modeValue)
        ]
        return try await request(url: components.url!)
    }

    func discoveryTracks(limit: Int = 10) async throws -> [Track] {
        var components = URLComponents(
            url: url(for: "/api/v1/tracks/discovery"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "childMode", value: childModeValue)
        ]
        return try await request(url: components.url!)
    }

    func dailyRecommendations() async throws -> [Track] {
        var components = URLComponents(
            url: url(for: "/api/v1/recommendations/daily"), resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "childMode", value: childModeValue)]
        return try await request(url: components.url!)
    }

    func madeForYouRecommendations() async throws -> [MadeForYouMix] {
        var components = URLComponents(
            url: url(for: "/api/v1/recommendations/made-for-you"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "childMode", value: childModeValue)]
        return try await request(url: components.url!)
    }

    func recommendationGenres() async throws -> [String] {
        var components = URLComponents(
            url: url(for: "/api/v1/recommendations/genres"), resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "childMode", value: childModeValue)]
        return try await request(url: components.url!)
    }

    func recommendations(genre: String, limit: Int = 20) async throws -> [Track] {
        var components = URLComponents(
            url: url(for: "/api/v1/recommendations/genres").appending(path: genre),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "childMode", value: childModeValue)
        ]
        return try await request(url: components.url!)
    }

    func chart(region: String) async throws -> [ChartEntry] {
        var components = URLComponents(
            url: url(for: "/api/v1/charts"), resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "region", value: region),
            URLQueryItem(name: "childMode", value: childModeValue)
        ]
        return try await request(url: components.url!)
    }

    func track(id: String) async throws -> Track {
        try await request(path: "/api/v1/tracks/\(id)")
    }

    func tracks(ids: [String]) async throws -> [Track] {
        struct Body: Encodable { let trackIds: [String] }
        var seen = Set<String>()
        let orderedIDs = ids.filter { seen.insert($0).inserted }
        var tracksByID: [String: Track] = [:]
        for start in stride(from: 0, to: orderedIDs.count, by: 500) {
            let end = min(start + 500, orderedIDs.count)
            let batch: [Track] = try await request(
                path: "/api/v1/tracks/batch",
                method: "POST",
                body: try encoder.encode(Body(trackIds: Array(orderedIDs[start..<end])))
            )
            batch.forEach { tracksByID[$0.id] = $0 }
        }
        return orderedIDs.compactMap { tracksByID[$0] }
    }

    func managedTracks(poolType: String? = nil) async throws -> [Track] {
        var components = URLComponents(
            url: url(for: "/api/v1/library/tracks"), resolvingAgainstBaseURL: false
        )!
        if let poolType { components.queryItems = [URLQueryItem(name: "poolType", value: poolType)] }
        return try await request(url: components.url!)
    }

    func duplicateTracks() async throws -> [DuplicateTrackGroup] {
        try await request(path: "/api/v1/library/tracks/duplicates")
    }

    func replaceDuplicateTrack(id: String, replacementTrackID: String) async throws {
        struct Body: Encodable {
            let replacementTrackId: String
        }
        try await requestVoid(
            path: "/api/v1/library/tracks/duplicates/\(id)/replace",
            method: "POST",
            body: try encoder.encode(Body(replacementTrackId: replacementTrackID))
        )
    }

    func classifyTrack(
        id: String, poolType: String,
        genre: String? = nil, region: String? = nil
    ) async throws -> Track {
        struct Body: Encodable {
            let poolType: String
            let genre: String?
            let region: String?
        }
        return try await request(
            path: "/api/v1/library/tracks/\(id)", method: "PATCH",
            body: try encoder.encode(Body(
                poolType: poolType, genre: genre, region: region
            ))
        )
    }

    func editTrackMetadata(
        id: String, title: String, artist: String, album: String,
        trackNumber: Int?, genre: String, relatedGenres: [String]? = nil
    ) async throws -> Track {
        struct Body: Encodable {
            let title: String; let artist: String; let album: String
            let trackNumber: Int?; let genre: String; let relatedGenres: [String]?
        }
        return try await request(
            path: "/api/v1/library/tracks/\(id)/metadata", method: "PATCH",
            body: try encoder.encode(Body(
                title: title, artist: artist, album: album,
                trackNumber: trackNumber, genre: genre, relatedGenres: relatedGenres
            ))
        )
    }

    func analyzeTrackMetadata(id: String) async throws -> AiTrackAnalysis {
        try await request(path: "/api/v1/library/tracks/\(id)/ai-analysis", method: "POST")
    }

    func aiSettings() async throws -> AiSettings {
        try await request(path: "/api/v1/library/ai-settings")
    }

    func updateAiSettings(
        enabled: Bool, baseUrl: String, model: String, apiKey: String?
    ) async throws -> AiSettings {
        struct Body: Encodable {
            let enabled: Bool
            let baseUrl: String
            let model: String
            let apiKey: String?
        }
        return try await request(
            path: "/api/v1/library/ai-settings", method: "PUT",
            body: try encoder.encode(Body(
                enabled: enabled, baseUrl: baseUrl, model: model, apiKey: apiKey
            ))
        )
    }

    func similarTracks(id: String, limit: Int = 10) async throws -> [Track] {
        var components = URLComponents(
            url: url(for: "/api/v1/tracks/\(id)/similar"), resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "childMode", value: childModeValue)
        ]
        return try await request(url: components.url!)
    }

    func rescrapeTrack(id: String) async throws -> ScanStatus {
        try await request(path: "/api/v1/library/tracks/\(id)/rescrape", method: "POST")
    }

    func deleteTrack(id: String, isAdmin: Bool) async throws {
        let path = isAdmin ? "/api/v1/library/tracks/\(id)" : "/api/v1/me/tracks/\(id)"
        try await requestVoid(path: path, method: "DELETE")
    }

    func trashTracks() async throws -> [Track] {
        try await request(path: "/api/v1/me/trash")
    }

    func restoreTrack(id: String) async throws {
        try await requestVoid(path: "/api/v1/me/trash/\(id)", method: "PUT")
    }

    func uploadTracks(urls: [URL]) async -> LocalUploadResult {
        var succeeded = 0
        var errors: [String] = []
        for url in urls {
            do {
                let accessible = url.startAccessingSecurityScopedResource()
                defer { if accessible { url.stopAccessingSecurityScopedResource() } }
                let boundary = "Sona-\(UUID().uuidString)"
                var body = Data()
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(url.lastPathComponent)\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
                body.append(try Data(contentsOf: url))
                body.append("\r\n".data(using: .utf8)!)
                body.append("--\(boundary)--\r\n".data(using: .utf8)!)
                var request = URLRequest(url: self.url(for: "/api/v1/library/tracks/upload"))
                request.httpMethod = "POST"
                request.httpBody = body
                request.setValue(
                    "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type"
                )
                let (data, response) = try await session.data(for: request)
                try validate(response: response, data: data)
                succeeded += 1
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        return LocalUploadResult(
            succeeded: succeeded,
            failed: urls.count - succeeded,
            message: errors.first
        )
    }

    func importRecords() async throws -> [ImportRecord] {
        try await request(path: "/api/v1/me/import-records")
    }

    func waitForImportRecord(id: String) async throws -> ImportRecord {
        for _ in 0..<300 {
            guard let record = try await importRecords().first(where: { $0.id == id }) else {
                throw APIError.invalidResponse
            }
            if record.state != .running { return record }
            try await Task.sleep(for: .seconds(1))
        }
        throw APIError.importTimedOut
    }

    func createImportRecord(
        type: ImportRecordType, source: String, target: String, total: Int
    ) async throws -> ImportRecord {
        struct Body: Encodable {
            let type: ImportRecordType
            let source: String
            let target: String
            let total: Int
        }
        return try await request(
            path: "/api/v1/me/import-records", method: "POST",
            body: try encoder.encode(Body(type: type, source: source, target: target, total: total))
        )
    }

    @discardableResult
    func updateImportRecord(id: String, update: ImportRecordUpdate) async throws -> ImportRecord {
        try await request(
            path: "/api/v1/me/import-records/\(id)", method: "PATCH",
            body: try encoder.encode(update)
        )
    }

    func deleteImportRecord(id: String) async throws {
        try await requestVoid(path: "/api/v1/me/import-records/\(id)", method: "DELETE")
    }

    func startScan() async throws -> ScanStatus {
        try await startScan(directory: "", mode: .standard)
    }

    func startScan(directory: String, mode: ScrapeMode = .standard) async throws -> ScanStatus {
        var components = URLComponents(
            url: url(for: "/api/v1/library/scan"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "mode", value: mode.rawValue)]
        if !directory.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "path", value: directory))
        }
        return try await request(url: components.url!, method: "POST")
    }

    func serverMusicDirectories(path: String) async throws -> ServerMusicDirectoryListing {
        var components = URLComponents(
            url: url(for: "/api/v1/library/directories"),
            resolvingAgainstBaseURL: false
        )!
        if !path.isEmpty {
            components.queryItems = [URLQueryItem(name: "path", value: path)]
        }
        return try await request(url: components.url!)
    }

    func scanStatus() async throws -> ScanStatus {
        try await request(path: "/api/v1/library/scan/status")
    }

    func musicDownloadSources() async throws -> [DownloadSource] {
        try await request(path: "/api/v1/downloads/sources")
    }

    func onlinePlaybackSources() async throws -> [OnlinePlaybackSource] {
        try await request(path: "/api/v1/online-playback/sources")
    }

    func setOnlinePlaybackSource(id: String, enabled: Bool) async throws {
        struct Body: Encodable { let enabled: Bool }
        try await requestVoid(
            path: "/api/v1/online-playback/sources/\(id)", method: "PUT",
            body: try encoder.encode(Body(enabled: enabled))
        )
    }

    func searchMusicDownloads(
        query: String, sources: [String] = []
    ) async throws -> DownloadSearchResponse {
        var components = URLComponents(
            url: url(for: "/api/v1/downloads/search"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        if !sources.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "sources", value: sources.joined(separator: ",")))
        }
        return try await request(url: components.url!, timeout: 180)
    }

    func queueMusicDownload(_ candidate: DownloadCandidate) async throws -> MusicDownloadTask {
        try await request(
            path: "/api/v1/downloads",
            method: "POST",
            body: try encoder.encode(candidate)
        )
    }

    func previewDownloadPlaylist(url: String) async throws -> DownloadPlaylistPreview {
        struct Body: Encodable { let url: String }
        return try await request(
            path: "/api/v1/downloads/playlists/preview",
            method: "POST",
            body: try encoder.encode(Body(url: url)),
            timeout: 300
        )
    }

    func queueDownloadPlaylist(
        name: String, items: [DownloadCandidate]
    ) async throws -> PlaylistDownloadQueueResponse {
        struct Body: Encodable {
            let name: String
            let items: [DownloadCandidate]
        }
        return try await request(
            path: "/api/v1/downloads/playlists",
            method: "POST",
            body: try encoder.encode(Body(name: name, items: items)),
            timeout: 60
        )
    }

    func playlistSubscriptions() async throws -> [PlaylistSubscription] {
        try await request(path: "/api/v1/me/playlist-subscriptions")
    }

    func createPlaylistSubscription(
        sourceURL: String, name: String?, poolType: String,
        autoDownload: Bool, syncIntervalHours: Int
    ) async throws -> PlaylistSubscription {
        struct Body: Encodable {
            let sourceUrl: String
            let name: String?
            let poolType: String
            let autoDownload: Bool
            let syncIntervalHours: Int
        }
        return try await request(
            path: "/api/v1/me/playlist-subscriptions",
            method: "POST",
            body: try encoder.encode(Body(
                sourceUrl: sourceURL, name: name, poolType: poolType,
                autoDownload: autoDownload, syncIntervalHours: syncIntervalHours
            )),
            timeout: 30
        )
    }

    func syncPlaylistSubscription(id: String) async throws -> PlaylistSubscription {
        try await request(
            path: "/api/v1/me/playlist-subscriptions/\(id)/sync",
            method: "POST",
            timeout: 300
        )
    }

    func downloadMissingPlaylistSubscription(id: String) async throws -> PlaylistSubscription {
        try await request(
            path: "/api/v1/me/playlist-subscriptions/\(id)/download-missing",
            method: "POST",
            timeout: 300
        )
    }

    func playlistSubscriptionItems(id: String) async throws -> [PlaylistSubscriptionItem] {
        try await request(path: "/api/v1/me/playlist-subscriptions/\(id)/items")
    }

    func playlistSubscriptionSuggestions(
        id: String, offset: Int, limit: Int
    ) async throws -> PlaylistSubscriptionItemPage {
        var components = URLComponents(
            url: url(for: "/api/v1/me/playlist-subscriptions/\(id)/suggestions"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        return try await request(url: components.url!, timeout: 60)
    }

    func applyBestPlaylistSubscriptionMatches(
        id: String
    ) async throws -> PlaylistSubscriptionBestMatchResult {
        try await request(
            path: "/api/v1/me/playlist-subscriptions/\(id)/matches/best",
            method: "POST",
            timeout: 300
        )
    }

    func selectPlaylistSubscriptionMatch(
        id: String, itemKey: String, trackId: String
    ) async throws -> PlaylistSubscription {
        struct Body: Encodable { let trackId: String }
        return try await request(
            path: "/api/v1/me/playlist-subscriptions/\(id)/items/\(itemKey)/match",
            method: "POST",
            body: try encoder.encode(Body(trackId: trackId))
        )
    }

    func downloadPlaylistSubscriptionItem(
        id: String, itemKey: String
    ) async throws -> PlaylistSubscription {
        try await request(
            path: "/api/v1/me/playlist-subscriptions/\(id)/items/\(itemKey)/download",
            method: "POST",
            timeout: 300
        )
    }

    func renamePlaylistSubscription(id: String, name: String) async throws -> PlaylistSubscription {
        struct Body: Encodable { let name: String }
        return try await request(
            path: "/api/v1/me/playlist-subscriptions/\(id)",
            method: "PATCH",
            body: try encoder.encode(Body(name: name))
        )
    }

    func deletePlaylistSubscription(id: String) async throws {
        try await requestVoid(path: "/api/v1/me/playlist-subscriptions/\(id)", method: "DELETE")
    }

    func achievements() async throws -> AchievementSummary {
        var components = URLComponents(
            url: url(for: "/api/v1/me/achievements"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "timezone", value: TimeZone.current.identifier)
        ]
        return try await request(url: components.url!)
    }

    func musicDownloadTasks() async throws -> [MusicDownloadTask] {
        try await request(path: "/api/v1/downloads")
    }

    func clearFailedMusicDownloadTasks() async throws {
        try await requestVoid(path: "/api/v1/downloads", method: "DELETE")
    }

    func deleteMusicDownloadTask(taskID: String) async throws {
        try await requestVoid(path: "/api/v1/downloads/\(taskID)", method: "DELETE")
    }

    func latestAppRelease() async throws -> AppReleaseInfo {
        var components = URLComponents(
            url: url(for: "/api/v1/app/releases/latest"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "platform", value: appReleasePlatform)
        ]
        let release: AppReleaseInfo = try await request(url: components.url!)
        if release.available,
           release.fileName?.lowercased().hasSuffix(".\(appReleaseExtension)") != true {
            throw APIError.invalidResponse
        }
        return release
    }

    func downloadAppRelease(
        _ release: AppReleaseInfo,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        guard let downloadURL = release.downloadURL,
              let version = release.version,
              let build = release.build else {
            throw APIError.invalidResponse
        }
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "Sona-\(version)-\(build).\(appReleaseExtension)")
        var request = URLRequest(url: url(for: downloadURL))
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = ReleaseDownloadDelegate(
                destination: destination,
                progress: progress,
                continuation: continuation
            )
            let configuration = URLSessionConfiguration.default
            configuration.httpCookieAcceptPolicy = .always
            configuration.httpCookieStorage = .shared
            configuration.timeoutIntervalForRequest = 60
            let downloadSession = URLSession(
                configuration: configuration,
                delegate: delegate,
                delegateQueue: nil
            )
            delegate.session = downloadSession
            downloadSession.downloadTask(with: request).resume()
        }
    }

    private var appReleasePlatform: String {
#if targetEnvironment(macCatalyst)
        "macos"
#else
        "ios"
#endif
    }

    private var appReleaseExtension: String {
#if targetEnvironment(macCatalyst)
        "dmg"
#else
        "ipa"
#endif
    }

    func retryMusicDownload(taskID: String) async throws -> MusicDownloadTask {
        try await request(path: "/api/v1/downloads/\(taskID)/retry", method: "POST")
    }

    func lyrics(for track: Track) async throws -> Lyrics {
        try await request(path: "/api/v1/tracks/\(track.id)/lyrics")
    }

    func data(at path: String) async throws -> Data {
        let (data, response) = try await session.data(from: url(for: path))
        try validate(response: response, data: data)
        return data
    }

    func download(at path: String) async throws -> URL {
        let (temporaryURL, response) = try await session.download(from: url(for: path))
        try validate(response: response, data: Data())
        return temporaryURL
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> T {
        try await request(url: url(for: path), method: method, body: body, timeout: timeout)
    }

    private func request<T: Decodable>(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if let timeout {
            request.timeoutInterval = timeout
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func requestVoid(path: String, method: String, body: Data? = nil) async throws {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = method
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    private func uploadAvatar<T: Decodable>(path: String, imageData: Data) async throws -> T {
        let boundary = "SonaAvatar-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"avatar.jpg\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        var request = URLRequest(url: url(for: path))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type"
        )
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            if http.statusCode == 401 {
                throw APIError.unauthorized
            }
            if http.statusCode == 403 {
                throw APIError.forbidden
            }
            let detail = String(data: data, encoding: .utf8)
            throw APIError.server(status: http.statusCode, detail: detail)
        }
    }

    private var childModeValue: String {
        UserDefaults.standard.bool(forKey: "childMode") ? "true" : "false"
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case importTimedOut
    case unauthorized
    case forbidden
    case server(status: Int, detail: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务器响应无效"
        case .importTimedOut:
            return "等待目录扫描完成超时，请稍后刷新歌单"
        case .unauthorized:
            return "账号、密码错误或登录已失效"
        case .forbidden:
            return "当前账号没有执行此操作的权限"
        case let .server(status, detail):
            if let message = Self.readableServerMessage(from: detail) {
                return message
            }
            return "服务器错误 \(status)"
        }
    }

    private static func readableServerMessage(from detail: String?) -> String? {
        guard let detail, !detail.isEmpty else { return nil }
        if let data = detail.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["detail", "message", "error"] {
                guard let message = object[key] as? String,
                      !message.isEmpty,
                      !["Bad Request", "Internal Server Error", "Not Found"].contains(message) else {
                    continue
                }
                return message
            }
            return nil
        }
        return detail
    }
}

private final class ReleaseDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let destination: URL
    let progress: (Double) -> Void
    var continuation: CheckedContinuation<URL, Error>?
    var session: URLSession?
    private var result: Result<URL, Error>?

    init(
        destination: URL,
        progress: @escaping (Double) -> Void,
        continuation: CheckedContinuation<URL, Error>
    ) {
        self.destination = destination
        self.progress = progress
        self.continuation = continuation
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let value = min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        DispatchQueue.main.async { [progress] in progress(value) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let response = downloadTask.response as? HTTPURLResponse else {
            result = .failure(APIError.invalidResponse)
            return
        }
        guard 200..<300 ~= response.statusCode else {
            result = .failure(APIError.server(status: response.statusCode, detail: nil))
            return
        }
        do {
            try FileManager.default.removeItemIfPresent(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            result = .success(destination)
        } catch {
            result = .failure(error)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let outcome = error.map(Result.failure) ?? result ?? .failure(APIError.invalidResponse)
        continuation?.resume(with: outcome)
        continuation = nil
        self.session?.finishTasksAndInvalidate()
        self.session = nil
    }
}

private extension FileManager {
    func removeItemIfPresent(at url: URL) throws {
        if fileExists(atPath: url.path) {
            try removeItem(at: url)
        }
    }
}
