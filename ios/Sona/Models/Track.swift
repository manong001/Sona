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

struct TrackPage: Decodable {
    let items: [Track]
    let nextCursor: String?
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
