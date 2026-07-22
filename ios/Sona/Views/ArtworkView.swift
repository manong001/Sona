import SwiftUI
import UIKit

struct ArtworkView: View {
    let path: String?
    var cornerRadius: CGFloat = 8
    var thumbnailSize: Int? = 768
    var onColorResolved: ((Color) -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            CachedRemoteImage(url: artworkURL) { image in
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.sonaSurface)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .onAppear {
                            if let color = image.sonaHeaderColor {
                                onColorResolved?(Color(uiColor: color))
                            }
                        }
                }
            } placeholder: {
                ZStack {
                    LinearGradient(
                        colors: [Color.sonaGreen.opacity(0.78), Color(red: 0.04, green: 0.20, blue: 0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note.list")
                        .font(.title2.bold())
                        .foregroundStyle(.white.opacity(0.88))
                        .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var artworkURL: URL? {
        sonaArtworkURL(path: path, thumbnailSize: thumbnailSize)
    }
}

private extension UIImage {
    var sonaHeaderColor: UIColor? {
        guard let cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let rendered = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard rendered, pixel[3] > 0 else { return nil }

        let average = UIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard average.getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        ) else { return average }
        if saturation < 0.08 {
            return UIColor(white: min(max(brightness, 0.22), 0.42), alpha: 1)
        }
        return UIColor(
            hue: hue,
            saturation: min(max(saturation, 0.32), 0.72),
            brightness: min(max(brightness, 0.28), 0.52),
            alpha: 1
        )
    }
}

func sonaArtworkURL(path: String?, thumbnailSize: Int?) -> URL? {
    guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
          !path.isEmpty else { return nil }
    let url = APIClient.shared.url(for: path)
    guard let thumbnailSize,
          var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return url
    }
    var queryItems = components.queryItems ?? []
    queryItems.removeAll { $0.name == "size" }
    queryItems.append(URLQueryItem(name: "size", value: String(thumbnailSize)))
    components.queryItems = queryItems
    return components.url
}

func sonaArtworkPaths(_ paths: [String]) -> [String] {
    var seen = Set<String>()
    return paths.compactMap { path in
        let value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, seen.insert(value).inserted else { return nil }
        return value
    }
}

func sonaFirstArtworkURL(in tracks: [Track]) -> String? {
    sonaArtworkPaths(tracks.compactMap(\.artworkURL)).first
}
