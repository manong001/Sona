import Foundation
import UIKit

@MainActor
final class UserPreferencesStore: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var statusMessage: String?

    private let api: APIClient
    private let defaults: UserDefaults
    private var activeUserID: String?
    private var lastSynced: UserPreferences?
    private var isApplyingRemote = false
    private var saveTask: Task<Void, Never>?
    private var defaultsObserver: NSObjectProtocol?

    init(api: APIClient = .shared, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleUpload()
            }
        }
    }

    func beginSession(userID: String) async {
        guard activeUserID != userID else { return }
        saveTask?.cancel()
        activeUserID = userID
        lastSynced = nil
        statusMessage = nil
        isSyncing = true
        defer { isSyncing = false }

        do {
            let response = try await api.userPreferences()
            guard activeUserID == userID else { return }
            if let preferences = response.preferences {
                lastSynced = preferences
                apply(preferences)
                statusMessage = "已恢复服务器配置"
            } else {
                let local = currentPreferences()
                _ = try await api.saveUserPreferences(local)
                lastSynced = local
                statusMessage = "当前配置已保存到服务器"
            }
        } catch {
            statusMessage = "配置同步失败：\(error.localizedDescription)"
        }
    }

    func restoreFromServer() async {
        guard activeUserID != nil else {
            statusMessage = "请先登录账号"
            return
        }
        saveTask?.cancel()
        isSyncing = true
        defer { isSyncing = false }
        do {
            let response = try await api.userPreferences()
            guard let preferences = response.preferences else {
                statusMessage = "服务器暂无可恢复的配置"
                return
            }
            lastSynced = preferences
            apply(preferences)
            statusMessage = "已恢复服务器配置"
        } catch {
            statusMessage = "恢复失败：\(error.localizedDescription)"
        }
    }

    func endSession() {
        saveTask?.cancel()
        saveTask = nil
        activeUserID = nil
        lastSynced = nil
        statusMessage = nil
        isSyncing = false
    }

    private func scheduleUpload() {
        guard activeUserID != nil, !isApplyingRemote else { return }
        let preferences = currentPreferences()
        guard preferences != lastSynced else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await self?.uploadCurrentPreferences()
        }
    }

    private func uploadCurrentPreferences() async {
        guard activeUserID != nil, !isApplyingRemote else { return }
        let preferences = currentPreferences()
        guard preferences != lastSynced else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            _ = try await api.saveUserPreferences(preferences)
            lastSynced = preferences
            statusMessage = "配置已同步"
        } catch {
            statusMessage = "配置同步失败：\(error.localizedDescription)"
        }
    }

    private func currentPreferences() -> UserPreferences {
        UserPreferences(
            childMode: defaults.bool(forKey: "childMode"),
            childTheme: defaults.string(forKey: "childTheme") ?? "boy",
            miniPlayerMode: defaults.string(forKey: "miniPlayerMode") ?? "floating",
            miniPlayerSide: defaults.string(forKey: "miniPlayerSide") ?? "right",
            miniPlayerY: defaults.double(forKey: "miniPlayerY"),
            hapticStrength: defaults.string(forKey: SonaHaptics.preferenceKey)
                ?? SonaHapticStrength.medium.rawValue,
            appIcon: defaults.string(forKey: "appIconPreference")
                ?? (UIApplication.shared.alternateIconName == nil ? "girl" : "spotify"),
            playlistVersionManagementEnabled: defaults.bool(
                forKey: "playlistVersionManagementEnabled"
            )
        )
    }

    private func apply(_ preferences: UserPreferences) {
        isApplyingRemote = true
        defaults.set(preferences.childMode, forKey: "childMode")
        defaults.set(preferences.childTheme, forKey: "childTheme")
        defaults.set(preferences.miniPlayerMode, forKey: "miniPlayerMode")
        defaults.set(preferences.miniPlayerSide, forKey: "miniPlayerSide")
        defaults.set(preferences.miniPlayerY, forKey: "miniPlayerY")
        defaults.set(preferences.hapticStrength, forKey: SonaHaptics.preferenceKey)
        defaults.set(preferences.appIcon, forKey: "appIconPreference")
        defaults.set(
            preferences.playlistVersionManagementEnabled,
            forKey: "playlistVersionManagementEnabled"
        )
        isApplyingRemote = false

        guard UIApplication.shared.supportsAlternateIcons else { return }
        let iconName = preferences.appIcon == "spotify" ? "SpotifyIcon" : nil
        guard UIApplication.shared.alternateIconName != iconName else { return }
        UIApplication.shared.setAlternateIconName(iconName)
    }
}
