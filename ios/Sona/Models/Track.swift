import Foundation

struct Track: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let trackNumber: Int?
    let durationMs: Int64
    let codec: String
    let fileExtension: String
    let sampleRate: Int?
    let bitDepth: Int?
    let artworkURL: String?
    let streamURL: String
    let hasLyrics: Bool
    let metadataStatus: String
    let poolType: String
    let audienceType: String
    let genre: String
    let region: String
    let artists: [String]

    private enum CodingKeys: String, CodingKey {
        case id, title, artist, album, trackNumber, durationMs, codec, fileExtension
        case sampleRate, bitDepth, artworkURL, streamURL, hasLyrics, metadataStatus
        case poolType, audienceType, genre, region, artists
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        artist = try values.decode(String.self, forKey: .artist)
        album = try values.decode(String.self, forKey: .album)
        trackNumber = try values.decodeIfPresent(Int.self, forKey: .trackNumber)
        durationMs = try values.decode(Int64.self, forKey: .durationMs)
        codec = try values.decode(String.self, forKey: .codec)
        fileExtension = try values.decode(String.self, forKey: .fileExtension)
        sampleRate = try values.decodeIfPresent(Int.self, forKey: .sampleRate)
        bitDepth = try values.decodeIfPresent(Int.self, forKey: .bitDepth)
        artworkURL = try values.decodeIfPresent(String.self, forKey: .artworkURL)
        streamURL = try values.decode(String.self, forKey: .streamURL)
        hasLyrics = try values.decode(Bool.self, forKey: .hasLyrics)
        metadataStatus = try values.decode(String.self, forKey: .metadataStatus)
        poolType = try values.decodeIfPresent(String.self, forKey: .poolType) ?? "NORMAL"
        audienceType = try values.decodeIfPresent(String.self, forKey: .audienceType) ?? "GENERAL"
        genre = try values.decodeIfPresent(String.self, forKey: .genre) ?? "未分类"
        region = try values.decodeIfPresent(String.self, forKey: .region) ?? "OTHER"
        artists = try values.decodeIfPresent([String].self, forKey: .artists) ?? [artist]
    }

    var durationText: String {
        let seconds = max(0, Int(durationMs / 1_000))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var qualityText: String {
        var parts = [codec]
        if let sampleRate {
            parts.append(String(format: "%.1f kHz", Double(sampleRate) / 1_000))
        }
        if let bitDepth {
            parts.append("\(bitDepth)-bit")
        }
        return parts.joined(separator: " · ")
    }
}

struct LibraryTrackLookup {
    private let tracksByID: [String: Track]

    init(_ tracks: [Track]) {
        tracksByID = Dictionary(
            tracks.map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
    }

    func track(id: String) -> Track? {
        tracksByID[id]
    }
}

struct TrackPage: Decodable {
    let items: [Track]
    let nextCursor: String?
}

struct ChartEntry: Decodable, Identifiable {
    let track: Track
    let playCount: Int64

    var id: String { track.id }
}

struct Lyrics: Decodable {
    let plain: String?
    let synced: String?
    let source: String?
}

struct ScanStatus: Decodable {
    let state: String
    let discovered: Int
    let imported: Int
    let updated: Int
    let skipped: Int
    let failed: Int
    let message: String?
    let errors: [String]?
}

struct ServerMusicDirectory: Decodable, Identifiable, Hashable {
    let path: String
    let name: String
    let hasChildren: Bool

    var id: String { path }
}

struct ServerMusicDirectoryListing: Decodable {
    let path: String
    let name: String
    let directories: [ServerMusicDirectory]
}

struct AppReleaseInfo: Decodable {
    let available: Bool
    let version: String?
    let build: Int?
    let notes: String?
    let publishedAt: Int64?
    let fileSizeBytes: Int64?
    let fileName: String?
    let downloadURL: String?

    func isNewer(thanVersion currentVersion: String, build currentBuild: Int) -> Bool {
        guard available, let version, let build else { return false }
        let remoteParts = numericVersionParts(version)
        let currentParts = numericVersionParts(currentVersion)
        let count = max(remoteParts.count, currentParts.count)
        for index in 0..<count {
            let remote = index < remoteParts.count ? remoteParts[index] : 0
            let current = index < currentParts.count ? currentParts[index] : 0
            if remote != current { return remote > current }
        }
        return build > currentBuild
    }

    var fileSizeText: String? {
        guard let fileSizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    private func numericVersionParts(_ value: String) -> [Int] {
        value.split(separator: ".").map { Int($0) ?? 0 }
    }
}

struct PlaybackState: Decodable {
    let queueType: String
    let queueContextId: String?
    let trackId: String
    let queueTrackIds: [String]
    let progressMs: Int64
    let updatedAt: Int64
}

enum UserRole: String, Codable, CaseIterable, Identifiable {
    case admin = "ADMIN"
    case user = "USER"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .admin: "管理员"
        case .user: "普通用户"
        }
    }
}

struct UserResponse: Decodable {
    let id: String
    let username: String
    let role: UserRole

    var isAdmin: Bool { role == .admin }
}

struct ManagedUser: Decodable, Identifiable {
    let id: String
    let username: String
    let role: UserRole
    let enabled: Bool
}
