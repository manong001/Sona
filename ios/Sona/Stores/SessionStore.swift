import Foundation

@MainActor
final class SessionStore: ObservableObject {
    enum State {
        case checking
        case signedOut
        case signedIn(String)
    }

    @Published private(set) var state: State = .checking
    @Published var isSubmitting = false
    @Published var errorMessage: String?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func restore() async {
        do {
            let user = try await api.currentUser()
            state = .signedIn(user.username)
        } catch {
            state = .signedOut
        }
    }

    func login(username: String, password: String) async {
        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = "请输入账号和密码"
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let user = try await api.login(username: username, password: password)
            state = .signedIn(user.username)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() async {
        try? await api.logout()
        state = .signedOut
    }
}
