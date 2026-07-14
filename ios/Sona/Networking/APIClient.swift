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

    func startScan() async throws -> ScanStatus {
        try await request(path: "/api/v1/library/scan", method: "POST")
    }

    func scanStatus() async throws -> ScanStatus {
        try await request(path: "/api/v1/library/scan/status")
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
        body: Data? = nil
    ) async throws -> T {
        try await request(url: url(for: path), method: method, body: body)
    }

    private func request<T: Decodable>(
        url: URL,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func requestVoid(path: String, method: String) async throws {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = method
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
            let detail = String(data: data, encoding: .utf8)
            throw APIError.server(status: http.statusCode, detail: detail)
        }
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case server(status: Int, detail: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务器响应无效"
        case .unauthorized:
            return "账号、密码错误或登录已失效"
        case let .server(status, detail):
            return detail?.isEmpty == false ? "服务器错误 \(status)：\(detail!)" : "服务器错误 \(status)"
        }
    }
}
