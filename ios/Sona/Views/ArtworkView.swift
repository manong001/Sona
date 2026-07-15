import SwiftUI
import UIKit

struct ArtworkView: View {
    let path: String?
    var cornerRadius: CGFloat = 8
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.sonaSurface)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
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
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: path) {
            guard let path else {
                image = nil
                return
            }
            if let data = try? await APIClient.shared.data(at: path) {
                image = UIImage(data: data)
            }
        }
    }
}
