import Foundation

enum ScrapeMode: String {
    case missingOnly = "MISSING_ONLY"
    case overwrite = "OVERWRITE"
}

struct Playlist: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let trackIDs: [String]
    let artworkURLs: [String]
    let artworkTrackID: String?
    let createdAt: Int64
    let featured: Bool
    let directoryPath: String?
    let poolType: String
    let shownOnHome: Bool
    let homePosition: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, featured, directoryPath, poolType, shownOnHome, homePosition
        case trackIDs = "trackIds"
        case artworkURLs = "artworkUrls"
        case artworkTrackID = "artworkTrackId"
    }

    init(
        id: String, name: String, trackIDs: [String], artworkURLs: [String] = [],
        artworkTrackID: String? = nil, createdAt: Int64,
        featured: Bool = false, directoryPath: String? = nil, poolType: String = "NORMAL",
        shownOnHome: Bool = false, homePosition: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.trackIDs = trackIDs
        self.artworkURLs = artworkURLs
        self.artworkTrackID = artworkTrackID
        self.createdAt = createdAt
        self.featured = featured
        self.directoryPath = directoryPath
        self.poolType = poolType
        self.shownOnHome = shownOnHome
        self.homePosition = homePosition
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        trackIDs = try values.decode([String].self, forKey: .trackIDs)
        artworkURLs = try values.decodeIfPresent([String].self, forKey: .artworkURLs) ?? []
        artworkTrackID = try values.decodeIfPresent(String.self, forKey: .artworkTrackID)
        createdAt = try values.decode(Int64.self, forKey: .createdAt)
        featured = try values.decodeIfPresent(Bool.self, forKey: .featured) ?? false
        directoryPath = try values.decodeIfPresent(String.self, forKey: .directoryPath)
        poolType = try values.decodeIfPresent(String.self, forKey: .poolType) ?? "NORMAL"
        shownOnHome = try values.decodeIfPresent(Bool.self, forKey: .shownOnHome) ?? false
        homePosition = try values.decodeIfPresent(Int.self, forKey: .homePosition)
    }

    var isDirectoryPlaylist: Bool { directoryPath != nil }

    func withShownOnHome(_ shown: Bool) -> Playlist {
        Playlist(
            id: id, name: name, trackIDs: trackIDs, artworkURLs: artworkURLs,
            artworkTrackID: artworkTrackID, createdAt: createdAt, featured: featured,
            directoryPath: directoryPath, poolType: poolType, shownOnHome: shown,
            homePosition: shown ? homePosition : nil
        )
    }

    func withHomePosition(_ position: Int) -> Playlist {
        Playlist(
            id: id, name: name, trackIDs: trackIDs, artworkURLs: artworkURLs,
            artworkTrackID: artworkTrackID, createdAt: createdAt, featured: featured,
            directoryPath: directoryPath, poolType: poolType, shownOnHome: shownOnHome,
            homePosition: position
        )
    }
}

struct FavoritesResponse: Decodable {
    let trackIDs: [String]
    let shownOnHome: Bool?
    let homePosition: Int?

    private enum CodingKeys: String, CodingKey {
        case trackIDs = "trackIds"
        case shownOnHome, homePosition
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

struct MadeForYouMix: Decodable, Identifiable {
    let id: String
    let artist: String
    let tracks: [Track]
}
