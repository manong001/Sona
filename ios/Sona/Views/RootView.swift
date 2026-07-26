import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var personal: PersonalStore
    @EnvironmentObject private var userPreferences: UserPreferencesStore

    var body: some View {
        Group {
            switch session.state {
            case .checking:
                ZStack {
                    Color.sonaBackgroundDeep.ignoresSafeArea()
                    ProgressView("正在连接 Sona…")
                }
            case .signedOut:
                LoginView()
            case .signedIn:
                MainTabView()
            }
        }
        .task {
            if case .checking = session.state {
                await session.restore()
            }
        }
        .onChange(of: session.currentUser?.id) { _, _ in
            personal.reset()
            if session.currentUser == nil {
                userPreferences.endSession()
            }
        }
    }
}
