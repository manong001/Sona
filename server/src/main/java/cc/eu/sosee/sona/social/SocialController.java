package cc.eu.sosee.sona.social;

import cc.eu.sosee.sona.auth.AuthenticatedUser;
import cc.eu.sosee.sona.auth.UserAvatarService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.net.URI;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

import static org.springframework.http.HttpStatus.BAD_REQUEST;

@RestController
@RequestMapping("/api/v1/social")
class SocialController {

    private static final Set<String> AVATAR_PRESETS = Set.of(
        "aurora", "cosmos", "forest", "ocean", "sunset", "candy", "ember", "midnight"
    );

    private final SocialRepository repository;
    private final SocialMediaService mediaService;
    private final UserAvatarService avatarService;

    SocialController(
        SocialRepository repository,
        SocialMediaService mediaService,
        UserAvatarService avatarService
    ) {
        this.repository = repository;
        this.mediaService = mediaService;
        this.avatarService = avatarService;
    }

    @GetMapping("/profile")
    SocialUserResponse profile(@AuthenticationPrincipal AuthenticatedUser actor) {
        return repository.profile(actor);
    }

    @PutMapping("/profile")
    SocialUserResponse updateProfile(
        @AuthenticationPrincipal AuthenticatedUser actor,
        @Valid @RequestBody UpdateProfileRequest request
    ) {
        if (request.avatarPreset() != null && !AVATAR_PRESETS.contains(request.avatarPreset())) {
            throw new ResponseStatusException(BAD_REQUEST, "Unknown avatar preset");
        }
        if (request.avatarPreset() != null) {
            avatarService.selectPresetForUser(actor.id(), request.avatarPreset());
        }
        return repository.updateProfile(actor, request.displayName(), request.signature());
    }

