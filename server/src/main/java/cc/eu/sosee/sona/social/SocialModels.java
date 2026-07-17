package cc.eu.sosee.sona.social;

import java.util.List;
import java.util.Map;

record SocialUserResponse(
    String id,
    String username,
    String role,
    String displayName,
    String signature,
    String avatarPreset,
    String avatarURL,
    boolean online,
    Long lastSeenAt,
    Long lastLoginAt,
    Boolean friend,
    Integer unreadCount,
    SocialMessageResponse lastMessage
) {
}

record SocialMessageResponse(
    String id,
    String senderId,
    String recipientId,
    String kind,
    String text,
    Map<String, Object> payload,
    long createdAt,
    Long recalledAt,
    Long readAt,
    boolean mine
) {
}

record SocialMediaResponse(
    String id,
    String kind,
    String mimeType,
    String originalName,
    long sizeBytes,
    String groupId,
    String component,
    String url
) {
}

record SocialCommentResponse(
    String id,
    SocialUserResponse user,
    String body,
    long createdAt
) {
}

record SocialMomentResponse(
    String id,
    SocialUserResponse user,
    String text,
    long createdAt,
    List<SocialMediaResponse> media,
    List<SocialUserResponse> likes,
    List<SocialCommentResponse> comments,
    boolean liked
) {
}

record SocialMediaFile(
    String id,
    String userId,
    String kind,
    String mimeType,
    String originalName,
    String storagePath,
    long sizeBytes,
    String groupId,
    String component
) {
    SocialMediaResponse response() {
        return new SocialMediaResponse(
            id, kind, mimeType, originalName, sizeBytes, groupId, component,
            "/api/v1/social/media/" + id
        );
    }
}
