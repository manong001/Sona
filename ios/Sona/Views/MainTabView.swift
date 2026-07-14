import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var personal: PersonalStore
    @State private var showsNowPlaying = false
    @State private var showsDrawer = false
    @State private var selectedTab: SonaTab = .home

    var body: some View {
        ZStack(alignment: .leading) {
            TabView(selection: $selectedTab) {
                tabContent(HomeView(openDrawer: openDrawer))
                    .tabItem { Label("首页", systemImage: "house.fill") }
                    .tag(SonaTab.home)
                tabContent(SearchView(openDrawer: openDrawer))
                    .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                    .tag(SonaTab.search)
                tabContent(MusicLibraryView(openDrawer: openDrawer))
                    .tabItem { Label("音乐库", systemImage: "books.vertical.fill") }
                    .tag(SonaTab.library)
                tabContent(SettingsView())
                    .tabItem { Label("设置", systemImage: "gearshape.fill") }
                    .tag(SonaTab.settings)
            }
            .tint(.white)
            .toolbarBackground(Color.sonaBackgroundDeep.opacity(0.98), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)

            if player.currentTrack != nil {
                MiniPlayerView {
                    showsNowPlaying = true
                }
            }

            if showsDrawer {
                Color.black.opacity(0.56)
                    .ignoresSafeArea()
                    .onTapGesture { closeDrawer() }
                    .transition(.opacity)

                GeometryReader { proxy in
                    ProfileDrawerView(
                        selectTab: { selectedTab = $0 },
                        close: closeDrawer
                    )
                    .frame(width: min(proxy.size.width * 0.88, 390))
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .leading))
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { value in
                                if value.translation.width < -60 { closeDrawer() }
                            }
                    )
                }
            }
        }
        .animation(.easeOut(duration: 0.24), value: showsDrawer)
        .sheet(isPresented: $showsNowPlaying) {
            NowPlayingView()
        }
        .task {
            if library.tracks.isEmpty {
                await library.refresh()
            }
            await personal.refresh()
        }
        .onChange(of: player.currentTrack?.id) { oldValue, newValue in
            guard let newValue, newValue != oldValue else { return }
            personal.notePlayback(trackID: newValue)
        }
        .onDisappear {
            personal.reset()
            player.stop()
        }
    }

    private func tabContent<Content: View>(_ content: Content) -> some View {
        content
    }

    private func openDrawer() {
        showsDrawer = true
    }

    private func closeDrawer() {
        showsDrawer = false
    }
}
