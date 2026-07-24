import AVFoundation
import CryptoKit
import Foundation
import UniformTypeIdentifiers

private struct PlaybackByteRange: Codable, Equatable {
    let lowerBound: Int64
    let upperBound: Int64
}

private enum PlaybackByteRanges {
    static func merging(
        _ ranges: [PlaybackByteRange],
        with newRange: PlaybackByteRange
    ) -> [PlaybackByteRange] {
        guard newRange.lowerBound < newRange.upperBound else { return ranges }
        var result: [PlaybackByteRange] = []
        var pending = newRange
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if range.upperBound < pending.lowerBound {
                result.append(range)
            } else if pending.upperBound < range.lowerBound {
                result.append(pending)
                pending = range
            } else {
                pending = PlaybackByteRange(
                    lowerBound: min(pending.lowerBound, range.lowerBound),
                    upperBound: max(pending.upperBound, range.upperBound)
                )
            }
        }
        result.append(pending)
        return result
    }

    static func cachedRange(
        containing offset: Int64,
        in ranges: [PlaybackByteRange]
    ) -> PlaybackByteRange? {
        ranges.first { $0.lowerBound <= offset && offset < $0.upperBound }
    }
}

private struct PlaybackCacheMetadata: Codable {
    let originalURL: String
    var contentLength: Int64?
    var contentType: String?
    var supportsByteRanges: Bool
    var ranges: [PlaybackByteRange]
    var lastAccessedAt: Date
}

private struct PlaybackCacheInfo {
    let contentLength: Int64?
    let contentType: String?
    let supportsByteRanges: Bool
}

private actor PlaybackCacheStore {
    static let shared = PlaybackCacheStore()

    private let fileManager = FileManager.default
    private let maximumCacheBytes: Int64 = 2 * 1_024 * 1_024 * 1_024
    private let pruneIntervalBytes: Int64 = 64 * 1_024 * 1_024
    private let directoryURL: URL
    private var bytesWrittenSinceLastPrune: Int64

    private init() {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        directoryURL = applicationSupport
            .appendingPathComponent("Sona", isDirectory: true)
            .appendingPathComponent("PlaybackCache", isDirectory: true)
        bytesWrittenSinceLastPrune = pruneIntervalBytes
        try? fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var cacheDirectory = directoryURL
        try? cacheDirectory.setResourceValues(values)
    }

    func info(for key: String, originalURL: URL) -> PlaybackCacheInfo? {
        guard var metadata = loadMetadata(for: key),
              metadata.originalURL == originalURL.absoluteString else { return nil }
        metadata.lastAccessedAt = Date()
        saveMetadata(metadata, for: key)
        return PlaybackCacheInfo(
            contentLength: metadata.contentLength,
            contentType: metadata.contentType,
            supportsByteRanges: metadata.supportsByteRanges
        )
    }

    func read(
        key: String,
        originalURL: URL,
        offset: Int64,
        maximumLength: Int
    ) throws -> Data? {
        guard let metadata = loadMetadata(for: key),
              metadata.originalURL == originalURL.absoluteString,
              let range = PlaybackByteRanges.cachedRange(
                  containing: offset,
                  in: metadata.ranges
              ) else { return nil }
        let availableLength = min(
            Int64(maximumLength),
            range.upperBound - offset
        )
        guard availableLength > 0 else { return nil }
        let handle = try FileHandle(forReadingFrom: dataURL(for: key))
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: Int(availableLength)) ?? Data()
        guard !data.isEmpty else { return nil }
        return data
    }

    func write(
        _ data: Data,
        key: String,
        originalURL: URL,
        offset: Int64,
        contentLength: Int64?,
        contentType: String?,
        supportsByteRanges: Bool
    ) throws {
        guard !data.isEmpty else { return }
        let dataURL = dataURL(for: key)
        if !fileManager.fileExists(atPath: dataURL.path) {
            fileManager.createFile(atPath: dataURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: dataURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        try handle.write(contentsOf: data)

        var metadata = loadMetadata(for: key) ?? PlaybackCacheMetadata(
            originalURL: originalURL.absoluteString,
            contentLength: nil,
            contentType: nil,
            supportsByteRanges: false,
            ranges: [],
            lastAccessedAt: Date()
        )
        metadata.contentLength = contentLength ?? metadata.contentLength
        metadata.contentType = contentType ?? metadata.contentType
        metadata.supportsByteRanges = supportsByteRanges
            || metadata.supportsByteRanges
        metadata.ranges = PlaybackByteRanges.merging(
            metadata.ranges,
            with: PlaybackByteRange(
                lowerBound: offset,
                upperBound: offset + Int64(data.count)
            )
        )
        metadata.lastAccessedAt = Date()
        saveMetadata(metadata, for: key)
        bytesWrittenSinceLastPrune += Int64(data.count)
        if bytesWrittenSinceLastPrune >= pruneIntervalBytes {
            pruneIfNeeded(excluding: key)
            bytesWrittenSinceLastPrune = 0
        }
    }

    private func pruneIfNeeded(excluding activeKey: String) {
        let metadataURLs = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ))?.filter { $0.pathExtension == "json" } ?? []
        var entries: [(key: String, bytes: Int64, lastAccessedAt: Date)] = []
        var totalBytes: Int64 = 0
        for url in metadataURLs {
            let key = url.deletingPathExtension().lastPathComponent
            guard let metadata = loadMetadata(for: key) else { continue }
            let bytes = metadata.ranges.reduce(Int64(0)) {
                $0 + max(0, $1.upperBound - $1.lowerBound)
            }
            totalBytes += bytes
            entries.append((key, bytes, metadata.lastAccessedAt))
        }
        guard totalBytes > maximumCacheBytes else { return }
        for entry in entries
            .filter({ $0.key != activeKey })
            .sorted(by: { $0.lastAccessedAt < $1.lastAccessedAt }) {
            try? fileManager.removeItem(at: dataURL(for: entry.key))
            try? fileManager.removeItem(at: metadataURL(for: entry.key))
            totalBytes -= entry.bytes
            if totalBytes <= maximumCacheBytes {
                break
            }
        }
    }

    private func loadMetadata(for key: String) -> PlaybackCacheMetadata? {
        guard let data = try? Data(contentsOf: metadataURL(for: key)) else {
            return nil
        }
        return try? JSONDecoder().decode(PlaybackCacheMetadata.self, from: data)
    }

    private func saveMetadata(_ metadata: PlaybackCacheMetadata, for key: String) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: metadataURL(for: key), options: .atomic)
    }

    private func dataURL(for key: String) -> URL {
        directoryURL.appendingPathComponent(key).appendingPathExtension("media")
    }

    private func metadataURL(for key: String) -> URL {
        directoryURL.appendingPathComponent(key).appendingPathExtension("json")
    }
}

