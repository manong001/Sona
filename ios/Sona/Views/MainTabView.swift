import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var personal: PersonalStore
    @EnvironmentObject private var offline: OfflineStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsNowPlaying = false
    @State private var showsDrawer = false
    @State private var selectedTab: SonaTab = .home
    @AppStorage("childMode") private var childMode = false
    @AppStorage("childTheme") private var childTheme = "boy"

    var body: some View {
        ZStack(alignment: .leading) {
            TabView(selection: $selectedTab) {
                tabContent(HomeView(openDrawer: openDrawer))
                    .tabItem { Label("首页", systemImage: "house.fill") }
                    .tag(SonaTab.home)
                tabContent(DiscoveryView(openDrawer: openDrawer))
                    .tabItem { Label("发现", systemImage: "sparkles") }
                    .tag(SonaTab.discovery)
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
            .tint(childMode ? (childTheme == "girl" ? .pink : .cyan) : .white)
            .toolbarBackground(Color.sonaBackgroundDeep.opacity(0.98), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)

            MiniPlayerView {
                showsNowPlaying = true
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
                    .frame(width: min(proxy.size.width * 0.76, 330))
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
        .overlay(alignment: .top) {
            if childMode {
                Text(childTheme == "girl" ? "🦄 糖果音乐乐园" : "🚀 星空音乐探险")
                    .font(.caption.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        childTheme == "girl" ? Color.pink.opacity(0.9) : Color.cyan.opacity(0.9),
                        in: Capsule()
                    )
                    .foregroundStyle(.black)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: childMode)
        .sheet(isPresented: $showsNowPlaying) {
            NowPlayingView()
        }
        .task {
            if library.tracks.isEmpty {
                await library.refresh()
            }
            await personal.refresh()
            await player.restoreStateIfNeeded { offline.localURL(for: $0) }
            await player.prepareRandomQueueIfNeeded()
        }
        .onChange(of: player.currentTrack?.id) { oldValue, newValue in
            guard let newValue, newValue != oldValue else { return }
            personal.notePlayback(trackID: newValue)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { player.saveState() }
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

private struct DiscoveryView: View {
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var personal: PersonalStore
    let openDrawer: () -> Void
    @State private var tracks: [Track] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && tracks.isEmpty {
                    ProgressView("正在挑选新歌…")
                } else if tracks.isEmpty {
                    ContentUnavailableView(
                        "暂无发现歌曲",
                        systemImage: "sparkles",
                        description: Text(errorMessage ?? "管理员将歌曲划入发现池后会显示在这里。")
                    )
                } else {
                    List(tracks) { track in
                        Button {
                            player.play(
                                track: track,
                                queue: tracks,
                                prioritizedQueueTitle: "发现",
                                offlineURLProvider: { offline.localURL(for: $0) }
                            )
                        } label: {
                            TrackRow(track: track, isFavorite: personal.favoriteIDs.contains(track.id))
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.sonaBackground)
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.sonaBackground)
            .navigationTitle("发现")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: openDrawer) { Image(systemName: "person.crop.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("试听十首", systemImage: "play.fill") {
                        guard let first = tracks.first else { return }
                        player.play(
                            track: first,
                            queue: tracks,
                            prioritizedQueueTitle: "发现",
                            offlineURLProvider: { offline.localURL(for: $0) }
                        )
                    }
                    .disabled(tracks.isEmpty)
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tracks = try await APIClient.shared.discoveryTracks(limit: 10)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
