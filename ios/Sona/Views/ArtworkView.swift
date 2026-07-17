import SwiftUI
import UIKit

struct ArtworkView: View {
    let path: String?
    var cornerRadius: CGFloat = 8

    var body: some View {
        CachedRemoteImage(url: path.map(APIClient.shared.url(for:))) { image in
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
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
