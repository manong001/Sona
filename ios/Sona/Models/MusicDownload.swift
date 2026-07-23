import Foundation

struct DownloadSource: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct OnlinePlaybackSource: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let enabled: Bool
}

struct DownloadCandidate: Codable, Identifiable, Hashable {
    let candidateId: String
    let source: String
    let sourceName: String
    let title: String
    let artist: String
    let album: String?
    let `extension`: String?
    let quality: String?
    let durationMs: Int64?
    let fileSizeBytes: Int64?
    let artworkUrl: String?
    let hasLyrics: Bool
    let downloadState: MusicDownloadState?

    var id: String { candidateId }

    var durationText: String? {
        guard let durationMs, durationMs > 0 else { return nil }
        let seconds = Int(durationMs / 1_000)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var fileSizeText: String? {
        guard let fileSizeBytes, fileSizeBytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }
}

struct DownloadSearchResponse: Decodable {
    let items: [DownloadCandidate]
}

struct DownloadPlaylistPreview: Decodable {
    let name: String
    let artworkUrl: String?
    let items: [DownloadCandidate]
}

struct PlaylistDownloadQueueResponse: Decodable {
    let playlistId: String
    let playlistName: String
    let tasks: [MusicDownloadTask]
}

struct PlaylistSubscription: Decodable, Identifiable {
    let id: String
    let playlistId: String
    let sourceUrl: String
    let name: String
    let poolType: String
    let autoDownload: Bool
    let syncIntervalHours: Int
    let enabled: Bool
    let lastSyncedAt: Int64?
    let lastError: String?
    let createdAt: Int64
    let updatedAt: Int64
    let itemCount: Int
    let matchedCount: Int
    let missingCount: Int
    let downloadingCount: Int
    let queuedCount: Int?
    let runningCount: Int?
    let suggestedCount: Int?
}

struct PlaylistSubscriptionItem: Decodable, Identifiable {
    let itemKey: String
    let position: Int
    let title: String
    let artist: String
    let album: String?
    let matchedTrackId: String?
    let state: String
    let suggestions: [PlaylistSubscriptionMatchSuggestion]

    var id: String { itemKey }
}

struct PlaylistSubscriptionItemPage: Decodable {
    let items: [PlaylistSubscriptionItem]
    let hasMore: Bool
}

struct PlaylistSubscriptionBestMatchResult: Decodable {
    let subscription: PlaylistSubscription
    let matchedCount: Int
}

struct PlaylistSubscriptionMatchSuggestion: Decodable, Identifiable {
    let trackId: String
    let title: String
    let artist: String
    let album: String?
    let durationMs: Int64
    let score: Int

    var id: String { trackId }

    var durationText: String {
        let seconds = Int(durationMs / 1_000)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

enum MusicDownloadState: String, Codable {
    case queued = "QUEUED"
    case running = "RUNNING"
    case completed = "COMPLETED"
    case failed = "FAILED"

    var title: String {
        switch self {
        case .queued: "等待中"
        case .running: "下载中"
        case .completed: "已入库"
        case .failed: "失败"
        }
    }
}

struct MusicDownloadTask: Decodable, Identifiable {
    let id: String
    let candidateId: String
    let source: String
    let sourceName: String
    let title: String
    let artist: String
    let album: String
    let quality: String
    let artworkUrl: String?
    let targetPlaylistId: String?
    let requestedBy: String
    let state: MusicDownloadState
    let files: [String]
    let message: String?
    let createdAt: Int64
    let updatedAt: Int64
}
