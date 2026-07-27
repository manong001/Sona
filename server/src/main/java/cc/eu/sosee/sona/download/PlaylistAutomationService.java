package cc.eu.sosee.sona.download;

import cc.eu.sosee.sona.auth.SystemNotificationService;
import cc.eu.sosee.sona.auth.UserPreferencesService;
import java.util.stream.Collectors;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

@Service
class PlaylistAutomationService {

    private final PlaylistSubscriptionRepository subscriptions;
    private final PlaylistSubscriptionService subscriptionService;
    private final UserPreferencesService userPreferences;
    private final PlaylistAutomationRepository runs;
    private final SystemNotificationService notifications;

    PlaylistAutomationService(
        PlaylistSubscriptionRepository subscriptions,
        PlaylistSubscriptionService subscriptionService,
        UserPreferencesService userPreferences,
        PlaylistAutomationRepository runs,
        SystemNotificationService notifications
    ) {
        this.subscriptions = subscriptions;
        this.subscriptionService = subscriptionService;
        this.userPreferences = userPreferences;
        this.runs = runs;
        this.notifications = notifications;
    }

    @Scheduled(fixedDelay = 60_000, initialDelay = 90_000)
    void maintainSubscriptions() {
        finishDownloadRuns();
        runDueAutomations();
    }

    void runDueAutomations() {
        for (var subscription : subscriptions.findAllEnabled()) {
            var settings = userPreferences.playlistAutomationSettings(subscription.userId());
            if (!settings.enabled()
                || !runs.isDue(subscription.id(), settings.intervalHours())) {
                continue;
            }
            run(subscription, settings);
        }
    }

    void finishDownloadRuns() {
        for (var run : runs.pending()) {
            var tasks = runs.tasks(run.id());
            if (tasks.stream().anyMatch(task -> !task.terminal())) {
                continue;
            }
            var failures = tasks.stream()
                .filter(PlaylistAutomationRepository.RunTask::failed)
                .toList();
            if (!failures.isEmpty()) {
                notifications.notifyPlaylistDownloadFailures(
                    run.userId(), run.playlistName(), failures.size(),
                    summarize(failures)
                );
            }
            runs.complete(run.id());
        }
    }

    private void run(
        PlaylistSubscriptionRepository.Subscription subscription,
        UserPreferencesService.PlaylistAutomationSettings settings
    ) {
        var runId = runs.start(subscription);
        try {
            var sync = subscriptionService.syncForAutomation(subscription);
            if (!sync.performed()) {
                runs.cancel(runId);
                return;
            }
            var matchedCount = 0;
            var includeSuggested = false;
            if (!"MANUAL".equals(settings.matchMode())) {
                var mode = PlaylistSubscriptionService.BestMatchMode.valueOf(
                    settings.matchMode()
                );
                matchedCount = subscriptionService.applyBestMatches(
                    subscription.userId(), subscription.id(), mode
                ).matchedCount();
                includeSuggested = true;
            }
            if ("MANUAL".equals(settings.matchMode())
                && sync.subscription().suggestedCount() > 0) {
                runs.waitForDownloads(runId, 0, java.util.List.of());
                return;
            }
            var downloads = subscriptionService.queueAutomationOriginals(
                subscription.userId(), subscription.id(), includeSuggested
            );
            runs.waitForDownloads(runId, matchedCount, downloads.tasks());
        } catch (RuntimeException exception) {
            runs.fail(runId, conciseMessage(exception));
        }
    }

    private String summarize(
        java.util.List<PlaylistAutomationRepository.RunTask> failures
    ) {
        var songs = failures.stream()
            .limit(5)
            .map(task -> "《" + task.title() + "》"
                + (task.artist().isBlank() ? "" : " - " + task.artist()))
            .collect(Collectors.joining("；"));
        if (failures.size() > 5) {
            songs += "；另有 " + (failures.size() - 5) + " 首";
        }
        return songs;
    }

    private String conciseMessage(RuntimeException exception) {
        var message = exception.getMessage();
        if (message == null || message.isBlank()) {
            message = exception.getClass().getSimpleName();
        }
        return message.length() <= 500 ? message : message.substring(0, 500);
    }
}
