import ImageIO
import SwiftUI
import UIKit

final class RemoteImageCache: @unchecked Sendable {
    static let shared = RemoteImageCache()

    private let images = NSCache<NSURL, UIImage>()
    private let data = NSCache<NSURL, NSData>()
    private let urlCache: URLCache
    private let loader: RemoteImageLoader

    private init() {
        images.totalCostLimit = 128 * 1_024 * 1_024
        data.totalCostLimit = 64 * 1_024 * 1_024

        urlCache = URLCache(
            memoryCapacity: 64 * 1_024 * 1_024,
            diskCapacity: 512 * 1_024 * 1_024,
            diskPath: "sona.remote-images"
        )
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = urlCache
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpCookieStorage = .shared
        loader = RemoteImageLoader(
            session: URLSession(configuration: configuration),
            urlCache: urlCache
        )
    }

    func cachedImage(for url: URL) -> UIImage? {
        images.object(forKey: url as NSURL)
    }

    func storeImage(_ image: UIImage, for url: URL) {
        images.setObject(image, forKey: url as NSURL, cost: image.memoryCost)
    }

    func image(for url: URL) async throws -> UIImage {
        if let image = cachedImage(for: url) { return image }
        let bytes = try await data(for: url)
        let image = try await Self.decodeImage(bytes, for: url)
        storeImage(image, for: url)
        return image
    }

    func data(for url: URL) async throws -> Data {
        if let cached = cachedData(for: url) { return cached }
        let bytes = try await loader.data(for: url)
        data.setObject(bytes as NSData, forKey: url as NSURL, cost: bytes.count)
        return bytes
    }

    func prefetch(urls: [URL], maxConcurrentDownloads: Int = 4) async {
        var iterator = Array(Set(urls)).makeIterator()
        let concurrency = max(1, maxConcurrentDownloads)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<concurrency {
                guard let url = iterator.next() else { break }
                group.addTask { [self] in
                    _ = try? await data(for: url)
                }
            }

            while await group.next() != nil {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                guard let url = iterator.next() else { continue }
                group.addTask { [self] in
                    _ = try? await data(for: url)
                }
            }
        }
    }

    func removeAll() {
        images.removeAllObjects()
        data.removeAllObjects()
        urlCache.removeAllCachedResponses()
    }

    private func cachedData(for url: URL) -> Data? {
        data.object(forKey: url as NSURL) as Data?
    }

    private static func decodeImage(_ bytes: Data, for url: URL) async throws -> UIImage {
        let maxPixelSize = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems?.first(where: { $0.name == "size" })?.value.flatMap(Int.init) ?? 768

        return try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                guard let source = CGImageSourceCreateWithData(bytes as CFData, nil) else {
                    throw URLError(.cannotDecodeContentData)
                }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                    kCGImageSourceShouldCacheImmediately: true,
                ]
                guard let image = CGImageSourceCreateThumbnailAtIndex(
                    source,
                    0,
                    options as CFDictionary
                ) else {
                    throw URLError(.cannotDecodeContentData)
                }
                return UIImage(cgImage: image)
            }
        }.value
    }
}

private actor RemoteImageLoader {
    private let session: URLSession
    private let urlCache: URLCache
    private var inFlight: [URL: Task<Data, Error>] = [:]

    init(session: URLSession, urlCache: URLCache) {
        self.session = session
        self.urlCache = urlCache
    }

    func data(for url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        if let task = inFlight[url] {
            return try await task.value
        }

        let task = Task { [session, urlCache] in
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode else {
                throw URLError(.badServerResponse)
            }
            let cacheControl = http.value(forHTTPHeaderField: "Cache-Control")?.lowercased() ?? ""
            if !cacheControl.contains("no-store") {
                urlCache.storeCachedResponse(
                    CachedURLResponse(response: response, data: data, storagePolicy: .allowed),
                    for: request
                )
            }
            return data
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        return try await task.value
    }
}

struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL?
    private let content: (UIImage) -> Content
    private let placeholder: () -> Placeholder
    @State private var image: UIImage?

    init(
        url: URL?,
        @ViewBuilder content: @escaping (UIImage) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        _image = State(initialValue: url.flatMap(RemoteImageCache.shared.cachedImage(for:)))
    }

    var body: some View {
        Group {
            if let image {
                content(image)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let cached = RemoteImageCache.shared.cachedImage(for: url) {
                image = cached
                return
            }
            image = nil
            image = try? await RemoteImageCache.shared.image(for: url)
        }
    }
}

private extension UIImage {
    var memoryCost: Int {
        guard let cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
