import SwiftUI
import UIKit

struct ArtworkView: View {
    let path: String?
    var cornerRadius: CGFloat = 8
    var thumbnailSize: Int? = 768

    var body: some View {
        GeometryReader { proxy in
            CachedRemoteImage(url: artworkURL) { image in
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.sonaSurface)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
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
