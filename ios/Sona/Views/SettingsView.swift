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

                Section("曲库维护") {
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

                Section("账号") {
                    if case let .signedIn(username) = session.state {
                        LabeledContent("当前账号", value: username)
                    }
                    Button("退出登录", role: .destructive) {
                        Task { await session.logout() }
                    }
                }

                Section("关于") {
                    LabeledContent("应用", value: "Sona")
                    LabeledContent("版本", value: "0.1.0")
                    Text("本地标签优先；MusicBrainz、LRCLIB 与 Cover Art Archive 仅补全缺失信息。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
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
