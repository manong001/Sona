import SwiftUI

@main
struct SonaApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var library = LibraryStore()
    @StateObject private var player = PlayerStore()
    @StateObject private var offline = OfflineStore()
    @StateObject private var personal = PersonalStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(offline)
                .environmentObject(personal)
                .tint(.sonaGreen)
                .preferredColorScheme(.dark)
        }
    }
}

extension Color {
    static let sonaGreen = Color(red: 0.118, green: 0.843, blue: 0.376)
    static let sonaBackground = Color(red: 0.071, green: 0.071, blue: 0.071)
    static let sonaBackgroundDeep = Color(red: 0.031, green: 0.031, blue: 0.031)
    static let sonaSurface = Color(red: 0.141, green: 0.141, blue: 0.141)
    static let sonaPlayerSurface = Color(red: 0.165, green: 0.165, blue: 0.153)
    static let sonaChip = Color(red: 0.20, green: 0.20, blue: 0.20)
    static let sonaSecondaryText = Color(red: 0.70, green: 0.70, blue: 0.70)
}