private struct PlaybackHTTPResponse {
    let data: Data
    let responseStart: Int64
    let contentLength: Int64?
    let contentType: String?
    let supportsByteRanges: Bool
}

private enum PlaybackCacheError: LocalizedError {
    case invalidResponse
    case invalidStatusCode(Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "音频服务器返回了无效响应"
        case let .invalidStatusCode(code):
            "音频服务器返回错误 \(code)"
        case .emptyResponse:
            "音频服务器没有返回数据"
        }
    }
}

final class PlaybackCacheResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    private let originalURL: URL
    private let cacheKey: String
    private let delegateQueue = DispatchQueue(label: "cc.eu.sosee.sona.playback-cache")
    private let lock = NSLock()
    private let session: URLSession
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(originalURL: URL) {
        self.originalURL = originalURL
        cacheKey = SHA256.hash(data: Data(originalURL.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration)
        super.init()
    }

    func makeAsset() -> AVURLAsset {
        let assetURL = URL(string: "sona-cache://\(cacheKey)")!
        let asset = AVURLAsset(url: assetURL)
        asset.resourceLoader.setDelegate(self, queue: delegateQueue)
        return asset
    }

    func cancelAll() {
        lock.lock()
        let activeTasks = Array(tasks.values)
        tasks.removeAll()
        lock.unlock()
        activeTasks.forEach { $0.cancel() }
        session.invalidateAndCancel()
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        let identifier = ObjectIdentifier(loadingRequest)
        lock.lock()
        let task = Task { [weak self, weak loadingRequest] in
            defer { self?.removeTask(identifier) }
            guard let self, let loadingRequest else { return }
            do {
                try await self.fulfill(loadingRequest)
                guard !Task.isCancelled else { return }
                loadingRequest.finishLoading()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                loadingRequest.finishLoading(with: error)
            }
        }
        tasks[identifier] = task
        lock.unlock()
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let identifier = ObjectIdentifier(loadingRequest)
        lock.lock()
        let task = tasks.removeValue(forKey: identifier)
        lock.unlock()
        task?.cancel()
    }

    private func fulfill(
        _ loadingRequest: AVAssetResourceLoadingRequest
    ) async throws {
        let info = try await ensureContentInformation()
        if let informationRequest = loadingRequest.contentInformationRequest {
            informationRequest.contentLength = info.contentLength ?? 0
            informationRequest.isByteRangeAccessSupported = info.supportsByteRanges
            informationRequest.contentType = uniformTypeIdentifier(
                for: info.contentType
            )
        }
        guard let dataRequest = loadingRequest.dataRequest else { return }
        let requestedOffset = max(0, dataRequest.requestedOffset)
        var offset = dataRequest.currentOffset > 0
            ? dataRequest.currentOffset
            : requestedOffset
        let requestedEnd: Int64
        if dataRequest.requestsAllDataToEndOfResource {
            requestedEnd = info.contentLength ?? Int64.max
        } else {
            requestedEnd = requestedOffset + Int64(dataRequest.requestedLength)
        }
        let targetEnd = min(info.contentLength ?? requestedEnd, requestedEnd)

        while offset < targetEnd {
            try Task.checkCancellation()
            let remaining = targetEnd - offset
            let chunkLength = Int(min(remaining, 1_024 * 1_024))
            if let cached = try await PlaybackCacheStore.shared.read(
                key: cacheKey,
                originalURL: originalURL,
                offset: offset,
                maximumLength: chunkLength
            ) {
                dataRequest.respond(with: cached)
                offset += Int64(cached.count)
                continue
            }

            let response = try await fetchWithRetry(
                range: offset..<(offset + Int64(chunkLength))
            )
            try await PlaybackCacheStore.shared.write(
                response.data,
                key: cacheKey,
                originalURL: originalURL,
                offset: response.responseStart,
                contentLength: response.contentLength,
                contentType: response.contentType,
                supportsByteRanges: response.supportsByteRanges
            )
            guard let cached = try await PlaybackCacheStore.shared.read(
                key: cacheKey,
                originalURL: originalURL,
                offset: offset,
                maximumLength: chunkLength
            ) else {
                throw PlaybackCacheError.emptyResponse
            }
            dataRequest.respond(with: cached)
            offset += Int64(cached.count)
        }
    }

    private func ensureContentInformation() async throws -> PlaybackCacheInfo {
        if let info = await PlaybackCacheStore.shared.info(
            for: cacheKey,
            originalURL: originalURL
        ), info.contentLength != nil {
            return info
        }
        let response = try await fetchWithRetry(range: 0..<2)
        guard let contentLength = response.contentLength, contentLength > 0 else {
            throw PlaybackCacheError.invalidResponse
        }
        try await PlaybackCacheStore.shared.write(
            response.data,
            key: cacheKey,
            originalURL: originalURL,
            offset: response.responseStart,
            contentLength: response.contentLength,
            contentType: response.contentType,
            supportsByteRanges: response.supportsByteRanges
        )
        return PlaybackCacheInfo(
            contentLength: contentLength,
            contentType: response.contentType,
            supportsByteRanges: response.supportsByteRanges
        )
    }

    private func fetchWithRetry(
        range: Range<Int64>
    ) async throws -> PlaybackHTTPResponse {
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                return try await fetch(range: range)
            } catch {
                lastError = error
                guard attempt == 0 else { break }
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        throw lastError ?? PlaybackCacheError.emptyResponse
    }

    private func fetch(range: Range<Int64>) async throws -> PlaybackHTTPResponse {
        var request = URLRequest(url: originalURL)
        request.setValue(
            "bytes=\(range.lowerBound)-\(range.upperBound - 1)",
            forHTTPHeaderField: "Range"
        )
        let cookies = HTTPCookieStorage.shared.cookies(for: originalURL) ?? []
        for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlaybackCacheError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PlaybackCacheError.invalidStatusCode(httpResponse.statusCode)
        }
        let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range")
        let parsedRange = parseContentRange(contentRange)
        let responseStart = httpResponse.statusCode == 206
            ? parsedRange?.start ?? range.lowerBound
            : 0
        let contentLength = parsedRange?.total
            ?? (httpResponse.statusCode == 200 && httpResponse.expectedContentLength > 0
                ? httpResponse.expectedContentLength
                : nil)
        let acceptsRanges = httpResponse.value(
            forHTTPHeaderField: "Accept-Ranges"
        )?.lowercased() == "bytes"
        return PlaybackHTTPResponse(
            data: data,
            responseStart: responseStart,
            contentLength: contentLength,
            contentType: httpResponse.mimeType,
            supportsByteRanges: httpResponse.statusCode == 206 || acceptsRanges
        )
    }

    private func parseContentRange(
        _ value: String?
    ) -> (start: Int64, total: Int64)? {
        guard let value,
              let rangeAndTotal = value.split(separator: " ").last else {
            return nil
        }
        let sections = rangeAndTotal.split(separator: "/")
        guard sections.count == 2,
              let total = Int64(sections[1]),
              let startText = sections[0].split(separator: "-").first,
              let start = Int64(startText) else { return nil }
        return (start, total)
    }

    private func uniformTypeIdentifier(for mimeType: String?) -> String {
        if let mimeType, let type = UTType(mimeType: mimeType) {
            return type.identifier
        }
        return UTType.audio.identifier
    }

    private func removeTask(_ identifier: ObjectIdentifier) {
        lock.lock()
        tasks.removeValue(forKey: identifier)
        lock.unlock()
    }
}
