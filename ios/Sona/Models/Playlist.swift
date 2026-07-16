import Foundation

struct Playlist: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let trackIDs: [String]
    let createdAt: Int64

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt
        case trackIDs = "trackIds"
    }
}

struct FavoritesResponse: Decodable {
    let trackIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case trackIDs = "trackIds"
    }
}

struct DirectoryImportResponse: Decodable {
    let importedCount: Int
    let importRecordID: String?
    let scanning: Bool?

    private enum CodingKeys: String, CodingKey {
        case importedCount
        case importRecordID = "importRecordId"
        case scanning
    }
}

enum ImportRecordType: String, Codable {
    case localFiles = "LOCAL_FILES"
    case favoriteDirectory = "FAVORITE_DIRECTORY"
    case playlistDirectory = "PLAYLIST_DIRECTORY"

    var title: String {
        switch self {
        case .localFiles: "本地文件导入"
        case .favoriteDirectory: "目录导入收藏"
        case .playlistDirectory: "目录导入歌单"
        }
    }
}

enum ImportRecordState: String, Codable {
    case running = "RUNNING"
    case completed = "COMPLETED"
    case failed = "FAILED"

    var title: String {
        switch self {
        case .running: "进行中"
        case .completed: "已完成"
        case .failed: "失败"
        }
    }
}

struct ImportRecord: Decodable, Identifiable {
    let id: String
    let type: ImportRecordType
    let source: String
    let target: String
    let state: ImportRecordState
    let total: Int
    let succeeded: Int
    let failed: Int
    let discovered: Int
    let imported: Int
    let updated: Int
    let skipped: Int
    let added: Int
    let message: String?
    let createdAt: Int64
    let updatedAt: Int64
}

struct ImportRecordUpdate: Encodable {
    let state: ImportRecordState
    var total: Int?
    var succeeded: Int?
    var failed: Int?
    var discovered: Int?
    var imported: Int?
    var updated: Int?
    var skipped: Int?
    var added: Int?
    var message: String?
}

struct LocalUploadResult {
    let succeeded: Int
    let failed: Int
    let message: String?
}

struct AchievementSummary: Decodable {
    let level: AchievementLevel
    let stats: AchievementStats
    let badges: [AchievementBadge]
    let history: [AchievementHistoryItem]
}

struct AchievementLevel: Decodable {
    let id: String
    let title: String
    let englishTitle: String
    let icon: String
    let minimum: Int
    let nextTitle: String?
    let nextThreshold: Int?
}

struct AchievementStats: Decodable {
    let total: Int
    let today: Int
    let uniqueTracks: Int
    let bestDaily: Int
    let longestStreak: Int
    let nightListens: Int
    let listenedMs: Int64
}

struct AchievementBadge: Decodable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let unlocked: Bool
}

struct AchievementHistoryItem: Decodable, Identifiable {
    let trackId: String
    let title: String
    let artist: String
    let listenedMs: Int64
    let progressPercent: Double
    let playedAt: Int64

    var id: String { "\(trackId)-\(playedAt)" }
}

func scanRecordUpdate(
    state: ImportRecordState,
    status: ScanStatus?,
    succeeded: Int? = nil,
    failed: Int? = nil,
    added: Int? = nil,
    message: String? = nil
) -> ImportRecordUpdate {
    ImportRecordUpdate(
        state: state,
        total: status?.discovered,
        succeeded: succeeded,
        failed: failed ?? status?.failed,
        discovered: status?.discovered,
        imported: status?.imported,
        updated: status?.updated,
        skipped: status?.skipped,
        added: added,
        message: message
    )
}

struct HistoryResponse: Decodable {
    let items: [HistoryItem]
}

struct HistoryItem: Decodable, Identifiable {
    let trackID: String
    let playedAt: Int64

    var id: String { "\(trackID)-\(playedAt)" }

    private enum CodingKeys: String, CodingKey {
        case trackID = "trackId"
        case playedAt
    }
}
