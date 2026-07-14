import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            switch session.state {
            case .checking:
                ZStack {
                    Color.black.ignoresSafeArea()
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
    }
}
