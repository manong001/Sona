import Foundation

@MainActor
final class SessionStore: ObservableObject {
    enum State {
        case checking
        case signedOut
        case signedIn(UserResponse)
    }

    @Published private(set) var state: State = .checking
    @Published var isSubmitting = false
    @Published var errorMessage: String?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    var currentUser: UserResponse? {
        guard case let .signedIn(user) = state else { return nil }
        return user
    }

    func restore() async {
        do {
            let user = try await api.currentUser()
            state = .signedIn(user)
        } catch {
            state = .signedOut
        }
    }

    @discardableResult
    func login(username: String, password: String) async -> Bool {
        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = "请输入账号和密码"
            return false
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            RemoteImageCache.shared.removeAll()
            let user = try await api.login(username: username, password: password)
            state = .signedIn(user)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func logout() async {
        LoginCredentialStore.disableAutoLogin()
        try? await api.logout()
        RemoteImageCache.shared.removeAll()
        state = .signedOut
    }

    func changePassword(currentPassword: String, newPassword: String) async -> Bool {
        guard !currentPassword.isEmpty, newPassword.count >= 8 else {
            errorMessage = "新密码至少需要 8 个字符"
            return false
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await api.changePassword(
                currentPassword: currentPassword,
                newPassword: newPassword
            )
            LoginCredentialStore.disableAutoLogin()
            LoginCredentialStore.delete()
            RemoteImageCache.shared.removeAll()
            state = .signedOut
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func logoutAll() async {
        LoginCredentialStore.disableAutoLogin()
        try? await api.logoutAll()
        RemoteImageCache.shared.removeAll()
        state = .signedOut
    }

    func selectAvatar(_ preset: AvatarPreset) async -> Bool {
        await updateAvatar { try await api.setOwnAvatarPreset(preset) }
    }

    func uploadAvatar(_ imageData: Data) async -> Bool {
        await updateAvatar { try await api.uploadOwnAvatar(imageData: imageData) }
    }

    private func updateAvatar(_ operation: () async throws -> UserResponse) async -> Bool {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            state = .signedIn(try await operation())
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
