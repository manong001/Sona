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
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    let openDrawer: () -> Void
    @State private var tracks: [Track] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var flowStartedAt = Date()
    @State private var remixID = 0

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
                    discoveryHeader

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
                        } else {
                            DiscoveryRiver(
                                tracks: tracks,
                                currentTrackID: player.currentTrack?.id,
                                startedAt: flowStartedAt,
                                play: play
                            )
                            .id(remixID)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await load() }
        }
    }

    private var discoveryHeader: some View {
        HStack(spacing: 12) {
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

            Button("换一片", systemImage: "sparkles") { remix() }
                .font(.caption.bold())
                .foregroundStyle(.black.opacity(0.86))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Color.sonaGreen, in: Capsule())
                .buttonStyle(.plain)
                .disabled(tracks.isEmpty)

            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.10), in: Circle())
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

    private func remix() {
        guard !tracks.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            tracks.shuffle()
            remixID += 1
            flowStartedAt = Date()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tracks = try await APIClient.shared.discoveryTracks(limit: 50).shuffled()
            errorMessage = nil
            remixID += 1
            flowStartedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
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
    let play: (Track) -> Void

    var body: some View {
        GeometryReader { proxy in
            let availableHeight = max(480, proxy.size.height)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    DiscoveryFlowLane(
                        tracks: laneTracks(0),
                        height: availableHeight * 0.34,
                        lane: 0,
                        speed: 8,
                        direction: -1,
                        startedAt: startedAt,
                        currentTrackID: currentTrackID,
                        play: play
                    )
                    DiscoveryFlowLane(
                        tracks: laneTracks(1),
                        height: availableHeight * 0.31,
                        lane: 1,
                        speed: 6,
                        direction: 1,
                        startedAt: startedAt,
                        currentTrackID: currentTrackID,
                        play: play
                    )
                    DiscoveryFlowLane(
                        tracks: laneTracks(2),
                        height: availableHeight * 0.29,
                        lane: 2,
                        speed: 7,
                        direction: -1,
                        startedAt: startedAt,
                        currentTrackID: currentTrackID,
                        play: play
                    )
                }
                .padding(.vertical, 2)
                .frame(minHeight: proxy.size.height, alignment: .top)
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
        Button(action: play) {
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel("播放 \(track.title)，\(track.artist)")
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
