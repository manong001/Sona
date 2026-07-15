import Foundation

@MainActor
final class OfflineStore: ObservableObject {
    @Published private(set) var downloadedIDs: Set<String> = []
    @Published private(set) var activeDownloads: Set<String> = []
    @Published var errorMessage: String?
    @Published private(set) var failedDownloadIDs: Set<String> = []

    private let directory: URL
    private let defaultsKey = "offlineTracks"
    private var files: [String: String]

    init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        directory = applicationSupport.appending(path: "Sona/Offline", directoryHint: .isDirectory)
        files = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        downloadedIDs = Set(files.compactMap { id, filename in
            FileManager.default.fileExists(atPath: directory.appending(path: filename).path) ? id : nil
        })
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func localURL(for track: Track) -> URL? {
        guard let filename = files[track.id] else { return nil }
        let target = directory.appending(path: filename)
        return FileManager.default.fileExists(atPath: target.path) ? target : nil
    }

    func download(_ track: Track, api: APIClient = .shared) async {
        guard !activeDownloads.contains(track.id) else { return }
        activeDownloads.insert(track.id)
        errorMessage = nil
        defer { activeDownloads.remove(track.id) }
        do {
            let temporaryURL = try await api.download(at: track.streamURL)
            let allowed = track.fileExtension.lowercased().filter { $0.isLetter || $0.isNumber }
            let filename = track.id + "." + (allowed.isEmpty ? "audio" : allowed)
            let target = directory.appending(path: filename)
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: target)
            files[track.id] = filename
            downloadedIDs.insert(track.id)
            persist()
            failedDownloadIDs.remove(track.id)
        } catch {
            failedDownloadIDs.insert(track.id)
            errorMessage = error.localizedDescription
        }
    }

    func downloadAll(_ tracks: [Track], api: APIClient = .shared) async {
        for track in tracks where !downloadedIDs.contains(track.id) {
            if Task.isCancelled { return }
            await download(track, api: api)
        }
    }

    func removeAll() {
        for filename in files.values {
            try? FileManager.default.removeItem(at: directory.appending(path: filename))
        }
        files.removeAll()
        downloadedIDs.removeAll()
        failedDownloadIDs.removeAll()
        persist()
    }

    var storageBytes: Int64 {
        files.values.reduce(0) { total, filename in
            let values = try? directory.appending(path: filename).resourceValues(forKeys: [.fileSizeKey])
            return total + Int64(values?.fileSize ?? 0)
        }
    }

    func remove(_ track: Track) {
        guard let filename = files.removeValue(forKey: track.id) else { return }
        try? FileManager.default.removeItem(at: directory.appending(path: filename))
        downloadedIDs.remove(track.id)
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(files, forKey: defaultsKey)
    }
}
