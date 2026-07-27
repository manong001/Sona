import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var personal: PersonalStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var userPreferences: UserPreferencesStore
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
    @State private var childModeRefreshTask: Task<Void, Never>?
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
            TabView(selection: tabSelection) {
                tabContent(HomeView(openDrawer: openDrawer))
                    .tabItem { Label("首页", systemImage: "house.fill") }
                    .tag(SonaTab.home)
                tabContent(DiscoveryView(
                    isActive: selectedTab == .discovery,
                    close: { selectedTab = .home },
                    openDrawer: openDrawer
                ))
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

            if selectedTab != .discovery
                && selectedTab != .search
                && selectedTab != .settings {
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
#endif
        }
#if !targetEnvironment(macCatalyst)
        .sheet(isPresented: $showsNowPlaying) {
            NowPlayingView()
                .presentationDragIndicator(.visible)
        }
#endif
        .sheet(isPresented: $showsAccountSecurity) {
            NavigationStack { AccountSecurityView().macModalBackButton() }
                .desktopSheetSize(.standard)
        }
        .sheet(isPresented: $showsAvatarEditor) {
            NavigationStack { OwnAvatarEditorView() }
                .desktopSheetSize(.standard)
        }
        .sheet(isPresented: $showsUserManagement) {
            NavigationStack { UserManagementView().macModalBackButton() }
                .desktopSheetSize(.large)
        }
        .sheet(isPresented: $showsAchievements) {
            NavigationStack { AchievementsView().macModalBackButton() }
                .desktopSheetSize(.large)
        }
        .sheet(isPresented: $showsSocial) {
            SocialHubView()
                .desktopSheetSize(.large)
        }
        .alert("发现新版本", isPresented: $showsUpdateAlert) {
            Button("稍后", role: .cancel) { }
            Button("前往更新") {
                player.pauseForUpdate()
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
            async let preferencesLoad: Void = userPreferences.beginSession(userID: userID)
            async let libraryRefresh: Void = refreshLibraryOnLaunch()
            async let personalRefresh: Void = personal.refresh()
            await player.restoreStateIfNeeded { offline.localURL(for: $0) }
            _ = await (preferencesLoad, libraryRefresh, personalRefresh)
            Task(priority: .utility) {
                _ = await library.prepareAlphabeticalIndex()
            }
            await player.startCarPlayPlaybackIfNeeded()
            await player.prepareRandomQueueIfNeeded { offline.localURL(for: $0) }
        }
        .task {
            await checkForUpdateOnLaunch()
        }
        .task(id: session.currentUser?.id) {
            guard session.currentUser != nil else {
                social.reset()
                return
            }
            while !Task.isCancelled {
                try? await social.loadConversations()
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .onChange(of: player.currentTrack?.id) { oldValue, newValue in
            guard let newValue, newValue != oldValue else { return }
            personal.notePlayback(trackID: newValue)
        }
        .onChange(of: personal.favoriteIDs) { _, _ in
            player.refreshRemoteFavoriteState()
        }
        .onChange(of: childMode) { oldValue, newValue in
            personal.prepareForLibraryModeChange(from: oldValue, to: newValue)
            childModeRefreshTask?.cancel()
            childModeRefreshTask = Task {
                async let libraryRefresh: Void = library.refreshForLibraryModeChange()
                async let personalRefresh: Void = personal.refreshForLibraryModeChange()
                if newValue {
                    await player.prepareChildModeRandomQueue {
                        offline.localURL(for: $0)
                    }
                }
                _ = await (libraryRefresh, personalRefresh)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                Task { await player.flushState() }
            } else if phase == .active, session.currentUser != nil {
                Task { try? await social.loadConversations() }
            }
        }
    }

    private var tabSelection: Binding<SonaTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                guard newValue != selectedTab else { return }
                SonaHaptics.buttonPressed()
                selectedTab = newValue
            }
        )
    }

    private func tabContent<Content: View>(_ content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if miniPlayerMode == "fixed"
                    && selectedTab != .discovery
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

    private func refreshLibraryOnLaunch() async {
        if library.tracks.isEmpty {
            await library.refresh()
        }
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
    @ViewBuilder
    func body(content: Content) -> some View {
#if targetEnvironment(macCatalyst)
        content.toolbar {
            ToolbarItem(placement: .cancellationAction) {
                ModalDismissButton("返回")
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
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var personal: PersonalStore
    @AppStorage("miniPlayerMode") private var miniPlayerMode = "floating"
    @State private var displayMode = "swipe"
    let isActive: Bool
    let close: () -> Void
    let openDrawer: () -> Void
    @State private var recommendations: [RecommendedTrack] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var flowStartedAt = Date()
    @State private var remixID = 0
    @State private var selectedScene: RecommendationScene?
    @State private var feedbackToUndo: RecommendationFeedback?
    @State private var feedbackMessage: String?
    @State private var activeSwipeTrackID: String?
    @State private var swipeLyricLines: [LyricLine] = []
    @State private var swipeTrackIDToPositionWithoutAutoplay: String?

    private var tracks: [Track] { recommendations.map(\.track) }

    private let subtitles = [
        "在熟悉之外，遇见一首歌",
        "今天会漂来什么？",
        "让下一首歌出乎意料",
        "顺着声音，去往没听过的地方"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                DiscoveryBackground()

                VStack(spacing: 0) {
                    if displayMode != "swipe" {
                        discoveryHeader
                    }

                    Group {
                        if isLoading && tracks.isEmpty {
                            ProgressView("正在挑选新歌…")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if tracks.isEmpty {
                            ContentUnavailableView(
                                "暂无发现歌曲",
                                systemImage: "sparkles",
                                description: Text(errorMessage ?? "管理员将歌曲划入发现池后会显示在这里。")
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if displayMode == "swipe" {
                            DiscoverySwipeFeed(
                                recommendations: recommendations,
                                activeTrackID: $activeSwipeTrackID,
                                actionBottomInset: discoveryActionBottomInset,
                                lyricLines: swipeLyricLines,
                                currentTrackID: player.currentTrack?.id,
                                favoriteIDs: personal.favoriteIDs,
                                playlists: personal.playlists.filter {
                                    !$0.featured && $0.directoryPath == nil
                                },
                                play: play,
                                toggleFavorite: { track in
                                    Task { await personal.toggleFavorite(trackID: track.id) }
                                },
                                addToPlaylist: { track, playlist in
                                    Task {
                                        await personal.setTrack(
                                            track.id, in: playlist.id, isIncluded: true
                                        )
                                    }
                                },
                                feedback: { type, track in
                                    Task { await submitFeedback(type, for: track) }
                                }
                            )
                            .ignoresSafeArea()
                        } else {
                            DiscoveryRiver(
                                tracks: tracks,
                                currentTrackID: player.currentTrack?.id,
                                startedAt: flowStartedAt,
                                hasFixedMiniPlayer: hasFixedMiniPlayer,
                                play: play,
                                remix: remix
                            )
                            .id(remixID)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                    }
                }

                if displayMode == "swipe" {
                    immersiveSwipeHeader
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.visible, for: .tabBar)
            .task { await load() }
            .task(id: activeSwipeTrackID) {
                await loadSwipeLyrics()
            }
            .onChange(of: activeSwipeTrackID) { oldValue, newValue in
                guard oldValue != newValue, isActive, displayMode == "swipe" else { return }
                if swipeTrackIDToPositionWithoutAutoplay == newValue {
                    swipeTrackIDToPositionWithoutAutoplay = nil
                    return
                }
                swipeTrackIDToPositionWithoutAutoplay = nil
                autoplaySwipeTrack(id: newValue)
            }
            .onChange(of: displayMode) { _, newValue in
                guard isActive, newValue == "swipe" else { return }
                resetSwipePositionWithoutAutoplay()
            }
            .onChange(of: isActive) { _, newValue in
                guard newValue else { return }
                resetSwipePositionWithoutAutoplay()
            }
        }
        .alert("推荐已调整", isPresented: Binding(
            get: { feedbackMessage != nil },
            set: { if !$0 { feedbackMessage = nil } }
        )) {
            if feedbackToUndo != nil {
                Button("撤销") { Task { await undoFeedback() } }
            }
            Button("好", role: .cancel) {}
        } message: {
            Text(feedbackMessage ?? "")
        }
    }

    private var immersiveSwipeHeader: some View {
        VStack {
            HStack(spacing: 12) {
                Button(action: close) {
                    Image(systemName: "chevron.down")
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .background(.black.opacity(0.24), in: Circle())
                }
                .accessibilityLabel("退出刷歌")

                Spacer()

                Menu {
                    Button(
                        "发现池",
                        systemImage: selectedScene == nil ? "checkmark" : "sparkles"
                    ) {
                        selectedScene = nil
                        Task { await load() }
                    }
                    ForEach(RecommendationScene.allCases) { scene in
                        Button(
                            scene.title,
                            systemImage: selectedScene == scene ? "checkmark" : scene.icon
                        ) {
                            selectedScene = scene
                            Task { await load() }
                        }
                    }
                } label: {
                    Label(selectedScene?.title ?? "发现池", systemImage: "slider.horizontal.3")
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.24), in: Circle())
                }

                Menu {
                    Button("换一批", systemImage: "shuffle") { remix() }
                    Button("重新载入", systemImage: "arrow.clockwise") {
                        Task { await load() }
                    }
                    Divider()
                    Button("流动卡片", systemImage: "rectangle.3.group") {
                        displayMode = "river"
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis")
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.24), in: Circle())
                }
            }
            .font(.headline)
            .labelStyle(.iconOnly)
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 10)

            Spacer()
        }
    }

    private var discoveryHeader: some View {
        HStack(spacing: 8) {
            SonaAvatarButton(
                username: session.currentUser?.username ?? "Sona",
                action: openDrawer
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("发现")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                Text(subtitles[remixID % subtitles.count])
                    .font(.caption)
                    .foregroundStyle(Color.sonaSecondaryText)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 8)

            Menu {
                Button(
                    "发现池",
                    systemImage: selectedScene == nil ? "checkmark" : "sparkles"
                ) {
                    selectedScene = nil
                    Task { await load() }
                }
                ForEach(RecommendationScene.allCases) { scene in
                    Button(
                        scene.title,
                        systemImage: selectedScene == scene ? "checkmark" : scene.icon
                    ) {
                        selectedScene = scene
                        Task { await load() }
                    }
                }
            } label: {
                Image(systemName: selectedScene?.icon ?? "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.24), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selectedScene?.title ?? "发现池")

            Button(
                displayMode == "swipe" ? "流动卡片" : "刷歌模式",
                systemImage: displayMode == "swipe" ? "rectangle.3.group" : "rectangle.portrait.on.rectangle.portrait"
            ) {
                displayMode = displayMode == "swipe" ? "river" : "swipe"
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.black.opacity(0.24), in: Circle())
            .buttonStyle(.plain)

            Button("换一批", systemImage: "shuffle") { remix() }
                .labelStyle(.iconOnly)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.24), in: Circle())
                .buttonStyle(.plain)
                .disabled(tracks.isEmpty)

            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.24), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityLabel("重新载入发现歌曲")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    private func play(_ track: Track) {
        player.play(
            track: track,
            queue: tracks,
            prioritizedQueueTitle: "发现",
            offlineURLProvider: { offline.localURL(for: $0) }
        )
    }

    private var hasFixedMiniPlayer: Bool {
#if targetEnvironment(macCatalyst)
        false
#else
        miniPlayerMode == "fixed"
#endif
    }

    private var discoveryActionBottomInset: CGFloat {
#if targetEnvironment(macCatalyst)
        30
#else
        92
#endif
    }

    @MainActor
    private func loadSwipeLyrics() async {
        swipeLyricLines = []
        guard displayMode == "swipe",
              let track = recommendations.first(where: {
                  $0.track.id == activeSwipeTrackID
              })?.track,
              track.hasLyrics else { return }
        do {
            let lyrics = try await APIClient.shared.lyrics(for: track)
            guard !Task.isCancelled, activeSwipeTrackID == track.id else { return }
            swipeLyricLines = LyricsParser.parse(synced: lyrics.synced, plain: lyrics.plain)
        } catch {
            swipeLyricLines = []
        }
    }

    private func remix() {
        guard !recommendations.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            recommendations.shuffle()
            remixID += 1
            flowStartedAt = Date()
        }
        resetSwipePositionWithoutAutoplay()
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            recommendations = if let selectedScene {
                try await APIClient.shared.sceneRecommendations(selectedScene, limit: 50)
            } else {
                try await APIClient.shared.discoveryFeed(limit: 50)
            }
            recommendations.shuffle()
            errorMessage = nil
            remixID += 1
            flowStartedAt = Date()
            resetSwipePositionWithoutAutoplay()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetSwipePositionWithoutAutoplay() {
        guard isActive, displayMode == "swipe" else { return }
        let firstID = recommendations.first?.track.id
        swipeTrackIDToPositionWithoutAutoplay = firstID
        activeSwipeTrackID = firstID
    }

    private func autoplaySwipeTrack(id: String?) {
        guard let id,
              let track = recommendations.first(where: { $0.track.id == id })?.track else {
            return
        }
        play(track)
    }

    @MainActor
    private func submitFeedback(
        _ type: RecommendationFeedbackType, for track: Track
    ) async {
        do {
            let activeIndex = recommendations.firstIndex {
                $0.track.id == activeSwipeTrackID
            }
            let feedback = try await APIClient.shared.addRecommendationFeedback(
                type: type, trackID: track.id
            )
            feedbackToUndo = feedback
            feedbackMessage = "\(type.title)：\(feedback.displayValue)"
            recommendations.removeAll { item in
                switch type {
                case .track:
                    item.track.id == track.id
                case .artist:
                    item.track.artist.localizedCaseInsensitiveCompare(track.artist) == .orderedSame
                case .genre:
                    item.track.genre.localizedCaseInsensitiveCompare(track.genre) == .orderedSame
                }
            }
            if recommendations.allSatisfy({ $0.track.id != activeSwipeTrackID }) {
                let replacementIndex = min(activeIndex ?? 0, max(0, recommendations.count - 1))
                activeSwipeTrackID = recommendations.indices.contains(replacementIndex)
                    ? recommendations[replacementIndex].track.id : nil
            }
        } catch {
            feedbackToUndo = nil
            feedbackMessage = "操作失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func undoFeedback() async {
        guard let feedback = feedbackToUndo else { return }
        do {
            try await APIClient.shared.removeRecommendationFeedback(id: feedback.id)
            feedbackToUndo = nil
            feedbackMessage = nil
            await load()
        } catch {
            feedbackMessage = "撤销失败：\(error.localizedDescription)"
        }
    }
}

private struct DiscoverySwipeFeed: View {
    let recommendations: [RecommendedTrack]
    @Binding var activeTrackID: String?
    let actionBottomInset: CGFloat
    let lyricLines: [LyricLine]
    let currentTrackID: String?
    let favoriteIDs: Set<String>
    let playlists: [Playlist]
    let play: (Track) -> Void
    let toggleFavorite: (Track) -> Void
    let addToPlaylist: (Track, Playlist) -> Void
    let feedback: (RecommendationFeedbackType, Track) -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(recommendations) { recommendation in
                        swipeCard(recommendation, size: proxy.size)
                            .frame(
                                width: proxy.size.width,
                                height: max(1, proxy.size.height)
                            )
                            .id(recommendation.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $activeTrackID)
        }
    }

    private func swipeCard(
        _ recommendation: RecommendedTrack, size: CGSize
    ) -> some View {
        let track = recommendation.track
        return ZStack(alignment: .bottom) {
            CachedRemoteImage(
                url: sonaArtworkURL(path: track.artworkURL, thumbnailSize: 1024),
                content: { artwork in
                    let displaySize = fittedArtworkSize(artwork, pageSize: size)
                    ZStack {
                        Color.black
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .scaleEffect(1.08)
                            .blur(radius: 32)
                            .opacity(0.62)
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .opacity(0.26)
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFit()
                            .frame(width: displaySize.width, height: displaySize.height)
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .white, location: 0.05),
                                        .init(color: .white, location: 0.86),
                                        .init(color: .clear, location: 1)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .offset(y: -size.height * 0.11)
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.22), location: 0),
                                .init(color: .clear, location: 0.22),
                                .init(color: .clear, location: 0.58),
                                .init(color: .black.opacity(0.42), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                },
                placeholder: {
                    LinearGradient(
                        colors: [.indigo, Color.sonaBackgroundDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            )
            .frame(width: size.width, height: max(1, size.height))
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.2), .black.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: size.width, height: max(1, size.height))

            VStack(alignment: .leading, spacing: 14) {
                Label(recommendation.reason, systemImage: "sparkles")
                    .font(.caption.bold())
                    .foregroundStyle(Color.sonaGreen)
                    .lineLimit(2)

                VStack(alignment: .leading, spacing: 5) {
                    Text(track.title)
                        .font(.title.bold())
                        .lineLimit(2)
                    Text("\(track.artist) · \(track.album)")
                        .foregroundStyle(.white.opacity(0.74))
                        .lineLimit(1)
                }

                DiscoverySwipeLyrics(lines: lyricLines)

                HStack(spacing: 24) {
                    Button {
                        play(track)
                    } label: {
                        Image(systemName: currentTrackID == track.id ? "waveform" : "play.fill")
                            .font(.title2.bold())
                            .foregroundStyle(.black)
                            .frame(width: 58, height: 58)
                            .background(Color.sonaGreen, in: Circle())
                    }

                    Button {
                        toggleFavorite(track)
                    } label: {
                        Image(systemName: favoriteIDs.contains(track.id) ? "heart.fill" : "heart")
                    }

                    Menu {
                        if playlists.isEmpty {
                            Text("请先创建歌单")
                        } else {
                            ForEach(playlists) { playlist in
                                Button(playlist.name, systemImage: "music.note.list") {
                                    addToPlaylist(track, playlist)
                                }
                                .disabled(playlist.trackIDs.contains(track.id))
                            }
                        }
                    } label: {
                        Image(systemName: "text.badge.plus")
                    }

                    Menu {
                        ForEach(RecommendationFeedbackType.allCases, id: \.rawValue) { type in
                            Button(type.title, systemImage: "hand.thumbsdown") {
                                feedback(type, track)
                            }
                            .disabled(type == .genre && track.genre == "未分类")
                        }
                    } label: {
                        Image(systemName: "hand.thumbsdown")
                    }
                }
                .font(.title2)
                .foregroundStyle(.white)
                .buttonStyle(.plain)
            }
            .padding(.bottom, actionBottomInset)
            .frame(
                width: max(1, size.width - 48),
                alignment: .leading
            )
        }
        .frame(width: size.width, height: max(1, size.height))
        .clipped()
    }

    private func fittedArtworkSize(_ artwork: UIImage, pageSize: CGSize) -> CGSize {
        let originalWidth = max(1, artwork.size.width)
        let originalHeight = max(1, artwork.size.height)
        let scale = min(
            pageSize.width / originalWidth,
            pageSize.height * 0.58 / originalHeight
        )
        return CGSize(width: originalWidth * scale, height: originalHeight * scale)
    }
}

private struct DiscoverySwipeLyrics: View {
    @EnvironmentObject private var playbackProgress: PlaybackProgress
    let lines: [LyricLine]

    private var activeLine: LyricLine? {
        LyricsParser.activeLine(
            in: lines,
            at: playbackProgress.elapsed,
            duration: playbackProgress.duration
        )
    }

    private var visibleLines: [LyricLine] {
        guard !lines.isEmpty else { return [] }
        let activeIndex = activeLine.flatMap { active in
            lines.firstIndex { $0.id == active.id }
        } ?? 0
        let start = max(0, min(activeIndex - 1, max(0, lines.count - 3)))
        return Array(lines.dropFirst(start).prefix(3))
    }

    var body: some View {
        if !visibleLines.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(visibleLines) { line in
                    Text(line.text)
                        .font(activeLine?.id == line.id ? .body.bold() : .subheadline)
                        .foregroundStyle(
                            activeLine?.id == line.id ? .white : .white.opacity(0.52)
                        )
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: activeLine?.id)
        }
    }
}

private struct DiscoveryBackground: View {
    var body: some View {
        ZStack {
            Color.sonaBackground
            RadialGradient(
                colors: [Color.sonaGreen.opacity(0.18), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 420
            )
            LinearGradient(
                colors: [.clear, Color.sonaBackgroundDeep.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

private struct DiscoveryRiver: View {
    let tracks: [Track]
    let currentTrackID: String?
    let startedAt: Date
    let hasFixedMiniPlayer: Bool
    let play: (Track) -> Void
    let remix: () -> Void
    @State private var hasUserScrolled = false
    @State private var hasTriggeredEnd = false

    var body: some View {
        GeometryReader { proxy in
            let availableHeight = hasFixedMiniPlayer
                ? proxy.size.height
                : max(480, proxy.size.height)
            let laneScale = hasFixedMiniPlayer ? 0.90 : 1.0
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    DiscoveryFlowLane(
                        tracks: laneTracks(0),
                        height: availableHeight * 0.34 * laneScale,
                        lane: 0,
                        speed: 8,
                        direction: -1,
                        startedAt: startedAt,
                        currentTrackID: currentTrackID,
                        play: play
                    )
                    DiscoveryFlowLane(
                        tracks: laneTracks(1),
                        height: availableHeight * 0.31 * laneScale,
                        lane: 1,
                        speed: 6,
                        direction: 1,
                        startedAt: startedAt,
                        currentTrackID: currentTrackID,
                        play: play
                    )
                    DiscoveryFlowLane(
                        tracks: laneTracks(2),
                        height: availableHeight * 0.29 * laneScale,
                        lane: 2,
                        speed: 7,
                        direction: -1,
                        startedAt: startedAt,
                        currentTrackID: currentTrackID,
                        play: play
                    )
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color.sonaGreen.opacity(0.06),
                                Color.sonaGreen.opacity(0.16),
                                Color.sonaBackgroundDeep
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        RadialGradient(
                            colors: [Color.sonaGreen.opacity(0.22), .clear],
                            center: .top,
                            startRadius: 0,
                            endRadius: 260
                        )
                        VStack(spacing: 10) {
                            Image(systemName: "chevron.down")
                                .font(.subheadline.bold())
                            Text("继续下滑，换一批声音")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(.white.opacity(0.58))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 16)
                    }
                    .frame(height: max(180, availableHeight * 0.22))
                    .background {
                        GeometryReader { marker in
                            Color.clear.preference(
                                key: DiscoveryRiverBottomPreferenceKey.self,
                                value: marker.frame(
                                    in: .named("discoveryRiverScroll")
                                ).maxY
                            )
                        }
                    }
                }
                .padding(.vertical, 2)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .coordinateSpace(name: "discoveryRiverScroll")
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in hasUserScrolled = true }
            )
            .onPreferenceChange(DiscoveryRiverBottomPreferenceKey.self) { bottomY in
                let visibleBottom = proxy.size.height
                    - max(12, proxy.safeAreaInsets.bottom)
                if bottomY > proxy.size.height + 80 {
                    hasTriggeredEnd = false
                }
                guard hasUserScrolled,
                      !hasTriggeredEnd,
                      bottomY > 0,
                      bottomY <= visibleBottom else { return }
                hasTriggeredEnd = true
                hasUserScrolled = false
                remix()
            }
        }
    }

    private func laneTracks(_ lane: Int) -> [Track] {
        let values = tracks.enumerated().compactMap { index, track in
            index % 3 == lane ? track : nil
        }
        return values.isEmpty ? tracks : values
    }
}

private struct DiscoveryRiverBottomPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

private struct DiscoveryFlowLane: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tracks: [Track]
    let height: CGFloat
    let lane: Int
    let speed: Double
    let direction: Double
    let startedAt: Date
    let currentTrackID: String?
    let play: (Track) -> Void
    @GestureState private var dragTranslation: CGFloat = 0
    @State private var settledTranslation: CGFloat = 0

    private let spacing: CGFloat = 12

    var body: some View {
        GeometryReader { _ in
            if reduceMotion {
                laneContent(at: startedAt)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    laneContent(at: context.date)
                }
            }
        }
        .frame(height: height)
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .updating($dragTranslation) { value, state, _ in
                    state = value.translation.width
                }
                .onEnded { value in
                    settledTranslation += value.translation.width
                }
        )
    }

    private func laneContent(at date: Date) -> some View {
        let cards = repeatedTracks
        let cycleWidth = widths(for: cards).reduce(0, +) + spacing * CGFloat(cards.count)
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        let automatic = reduceMotion ? 0 : CGFloat(elapsed * speed * direction)
        let offset = wrappedOffset(
            automatic + settledTranslation + dragTranslation,
            cycleWidth: cycleWidth
        )

        return HStack(spacing: spacing) {
            ForEach(0..<(cards.count * 2), id: \.self) { index in
                let track = cards[index % cards.count]
                DiscoveryTrackCard(
                    track: track,
                    width: cardWidth(at: index % cards.count),
                    height: height,
                    lane: lane,
                    index: index % cards.count,
                    isPlaying: track.id == currentTrackID,
                    play: { play(track) }
                )
            }
        }
        .offset(x: offset)
    }

    private var repeatedTracks: [Track] {
        guard !tracks.isEmpty else { return [] }
        var values = tracks
        while values.count < 6 { values.append(contentsOf: tracks) }
        return values
    }

    private func widths(for tracks: [Track]) -> [CGFloat] {
        tracks.indices.map(cardWidth)
    }

    private func cardWidth(at index: Int) -> CGFloat {
        let patterns: [[CGFloat]] = [
            [270, 158, 210, 176],
            [142, 220, 166, 196],
            [194, 148, 230, 164]
        ]
        let pattern = patterns[lane % patterns.count]
        return pattern[index % pattern.count]
    }

    private func wrappedOffset(_ value: CGFloat, cycleWidth: CGFloat) -> CGFloat {
        guard cycleWidth > 0 else { return 0 }
        let remainder = value.truncatingRemainder(dividingBy: cycleWidth)
        return remainder > 0 ? remainder - cycleWidth : remainder
    }
}

private struct DiscoveryTrackCard: View {
    let track: Track
    let width: CGFloat
    let height: CGFloat
    let lane: Int
    let index: Int
    let isPlaying: Bool
    let play: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork
            LinearGradient(
                colors: [.clear, .black.opacity(0.12), .black.opacity(0.90)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                if isPlaying {
                    Label("正在播放", systemImage: "waveform")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.sonaGreen)
                } else if width > 175 {
                    Text(discoveryReason)
                        .font(.caption2.bold())
                        .foregroundStyle(.white.opacity(0.74))
                        .lineLimit(1)
                }

                Text(track.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(1)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)

            if width > 205 {
                Image(systemName: "play.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(Color.sonaGreen, in: Circle())
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isPlaying ? Color.sonaGreen.opacity(0.72) : .white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 12, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: play)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("播放 \(track.title)，\(track.artist)")
        .accessibilityAction { play() }
    }

    private var artwork: some View {
        CachedRemoteImage(url: sonaArtworkURL(path: track.artworkURL, thumbnailSize: 768)) { image in
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } placeholder: {
            LinearGradient(
                colors: [placeholderColor.opacity(0.92), Color.sonaBackgroundDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private var discoveryReason: String {
        let values = track.genre == "未分类"
            ? ["随机漂来的旋律", "来自发现歌曲池", "也许正合此刻"]
            : ["随机漂来的\(track.genre)", "来自发现歌曲池", "换一种声音"]
        return values[(lane + index) % values.count]
    }

    private var placeholderColor: Color {
        let values: [Color] = [.indigo, .teal, .purple, .orange, .blue]
        return values[(lane + index) % values.count]
    }
}