    @PostMapping("/presence")
    ResponseEntity<Void> presence(@AuthenticationPrincipal AuthenticatedUser actor) {
        repository.touch(actor.id());
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/users")
    List<SocialUserResponse> users(
        @AuthenticationPrincipal AuthenticatedUser actor,
        @RequestParam(defaultValue = "") @Size(max = 80) String query
    ) {
        return repository.searchUsers(actor, query.strip());
    }

    @GetMapping("/friends")
    List<SocialUserResponse> friends(@AuthenticationPrincipal AuthenticatedUser actor) {
        return repository.friends(actor);
    }

    @PostMapping("/friends")
    ResponseEntity<FriendResponse> addFriend(
        @AuthenticationPrincipal AuthenticatedUser actor,
        @Valid @RequestBody AddFriendRequest request
    ) {
        var user = repository.addFriend(actor, request.username().strip());
        return ResponseEntity.created(URI.create("/api/v1/social/friends/" + user.id()))
            .body(new FriendResponse(user));
    }

    @DeleteMapping("/friends/{peerId}")
    ResponseEntity<Void> deleteFriend(
        @AuthenticationPrincipal AuthenticatedUser actor,
        @PathVariable String peerId
    ) {
        repository.deleteFriend(actor.id(), peerId);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/conversations")
    List<SocialUserResponse> conversations(@AuthenticationPrincipal AuthenticatedUser actor) {
        return repository.conversations(actor);
    }

    @GetMapping("/messages/{peerId}")
    List<SocialMessageResponse> messages(
        @AuthenticationPrincipal AuthenticatedUser actor,
        @PathVariable String peerId
    ) {
        return repository.messages(actor, peerId);
    }

    @PostMapping("/messages")
    ResponseEntity<SocialMessageResponse> sendMessage(
        @AuthenticationPrincipal AuthenticatedUser actor,
        @Valid @RequestBody SendMessageRequest request
    ) {
        var value = repository.sendMessage(
            actor, request.recipientId(), request.clientMessageId(), request.kind(),
            request.text(), request.payload()
        );
        return ResponseEntity.created(URI.create("/api/v1/social/messages/" + value.id())).body(value);
    }

    @PutMapping("/messages/{messageId}/recall")
    SocialMessageResponse recall(
        @AuthenticationPrincipal AuthenticatedUser actor,
        @PathVariable String messageId
    ) {
        return repository.recall(actor, messageId);
    }

    @PostMapping(path = "/media", consumes = "multipart/form-data")
    ResponseEntity<SocialMediaResponse> uploadMedia(
        @AuthenticationPrincipal AuthenticatedUser actor,
        @RequestParam MultipartFile file,
        @RequestParam String kind,
        @RequestParam(required = false) String filename,
        @RequestParam(required = false) String groupId,
        @RequestParam(required = false) String component
    ) {
        var value = mediaService.upload(actor, file, kind, filename, groupId, component);
        return ResponseEntity.created(URI.create(value.url())).body(value);
    }

    @GetMapping("/media/{mediaId}")
    ResponseEntity<org.springframework.core.io.Resource> media(
        @AuthenticationPrincipal AuthenticatedUser actor,
        @PathVariable String mediaId
    ) {
        var value = mediaService.download(actor, mediaId);
        return ResponseEntity.ok()
            .cacheControl(CacheControl.noStore())
            .contentType(MediaType.parseMediaType(value.mimeType()))
            .header(
                HttpHeaders.CONTENT_DISPOSITION,
                "inline; filename*=UTF-8''" + java.net.URLEncoder.encode(
                    value.originalName(), java.nio.charset.StandardCharsets.UTF_8
                ).replace("+", "%20")
            )
            .body(value.resource());
    }

    @GetMapping("/moments")
    List<SocialMomentResponse> moments(@AuthenticationPrincipal AuthenticatedUser actor) {
        return repository.moments(actor);
    }

    @PostMapping("/moments")
    ResponseEntity<SocialMomentResponse> createMoment(
        @AuthenticationPrincipal AuthenticatedUser actor,
        @RequestBody CreateMomentRequest request
    ) {
        var value = repository.createMoment(actor, request.text(), request.mediaIds());
        return ResponseEntity.created(URI.create("/api/v1/social/moments/" + value.id())).body(value);
    }

    @DeleteMapping("/moments/{momentId}")
    ResponseEntity<Void> deleteMoment(
        @AuthenticationPrincipal AuthenticatedUser actor,
        @PathVariable String momentId
    ) {
        repository.deleteMoment(actor, momentId);
        return ResponseEntity.noContent().build();
    }

    @PutMapping("/moments/{momentId}/like")
    ResponseEntity<Void> like(
        @AuthenticationPrincipal AuthenticatedUser actor,
        @PathVariable String momentId
    ) {
        repository.setLiked(actor, momentId, true);
        return ResponseEntity.noContent().build();
    }

    @DeleteMapping("/moments/{momentId}/like")
    ResponseEntity<Void> unlike(
        @AuthenticationPrincipal AuthenticatedUser actor,
        @PathVariable String momentId
    ) {
        repository.setLiked(actor, momentId, false);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/moments/{momentId}/comments")
    ResponseEntity<SocialCommentResponse> comment(
        @AuthenticationPrincipal AuthenticatedUser actor,
        @PathVariable String momentId,
        @Valid @RequestBody CommentRequest request
    ) {
        var value = repository.comment(actor, momentId, request.body());
        return ResponseEntity.created(
            URI.create("/api/v1/social/moments/" + momentId + "/comments/" + value.id())
        ).body(value);
    }

    record UpdateProfileRequest(
        @Size(max = 48) String displayName,
        @Size(max = 160) String signature,
        String avatarPreset
    ) {
        UpdateProfileRequest {
            signature = signature == null ? "" : signature;
        }
    }

    record AddFriendRequest(@NotBlank @Size(max = 32) String username) {
    }

    record FriendResponse(SocialUserResponse user) {
    }

    record SendMessageRequest(
        @NotBlank String recipientId,
        @Size(max = 80) String clientMessageId,
        @NotBlank String kind,
        String text,
        Map<String, Object> payload
    ) {
    }

    record CreateMomentRequest(String text, List<String> mediaIds) {
    }

    record CommentRequest(@NotBlank @Size(max = 500) String body) {
    }
}
