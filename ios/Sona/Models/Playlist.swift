import Foundation
import SwiftData

@Model
final class Playlist {
    @Attribute(.unique) var id: UUID
    var name: String
    var trackIDsJSON: String
    var createdAt: Date

    init(name: String) {
        id = UUID()
        self.name = name
        trackIDsJSON = "[]"
        createdAt = Date()
    }

    var trackIDs: [String] {
        get {
            guard let data = trackIDsJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else { return }
            trackIDsJSON = json
        }
    }

    func add(trackID: String) {
        var ids = trackIDs
        guard !ids.contains(trackID) else { return }
        ids.append(trackID)
        trackIDs = ids
    }

    func remove(trackID: String) {
        trackIDs = trackIDs.filter { $0 != trackID }
    }
}
