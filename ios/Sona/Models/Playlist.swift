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
