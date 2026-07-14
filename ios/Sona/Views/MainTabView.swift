import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @State private var showsNowPlaying = false

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("曲库", systemImage: "music.note.list") }
            PlaylistsView()
                .tabItem { Label("歌单", systemImage: "rectangle.stack.fill") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if player.currentTrack != nil {
                MiniPlayerView {
                    showsNowPlaying = true
                }
            }
        }
        .sheet(isPresented: $showsNowPlaying) {
            NowPlayingView()
        }
        .task {
            if library.tracks.isEmpty {
                await library.refresh()
            }
        }
    }
}
