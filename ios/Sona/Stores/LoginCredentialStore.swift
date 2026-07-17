import Foundation
import Security

struct LoginCredentials: Codable {
    let serverURL: String
    let username: String
    let password: String
}

enum LoginCredentialStore {
    static let rememberPasswordKey = "rememberPassword"
    static let autoLoginKey = "autoLogin"

    private static let service = "cc.eu.sosee.sona.login"
    private static let account = "lastLogin"

    static func load() -> LoginCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(LoginCredentials.self, from: data)
    }

    static func save(_ credentials: LoginCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        SecItemDelete(baseQuery as CFDictionary)

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    static func disableAutoLogin() {
        UserDefaults.standard.set(false, forKey: autoLoginKey)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
