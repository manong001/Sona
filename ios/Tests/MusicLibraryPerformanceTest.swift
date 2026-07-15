import Foundation

@main
struct MusicLibraryPerformanceTest {
    static func main() throws {
        let count = 12_000
        let payload = (0..<count).map { index in
            [
                "id": "track-\(index)",
                "title": "歌曲 \(index)",
                "artist": "艺人 \(index % 300)",
                "album": "专辑 \(index % 800)",
                "durationMs": 180_000,
                "codec": "AAC",
                "fileExtension": "m4a",
                "streamURL": "/tracks/\(index)/stream",
                "hasLyrics": false,
                "metadataStatus": "LOCAL"
            ] as [String: Any]
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        let tracks = try JSONDecoder().decode([Track].self, from: data)
        let lookup = LibraryTrackLookup(tracks)
        let ids = (0..<count).reversed().map { "track-\($0)" }

        let started = ContinuousClock.now
        for _ in 0..<3 {
            for id in ids {
                precondition(lookup.track(id: id) != nil)
            }
        }
        let elapsed = started.duration(to: .now)
        let seconds = Double(elapsed.components.seconds) +
            Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
        fputs(String(format: "Music library lookup: %.3f s\n", seconds), stdout)
        fflush(stdout)
        precondition(seconds < 0.25, "音乐库 ID 查找耗时过高")
    }
}
