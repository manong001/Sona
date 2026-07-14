import SwiftData
import SwiftUI

@main
struct SonaApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var library = LibraryStore()
    @StateObject private var player = PlayerStore()
    @StateObject private var offline = OfflineStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(offline)
                .tint(.sonaGreen)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: Playlist.self)
    }
}

extension Color {
    static let sonaGreen = Color(red: 0.12, green: 0.84, blue: 0.38)
    static let sonaSurface = Color(white: 0.10)
}
