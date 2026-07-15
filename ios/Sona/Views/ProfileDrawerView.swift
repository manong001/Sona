import SwiftUI

enum SonaTab: Hashable {
    case home
    case discovery
    case search
    case library
    case settings
}

struct ProfileDrawerView: View {
    @EnvironmentObject private var session: SessionStore
    let selectTab: (SonaTab) -> Void
    let manageAccount: () -> Void
    let editAvatar: () -> Void
    let showAchievements: () -> Void
    let manageUsers: () -> Void
    let close: () -> Void

    private var user: UserResponse? {
        session.currentUser
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                SonaAvatarView(
                    username: user?.username ?? "Sona",
                    avatarPreset: user?.avatarPreset,
                    avatarURL: user?.avatarURL,
                    size: 58
                )
                VStack(alignment: .leading, spacing: 5) {
                    Text(user?.username ?? "Sona")
                        .font(.title3.bold())
                    Text(user?.isAdmin == true ? "管理员账户" : "普通用户")
                        .font(.subheadline)
                        .foregroundStyle(Color.sonaSecondaryText)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 116)

            Divider().overlay(Color.white.opacity(0.12))

            drawerButton("最近播放", systemImage: "clock.arrow.circlepath") {
                selectTab(.home)
                close()
            }
            drawerButton("音乐库", systemImage: "books.vertical") {
                selectTab(.library)
                close()
            }
            drawerButton("账户安全", systemImage: "person.crop.circle.badge.checkmark") {
                close()
                manageAccount()
            }
            drawerButton("编辑头像", systemImage: "photo.badge.plus") {
                close()
                editAvatar()
            }
            drawerButton("我的成就", systemImage: "trophy.fill") {
                close()
                showAchievements()
            }
            drawerButton("设置和隐私", systemImage: "gearshape") {
                selectTab(.settings)
                close()
            }
            if user?.isAdmin == true {
                drawerButton("用户管理", systemImage: "person.2") {
                    close()
                    manageUsers()
                }
            }

            Spacer()

            Divider().overlay(Color.white.opacity(0.12))
            Button(role: .destructive) {
                close()
                Task { await session.logout() }
            } label: {
                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 58)
                    .padding(.horizontal, 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .background(Color(red: 0.125, green: 0.125, blue: 0.125))
    }

    private func drawerButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 58)
                .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}

struct AchievementsView: View {
    @State private var summary: AchievementSummary?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            if let summary {
                LazyVStack(alignment: .leading, spacing: 22) {
                    levelCard(summary)
                    statsGrid(summary.stats)
                    badgeSection(summary.badges)
                    historySection(summary.history)
                }
                .padding(16)
            } else if isLoading {
                ProgressView("正在载入成就…")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
            } else {
                ContentUnavailableView(
                    "无法载入成就",
                    systemImage: "trophy",
                    description: Text(errorMessage ?? "请稍后重试")
                )
                .padding(.top, 70)
            }
        }
        .background(Color.sonaBackground.ignoresSafeArea())
        .navigationTitle("我的成就")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func levelCard(_ summary: AchievementSummary) -> some View {
        let level = summary.level
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("LISTENING STATUS")
                        .font(.caption2.bold())
                        .tracking(2.2)
                        .foregroundStyle(Color.sonaGreen)
                    Text(level.title)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                    Text(level.englishTitle)
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(Color.sonaSecondaryText)
                }
                Spacer()
                Image(systemName: level.icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.sonaGreen)
                    .frame(width: 66, height: 66)
                    .background(Color.white.opacity(0.07), in: Circle())
                    .overlay(Circle().stroke(Color.sonaGreen.opacity(0.45)))
            }
            HStack(alignment: .lastTextBaseline) {
                Text("\(summary.stats.total)")
                    .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                Text("次有效聆听")
                    .font(.subheadline)
                    .foregroundStyle(Color.sonaSecondaryText)
                Spacer()
                Text(level.nextTitle.map { "距 \($0) 还差 \(max(0, (level.nextThreshold ?? 0) - summary.stats.total)) 次" } ?? "已解锁最高等级")
                    .font(.caption2)
                    .foregroundStyle(Color.sonaSecondaryText)
            }
            if let threshold = level.nextThreshold, threshold > level.minimum {
                ProgressView(
                    value: Double(summary.stats.total - level.minimum),
                    total: Double(threshold - level.minimum)
                )
                .tint(.sonaGreen)
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [Color.sonaSurface, Color.sonaBackgroundDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    private func statsGrid(_ stats: AchievementStats) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
            achievementStat(stats.today, "今日")
            achievementStat(stats.uniqueTracks, "不同歌曲")
            achievementStat(stats.longestStreak, "最长连续")
            achievementStat(stats.bestDaily, "单日最佳")
        }
    }

    private func achievementStat(_ value: Int, _ title: String) -> some View {
        VStack(spacing: 5) {
            Text("\(value)").font(.title3.bold().monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(Color.sonaSecondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 66)
        .background(Color.sonaSurface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func badgeSection(_ badges: [AchievementBadge]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("荣誉徽章", "ACHIEVEMENTS")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(badges) { badge in
                    HStack(spacing: 10) {
                        Image(systemName: badge.unlocked ? badge.icon : "lock.fill")
                            .foregroundStyle(badge.unlocked ? Color.sonaGreen : Color.sonaSecondaryText)
                            .frame(width: 38, height: 38)
                            .background(Color.sonaBackground, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(badge.title).font(.caption.bold())
                            Text(badge.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.sonaSecondaryText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .background(Color.sonaSurface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(badge.unlocked ? Color.sonaGreen.opacity(0.4) : Color.clear)
                    }
                }
            }
        }
    }

    private func historySection(_ history: [AchievementHistoryItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("聆听足迹", "LISTENING LOG")
            if history.isEmpty {
                Text("播放歌曲超过 5 秒后，会在这里留下第一条足迹。")
                    .font(.subheadline)
                    .foregroundStyle(Color.sonaSecondaryText)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.sonaSurface, in: RoundedRectangle(cornerRadius: 16))
            } else {
                ForEach(history) { item in
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundStyle(Color.sonaGreen)
                            .frame(width: 34, height: 34)
                            .background(Color.sonaSurface, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text("\(item.artist) · \(dateText(item.playedAt))")
                                .font(.caption)
                                .foregroundStyle(Color.sonaSecondaryText)
                        }
                        Spacer()
                        Text("\(Int(item.progressPercent))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.sonaSecondaryText)
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption2.bold()).tracking(1.4).foregroundStyle(Color.sonaGreen)
        }
    }

    private func dateText(_ milliseconds: Int64) -> String {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
            .formatted(date: .abbreviated, time: .shortened)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            summary = try await APIClient.shared.achievements()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
