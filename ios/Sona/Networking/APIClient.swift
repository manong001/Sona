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
        return serverURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
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

    func playlists() async throws -> [Playlist] {
        try await request(path: "/api/v1/me/playlists")
    }

    func createPlaylist(name: String) async throws -> Playlist {
        struct Body: Encodable { let name: String }
        return try await request(
            path: "/api/v1/me/playlists",
            method: "POST",
            body: try encoder.encode(Body(name: name))
        )
    }

    func deletePlaylist(id: String) async throws {
        try await requestVoid(path: "/api/v1/me/playlists/\(id)", method: "DELETE")
    }

    func setPlaylistTrack(playlistID: String, trackID: String, isIncluded: Bool) async throws {
        try await requestVoid(
            path: "/api/v1/me/playlists/\(playlistID)/tracks/\(trackID)",
            method: isIncluded ? "PUT" : "DELETE"
        )
    }

    func history() async throws -> HistoryResponse {
        try await request(path: "/api/v1/me/history")
    }

    func recordPlayback(trackID: String) async throws {
        try await requestVoid(path: "/api/v1/me/history/\(trackID)", method: "POST")
    }

    func recordPlaybackCompletion(trackID: String) async throws {
        try await requestVoid(
            path: "/api/v1/me/history/\(trackID)/complete",
            method: "POST"
        )
    }

    func tracks(query: String, cursor: String?) async throws -> TrackPage {
        var components = URLComponents(url: url(for: "/api/v1/tracks"), resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "limit", value: "50")]
        if !query.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components.queryItems = queryItems
        return try await request(url: components.url!)
    }

    func randomTracks(limit: Int = 50) async throws -> [Track] {
        var components = URLComponents(
            url: url(for: "/api/v1/tracks/random"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        return try await request(url: components.url!)
    }

    func startScan() async throws -> ScanStatus {
        try await request(path: "/api/v1/library/scan", method: "POST")
    }

    func scanStatus() async throws -> ScanStatus {
        try await request(path: "/api/v1/library/scan/status")
    }

    func musicDownloadSources() async throws -> [DownloadSource] {
        try await request(path: "/api/v1/downloads/sources")
    }

    func searchMusicDownloads(query: String) async throws -> DownloadSearchResponse {
        var components = URLComponents(
            url: url(for: "/api/v1/downloads/search"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return try await request(url: components.url!, timeout: 180)
    }

    func queueMusicDownload(_ candidate: DownloadCandidate) async throws -> MusicDownloadTask {
        try await request(
            path: "/api/v1/downloads",
            method: "POST",
            body: try encoder.encode(candidate)
        )
    }

    func musicDownloadTasks() async throws -> [MusicDownloadTask] {
        try await request(path: "/api/v1/downloads")
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
}

enum APIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case forbidden
    case server(status: Int, detail: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务器响应无效"
        case .unauthorized:
            return "账号、密码错误或登录已失效"
        case .forbidden:
            return "当前账号没有执行此操作的权限"
        case let .server(status, detail):
            return detail?.isEmpty == false ? "服务器错误 \(status)：\(detail!)" : "服务器错误 \(status)"
        }
    }
}
