import Foundation

struct DownloadSource: Codable, Identifiable, Hashable {
    let id: String
    let name: String
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
    let requestedBy: String
    let state: MusicDownloadState
    let files: [String]
    let message: String?
    let createdAt: Int64
    let updatedAt: Int64
}
