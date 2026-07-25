import Foundation

struct UserPreferences: Codable, Equatable {
    let childMode: Bool
    let childTheme: String
    let miniPlayerMode: String
    let miniPlayerSide: String
    let miniPlayerY: Double
    let hapticStrength: String
    let appIcon: String
    let playlistVersionManagementEnabled: Bool
}

struct UserPreferencesResponse: Decodable {
    let configured: Bool
    let childMode: Bool?
    let childTheme: String?
    let miniPlayerMode: String?
    let miniPlayerSide: String?
    let miniPlayerY: Double?
    let hapticStrength: String?
    let appIcon: String?
    let playlistVersionManagementEnabled: Bool?
    let updatedAt: Int64?

    var preferences: UserPreferences? {
        guard configured,
              let childMode,
              let childTheme,
              let miniPlayerMode,
              let miniPlayerSide,
              let miniPlayerY,
              let hapticStrength,
              let appIcon else {
            return nil
        }
        return UserPreferences(
            childMode: childMode,
            childTheme: childTheme,
            miniPlayerMode: miniPlayerMode,
            miniPlayerSide: miniPlayerSide,
            miniPlayerY: miniPlayerY,
            hapticStrength: hapticStrength,
            appIcon: appIcon,
            playlistVersionManagementEnabled: playlistVersionManagementEnabled ?? false
        )
    }
}
