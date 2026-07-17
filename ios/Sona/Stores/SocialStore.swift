import Foundation
import CoreTransferable
import UniformTypeIdentifiers

@MainActor
final class SocialStore: ObservableObject {
    @Published private(set) var profile: SocialUser?
    @Published private(set) var friends: [SocialUser] = []
    @Published private(set) var conversations: [SocialUser] = []
    @Published private(set) var moments: [SocialMoment] = []
    @Published private(set) var messages: [String: [SocialMessage]] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60 * 60
        session = URLSession(configuration: configuration)
    }

    func reset() {
        profile = nil
        friends = []
        conversations = []
        moments = []
        messages = [:]
        errorMessage = nil
    }

    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await loadProfile()
            try await loadFriends()
            try await loadConversations()
            try await loadMoments()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func heartbeat() async {
        do {
            try await requestVoid(path: "/api/v1/social/presence", method: "POST")
            try await loadFriends()
            try await loadConversations()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadProfile() async throws {
        profile = try await request(path: "/api/v1/social/profile")
    }

    func updateProfile(displayName: String, signature: String, avatarPreset: String?) async throws {
        struct Body: Encodable {
            let displayName: String
            let signature: String
            let avatarPreset: String?
        }
        profile = try await request(
            path: "/api/v1/social/profile",
            method: "PUT",
            body: Body(displayName: displayName, signature: signature, avatarPreset: avatarPreset)
        )
    }

    func searchUsers(_ query: String) async throws -> [SocialUser] {
        var components = URLComponents(
            url: APIClient.shared.url(for: "/api/v1/social/users"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "query", value: query)]
        return try await request(url: components.url!)
    }

    func loadFriends() async throws {
        friends = try await request(path: "/api/v1/social/friends")
    }

    func loadConversations() async throws {
        conversations = try await request(path: "/api/v1/social/conversations")
    }

    func addFriend(username: String) async throws {
        struct Body: Encodable { let username: String }
        struct Response: Decodable { let user: SocialUser }
        let _: Response = try await request(
            path: "/api/v1/social/friends", method: "POST", body: Body(username: username)
        )
        try await loadFriends()
    }

    func deleteFriend(_ user: SocialUser) async throws {
        try await requestVoid(path: "/api/v1/social/friends/\(user.id)", method: "DELETE")
        try await loadFriends()
        try await loadConversations()
    }

    func loadMessages(with peerId: String) async throws {
        messages[peerId] = try await request(path: "/api/v1/social/messages/\(peerId)")
        try await loadConversations()
    }

    func sendText(_ text: String, to peerId: String) async throws {
        try await send(kind: "TEXT", text: text, track: nil, to: peerId)
    }

    func sendSticker(_ sticker: String, to peerId: String) async throws {
        try await send(kind: "STICKER", text: sticker, track: nil, to: peerId)
    }

    func share(track: Track, with peerId: String) async throws {
        let payload = SharedTrackPayload(
            id: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            artworkURL: track.artworkURL
        )
        try await send(kind: "TRACK", text: "", track: payload, to: peerId)
    }

    func recall(_ message: SocialMessage, peerId: String) async throws {
        let updated: SocialMessage = try await request(
            path: "/api/v1/social/messages/\(message.id)/recall", method: "PUT"
        )
        guard var values = messages[peerId],
              let index = values.firstIndex(where: { $0.id == updated.id }) else { return }
        values[index] = updated
        messages[peerId] = values
    }

    func loadMoments() async throws {
        moments = try await request(path: "/api/v1/social/moments")
    }

    func publishMoment(text: String, mediaIds: [String]) async throws {
        struct Body: Encodable { let text: String; let mediaIds: [String] }
        let _: SocialMoment = try await request(
            path: "/api/v1/social/moments",
            method: "POST",
            body: Body(text: text, mediaIds: mediaIds)
        )
        try await loadMoments()
    }

    func deleteMoment(_ moment: SocialMoment) async throws {
        try await requestVoid(path: "/api/v1/social/moments/\(moment.id)", method: "DELETE")
        try await loadMoments()
    }

    func setMomentLiked(_ moment: SocialMoment, liked: Bool) async throws {
        try await requestVoid(
            path: "/api/v1/social/moments/\(moment.id)/like",
            method: liked ? "PUT" : "DELETE"
        )
        try await loadMoments()
    }

    func comment(momentId: String, body: String) async throws {
        struct Body: Encodable { let body: String }
        let _: SocialComment = try await request(
            path: "/api/v1/social/moments/\(momentId)/comments",
            method: "POST",
            body: Body(body: body)
        )
        try await loadMoments()
    }

    func uploadMedia(
        data: Data,
        filename: String,
        kind: String,
        mimeType: String,
        groupId: String? = nil,
        component: String? = nil
    ) async throws -> SocialMedia {
        let boundary = "SonaSocial-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        var request = URLRequest(url: mediaURL(
            kind: kind, filename: filename, groupId: groupId, component: component
        ))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (responseData, response) = try await session.data(for: request)
        return try decode(SocialMedia.self, data: responseData, response: response)
    }

    func uploadMedia(
        fileURL: URL,
        filename: String,
        kind: String,
        mimeType: String,
        groupId: String? = nil,
        component: String? = nil
    ) async throws -> SocialMedia {
        let boundary = "SonaSocial-\(UUID().uuidString)"
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sona-social-body-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: bodyURL)
        do {
            try handle.write(contentsOf: "--\(boundary)\r\n".data(using: .utf8)!)
            try handle.write(contentsOf: (
                "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n" +
                "Content-Type: \(mimeType)\r\n\r\n"
            ).data(using: .utf8)!)
            let source = try FileHandle(forReadingFrom: fileURL)
            while let chunk = try source.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                try handle.write(contentsOf: chunk)
            }
            try source.close()
            try handle.write(contentsOf: "\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: bodyURL)
            throw error
        }
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        var request = URLRequest(url: mediaURL(
            kind: kind, filename: filename, groupId: groupId, component: component
        ))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.upload(for: request, fromFile: bodyURL)
        return try decode(SocialMedia.self, data: data, response: response)
    }

    func resolvedURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        return APIClient.shared.url(for: value)
    }

    private func send(
        kind: String,
        text: String,
        track: SharedTrackPayload?,
        to peerId: String
    ) async throws {
        struct Body: Encodable {
            let recipientId: String
            let clientMessageId: String
            let kind: String
            let text: String
            let payload: SharedTrackPayload?
        }
        let message: SocialMessage = try await request(
            path: "/api/v1/social/messages",
            method: "POST",
            body: Body(
                recipientId: peerId,
                clientMessageId: UUID().uuidString,
                kind: kind,
                text: text,
                payload: track
            )
        )
        messages[peerId, default: []].append(message)
        try await loadConversations()
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET"
    ) async throws -> T {
        try await request(url: APIClient.shared.url(for: path), method: method, body: Optional<Data>.none)
    }

    private func request<T: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> T {
        try await request(
            url: APIClient.shared.url(for: path),
            method: method,
            body: try JSONEncoder().encode(body)
        )
    }

    private func request<T: Decodable>(url: URL) async throws -> T {
        try await request(url: url, method: "GET", body: Optional<Data>.none)
    }

    private func request<T: Decodable>(
        url: URL,
        method: String,
        body: Data?
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        return try decode(T.self, data: data, response: response)
    }

    private func requestVoid(path: String, method: String) async throws {
        var request = URLRequest(url: APIClient.shared.url(for: path))
        request.httpMethod = method
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    private func decode<T: Decodable>(_ type: T.Type, data: Data, response: URLResponse) throws -> T {
        try validate(response: response, data: data)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SocialServiceError(message: "社交服务数据格式不兼容：\(error.localizedDescription)")
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SocialServiceError(message: "服务器无响应")
        }
        guard 200..<300 ~= http.statusCode else {
            struct Problem: Decodable { let detail: String?; let title: String? }
            let problem = try? JSONDecoder().decode(Problem.self, from: data)
            throw SocialServiceError(
                message: problem?.detail ?? problem?.title ?? "请求失败（HTTP \(http.statusCode)）"
            )
        }
    }

    private func mediaURL(
        kind: String,
        filename: String,
        groupId: String?,
        component: String?
    ) -> URL {
        var components = URLComponents(
            url: APIClient.shared.url(for: "/api/v1/social/media"),
            resolvingAgainstBaseURL: false
        )!
        var items = [
            URLQueryItem(name: "kind", value: kind),
            URLQueryItem(name: "filename", value: filename),
        ]
        if let groupId { items.append(URLQueryItem(name: "groupId", value: groupId)) }
        if let component { items.append(URLQueryItem(name: "component", value: component)) }
        components.queryItems = items
        return components.url!
    }
}

struct SocialPickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { value in
            SentTransferredFile(value.url)
        } importing: { received in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("sona-social-video-\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return Self(url: destination)
        }
    }
}
