import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @AppStorage("serverURL") private var serverURL = APIClient.defaultServerURL

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器") {
                    TextField("Base URL", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Label("当前连接使用明文 HTTP", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                if session.currentUser?.isAdmin == true {
                    Section("曲库维护") {
                        NavigationLink {
                            MusicDownloadView()
                        } label: {
                            Label("多源音乐下载", systemImage: "arrow.down.circle")
                        }

                        Button {
                            Task { await library.scan() }
                        } label: {
                            Label(
                                library.scanStatus?.state == "RUNNING" ? "正在扫描…" : "扫描并刮削曲库",
                                systemImage: "arrow.clockwise"
                            )
                        }
                        .disabled(library.scanStatus?.state == "RUNNING")

                        if let status = library.scanStatus {
                            LabeledContent("状态", value: stateText(status.state))
                            LabeledContent("发现", value: "\(status.discovered)")
                            LabeledContent("新增 / 更新", value: "\(status.imported) / \(status.updated)")
                            LabeledContent("跳过 / 失败", value: "\(status.skipped) / \(status.failed)")
                            if let message = status.message {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }

                Section("账号") {
                    if let user = session.currentUser {
                        LabeledContent("当前账号", value: user.username)
                        LabeledContent("角色", value: user.isAdmin ? "管理员" : "用户")
                    }
                    NavigationLink("账户安全") {
                        AccountSecurityView()
                    }
                    if session.currentUser?.isAdmin == true {
                        NavigationLink("用户管理") {
                            UserManagementView()
                        }
                    }
                    Button("退出登录", role: .destructive) {
                        Task { await session.logout() }
                    }
                }

                Section("关于") {
                    LabeledContent("应用", value: "Sona")
                    LabeledContent("版本", value: "0.4.0")
                    Text("本地标签优先；MusicBrainz、LRCLIB、Cover Art Archive 与多源候选仅补全缺失信息。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.sonaBackground)
            .tint(.sonaGreen)
            .navigationTitle("设置")
            .toolbarBackground(Color.sonaBackground, for: .navigationBar)
        }
    }

    private func stateText(_ state: String) -> String {
        switch state {
        case "RUNNING": "运行中"
        case "COMPLETED": "已完成"
        case "FAILED": "失败"
        default: "空闲"
        }
    }
}

private struct AccountSecurityView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""

    var body: some View {
        Form {
            Section("修改密码") {
                SecureField("当前密码", text: $currentPassword)
                    .textContentType(.password)
                SecureField("新密码（至少 8 位）", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("再次输入新密码", text: $confirmation)
                    .textContentType(.newPassword)
                Button("修改密码") {
                    Task {
                        _ = await session.changePassword(
                            currentPassword: currentPassword,
                            newPassword: newPassword
                        )
                    }
                }
                .disabled(
                    session.isSubmitting ||
                    currentPassword.isEmpty ||
                    newPassword.count < 8 ||
                    newPassword != confirmation
                )
            }

            if let message = session.errorMessage {
                Section {
                    Text(message).foregroundStyle(.red)
                }
            }

            Section {
                Button("退出所有设备", role: .destructive) {
                    Task { await session.logoutAll() }
                }
            } footer: {
                Text("修改密码也会使所有已登录设备退出。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.sonaBackground)
        .tint(.sonaGreen)
        .navigationTitle("账户安全")
    }
}

private struct UserManagementView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var users: [ManagedUser] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showsCreate = false
    @State private var newUsername = ""
    @State private var newPassword = ""
    @State private var newRole: UserRole = .user
    @State private var resetUser: ManagedUser?
    @State private var resetPassword = ""
    @State private var deleteUser: ManagedUser?

    var body: some View {
        List {
            if users.isEmpty && isLoading {
                ProgressView("载入用户…")
            } else {
                ForEach(users) { user in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.username).fontWeight(.semibold)
                            Text(user.role.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(user.enabled ? "正常" : "已停用")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(user.enabled ? Color.sonaGreen : .secondary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if canManage(user) {
                            Button(user.enabled ? "停用" : "启用") {
                                Task { await setEnabled(user, enabled: !user.enabled) }
                            }
                            .tint(user.enabled ? .orange : .green)
                            Button("删除", role: .destructive) {
                                deleteUser = user
                            }
                        }
                    }
                    .contextMenu {
                        if canManage(user) {
                            Button("重置密码", systemImage: "key") {
                                resetPassword = ""
                                resetUser = user
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.sonaBackground)
        .tint(.sonaGreen)
        .navigationTitle("用户管理")
        .toolbar {
            Button("新建用户", systemImage: "person.badge.plus") {
                newUsername = ""
                newPassword = ""
                newRole = .user
                showsCreate = true
            }
        }
        .refreshable { await loadUsers() }
        .task { await loadUsers() }
        .sheet(isPresented: $showsCreate) {
            NavigationStack {
                Form {
                    Section("账号") {
                        TextField("用户名", text: $newUsername)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("密码（至少 8 位）", text: $newPassword)
                    }
                    Section("角色") {
                        Picker("用户角色", selection: $newRole) {
                            ForEach(UserRole.allCases) { role in
                                Text(role.title).tag(role)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    if let errorMessage {
                        Section {
                            Text(errorMessage).foregroundStyle(.red)
                        }
                    }
                }
                .navigationTitle("新建用户")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showsCreate = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("创建") { Task { await createUser() } }
                            .disabled(newUsername.count < 2 || newPassword.count < 8)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .alert("重置密码", isPresented: resetAlertBinding) {
            SecureField("新密码（至少 8 位）", text: $resetPassword)
            Button("取消", role: .cancel) { resetUser = nil }
            Button("重置") { Task { await performPasswordReset() } }
                .disabled(resetPassword.count < 8)
        } message: {
            Text("该用户的所有设备会退出登录。")
        }
        .confirmationDialog(
            "删除用户 \(deleteUser?.username ?? "")？",
            isPresented: deleteDialogBinding,
            titleVisibility: .visible
        ) {
            Button("删除用户及个人数据", role: .destructive) {
                Task { await performDelete() }
            }
            Button("取消", role: .cancel) { deleteUser = nil }
        }
        .overlay(alignment: .bottom) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .padding(10)
                    .background(.red.opacity(0.9), in: Capsule())
                    .padding()
            }
        }
    }

    private var resetAlertBinding: Binding<Bool> {
        Binding(
            get: { resetUser != nil },
            set: { if !$0 { resetUser = nil } }
        )
    }

    private func canManage(_ user: ManagedUser) -> Bool {
        user.id != session.currentUser?.id
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { deleteUser != nil },
            set: { if !$0 { deleteUser = nil } }
        )
    }

    private func loadUsers() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            users = try await APIClient.shared.users()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createUser() async {
        do {
            users.append(try await APIClient.shared.createUser(
                username: newUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                password: newPassword,
                role: newRole
            ))
            showsCreate = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setEnabled(_ user: ManagedUser, enabled: Bool) async {
        do {
            let updated = try await APIClient.shared.setUserEnabled(id: user.id, enabled: enabled)
            replace(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performPasswordReset() async {
        guard let user = resetUser else { return }
        do {
            try await APIClient.shared.resetPassword(userID: user.id, password: resetPassword)
            resetUser = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performDelete() async {
        guard let user = deleteUser else { return }
        do {
            try await APIClient.shared.deleteUser(id: user.id)
            users.removeAll { $0.id == user.id }
            deleteUser = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replace(_ user: ManagedUser) {
        guard let index = users.firstIndex(where: { $0.id == user.id }) else { return }
        users[index] = user
    }
}
