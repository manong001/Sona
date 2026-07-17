import Foundation

struct SocialUser: Codable, Identifiable, Equatable {
    let id: String
    let username: String
    let role: String
    let displayName: String
    let signature: String
    let avatarPreset: String?
    let avatarURL: String?
    let online: Bool
    let lastSeenAt: Int64?
    let lastLoginAt: Int64?
    let friend: Bool?
    let unreadCount: Int?
    let lastMessage: SocialMessage?

    var isAdmin: Bool { role == "ADMIN" }
}

struct SharedTrackPayload: Codable, Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let artworkURL: String?
}

struct SocialMessage: Codable, Identifiable, Equatable {
    let id: String
    let senderId: String
    let recipientId: String
    let kind: String
    let text: String
    let payload: SharedTrackPayload?
    let createdAt: Int64
    let recalledAt: Int64?
    let readAt: Int64?
    let mine: Bool

    var canRecall: Bool {
        mine && recalledAt == nil
            && Date().timeIntervalSince1970 * 1_000 - Double(createdAt) <= 120_000
    }
}

struct SocialMedia: Codable, Identifiable, Equatable {
    let id: String
    let kind: String
    let mimeType: String
    let originalName: String
    let sizeBytes: Int64
    let groupId: String?
    let component: String?
    let url: String
}

struct SocialComment: Codable, Identifiable, Equatable {
    let id: String
    let user: SocialUser
    let body: String
    let createdAt: Int64
}

struct SocialMoment: Codable, Identifiable, Equatable {
    let id: String
    let user: SocialUser
    let text: String
    let createdAt: Int64
    let media: [SocialMedia]
    let likes: [SocialUser]
    let comments: [SocialComment]
    let liked: Bool
}

enum SocialSection: String, CaseIterable, Identifiable {
    case messages, contacts, moments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .messages: "消息"
        case .contacts: "通讯录"
        case .moments: "朋友圈"
        }
    }

    var icon: String {
        switch self {
        case .messages: "bubble.left.and.bubble.right.fill"
        case .contacts: "person.2.fill"
        case .moments: "camera.aperture"
        }
    }
}

struct SocialServiceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
