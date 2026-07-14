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
    let close: () -> Void

    private var user: UserResponse? {
        session.currentUser
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                SonaAvatarView(username: user?.username ?? "Sona", size: 58)
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
            drawerButton("设置和隐私", systemImage: "gearshape") {
                selectTab(.settings)
                close()
            }
            if user?.isAdmin == true {
                drawerButton("用户管理", systemImage: "person.2") {
                    selectTab(.settings)
                    close()
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
