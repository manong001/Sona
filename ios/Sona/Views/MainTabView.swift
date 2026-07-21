import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var personal: PersonalStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var session: SessionStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsNowPlaying = false
    @State private var showsDrawer = false
    @State private var showsAccountSecurity = false
    @State private var showsAvatarEditor = false
    @State private var showsUserManagement = false
    @State private var showsAchievements = false
    @State private var showsSocial = false
    @State private var hasCheckedForUpdate = false
    @State private var availableRelease: AppReleaseInfo?
    @State private var showsUpdateAlert = false
    @State private var selectedTab: SonaTab = .home
    @AppStorage("childMode") private var childMode = false
    @AppStorage("childTheme") private var childTheme = "boy"
    @AppStorage("miniPlayerMode") private var miniPlayerMode = "floating"

    var body: some View {
        Group {
#if targetEnvironment(macCatalyst)
            ZStack(alignment: .leading) {
                MacMainView(
                    selectedTab: $selectedTab,
                    showsNowPlaying: $showsNowPlaying,
                    availableRelease: availableRelease,
                    openDrawer: openDrawer
                )

                if showsDrawer {
                    Color.black.opacity(0.56)
                        .ignoresSafeArea()
                        .onTapGesture { closeDrawer() }
                        .transition(.opacity)

                    GeometryReader { proxy in
                        ProfileDrawerView(
                            selectTab: { selectedTab = $0 },
                            manageAccount: { showsAccountSecurity = true },
                            editAvatar: { showsAvatarEditor = true },
                            showAchievements: { showsAchievements = true },
                            showSocial: { showsSocial = true },
                            manageUsers: { showsUserManagement = true },
                            close: closeDrawer
                        )
                        .frame(width: min(proxy.size.width * 0.76, 330))
                        .frame(maxHeight: .infinity)
                        .transition(.move(edge: .leading))
                    }
                }
            }
            .animation(.easeOut(duration: 0.24), value: showsDrawer)
#else
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
                tabContent(SettingsView(availableRelease: availableRelease))
                    .tabItem { Label("设置", systemImage: "gearshape.fill") }
                    .tag(SonaTab.settings)
            }
            .tint(childMode ? (childTheme == "girl" ? .pink : .cyan) : .white)
            .toolbarBackground(Color.sonaBackgroundDeep.opacity(0.98), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)

            if selectedTab != .search && selectedTab != .settings {
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
                        manageAccount: { showsAccountSecurity = true },
                        editAvatar: { showsAvatarEditor = true },
                        showAchievements: { showsAchievements = true },
                        showSocial: { showsSocial = true },
                        manageUsers: { showsUserManagement = true },
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
#endif
        }
#if !targetEnvironment(macCatalyst)
        .sheet(isPresented: $showsNowPlaying) {
            NowPlayingView()
        }
#endif
        .sheet(isPresented: $showsAccountSecurity) {
            NavigationStack { AccountSecurityView().macModalBackButton() }
        }
        .sheet(isPresented: $showsAvatarEditor) {
            NavigationStack { OwnAvatarEditorView() }
        }
        .sheet(isPresented: $showsUserManagement) {
            NavigationStack { UserManagementView().macModalBackButton() }
        }
        .sheet(isPresented: $showsAchievements) {
            NavigationStack { AchievementsView().macModalBackButton() }
        }
        .sheet(isPresented: $showsSocial) {
            SocialHubView().macModalBackButton()
        }
        .alert("发现新版本", isPresented: $showsUpdateAlert) {
            Button("稍后", role: .cancel) { }
            Button("前往更新") {
                selectedTab = .settings
            }
        } message: {
            Text(updateAlertMessage)
        }
        .task {
            guard let userID = session.currentUser?.id else { return }
            personal.configure(userID: userID)
            player.configureFavoriteCommand(
                isFavorite: { personal.favoriteIDs.contains($0) },
                updateFavorite: { trackID, isFavorite in
                    await personal.setFavorite(trackID: trackID, isFavorite: isFavorite)
                }
            )
            player.configureCarPlayAutoPlayback(
                favoriteTracks: { await personal.loadAllFavoriteTracks() },
                offlineURLProvider: { offline.localURL(for: $0) }
            )
            player.beginSession(userID: userID)
            player.restoreCachedStateIfAvailable { offline.localURL(for: $0) }
            await player.restoreStateIfNeeded { offline.localURL(for: $0) }
            if library.tracks.isEmpty {
                await library.refresh()
            }
            await personal.refresh()
            await player.startCarPlayPlaybackIfNeeded()
            await player.prepareRandomQueueIfNeeded { offline.localURL(for: $0) }
        }
        .task {
            await checkForUpdateOnLaunch()
        }
        .onChange(of: player.currentTrack?.id) { oldValue, newValue in
            guard let newValue, newValue != oldValue else { return }
            personal.notePlayback(trackID: newValue)
        }
        .onChange(of: personal.favoriteIDs) { _, _ in
            player.refreshRemoteFavoriteState()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                Task { await player.flushState() }
            }
        }
    }

    private func tabContent<Content: View>(_ content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if miniPlayerMode == "fixed"
                    && selectedTab != .search
                    && selectedTab != .settings {
                    Color.clear
                        .frame(height: 76)
                        .accessibilityHidden(true)
                }
            }
    }

    private func openDrawer() {
        showsDrawer = true
    }

    private func closeDrawer() {
        showsDrawer = false
    }

    @MainActor
    private func checkForUpdateOnLaunch() async {
        guard !hasCheckedForUpdate else { return }
        hasCheckedForUpdate = true
        do {
            let release = try await APIClient.shared.latestAppRelease()
            guard release.isNewer(
                thanVersion: currentVersion,
                build: currentBuild
            ) else { return }
            availableRelease = release
            showsUpdateAlert = true
        } catch {
            // 启动检查静默失败，用户仍可在设置页手动重试。
        }
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
    }

    private var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
    }

    private var updateAlertMessage: String {
        guard let release = availableRelease else { return "已有新版本可用。" }
        var values = ["Sona \(release.version ?? "新版本") 已发布。"]
        if let fileSize = release.fileSizeText {
            values.append("安装包大小：\(fileSize)")
        }
        if let notes = release.notes,
           !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values.append(notes)
        }
        return values.joined(separator: "\n")
    }
}

private struct MacModalBackButtonModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    @ViewBuilder
    func body(content: Content) -> some View {
#if targetEnvironment(macCatalyst)
        content.toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("返回", systemImage: "chevron.left") {
                    dismiss()
                }
            }
        }
#else
        content
#endif
    }
}

private extension View {
    func macModalBackButton() -> some View {
        modifier(MacModalBackButtonModifier())
    }
}

struct DiscoveryView: View {
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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("刷新", systemImage: "arrow.clockwise") {
                        Task { await load() }
                    }
                    .disabled(isLoading)
                    Button("播放全部", systemImage: "play.fill") {
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
            tracks = try await APIClient.shared.discoveryTracks(limit: 50)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
