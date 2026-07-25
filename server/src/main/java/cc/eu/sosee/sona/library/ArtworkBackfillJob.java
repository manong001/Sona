package cc.eu.sosee.sona.library;

import java.time.Clock;
import java.time.Duration;
import java.util.concurrent.atomic.AtomicBoolean;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.core.task.TaskExecutor;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
class ArtworkBackfillJob {

    private static final Logger LOGGER = LoggerFactory.getLogger(ArtworkBackfillJob.class);
    private static final int BATCH_SIZE = 20;
    private static final int MINIMUM_CONFIDENCE = 80;
    private static final long[] RETRY_DELAYS = {
        Duration.ofDays(1).toMillis(),
        Duration.ofDays(3).toMillis(),
        Duration.ofDays(7).toMillis(),
        Duration.ofDays(30).toMillis()
    };

    private final ArtworkBackfillRepository repository;
    private final MetadataScraper metadataScraper;
    private final ArtworkStore artworkStore;
    private final Clock clock;
    private final TaskExecutor taskExecutor;
    private final AtomicBoolean scheduled = new AtomicBoolean();

    ArtworkBackfillJob(
        ArtworkBackfillRepository repository,
        MetadataScraper metadataScraper,
        ArtworkStore artworkStore,
        Clock clock,
        @Qualifier("scanTaskExecutor") TaskExecutor taskExecutor
    ) {
        this.repository = repository;
        this.metadataScraper = metadataScraper;
        this.artworkStore = artworkStore;
        this.clock = clock;
        this.taskExecutor = taskExecutor;
    }

    @Scheduled(fixedDelay = 3_600_000, initialDelay = 120_000)
    void schedule() {
        if (!scheduled.compareAndSet(false, true)) {
            return;
        }
        try {
            taskExecutor.execute(() -> {
                try {
                    runBatch();
                } finally {
                    scheduled.set(false);
                }
            });
        } catch (RuntimeException exception) {
            scheduled.set(false);
            LOGGER.warn("无法提交缺失歌曲封面补全任务", exception);
        }
    }

    Result runBatch() {
        var now = clock.millis();
        var candidates = repository.findDue(now, BATCH_SIZE);
        var succeeded = 0;
        var failed = 0;
        for (var candidate : candidates) {
            try {
                backfill(candidate);
                succeeded++;
            } catch (Exception exception) {
                failed++;
                var attempts = candidate.attempts() + 1;
                var retryAt = now + RETRY_DELAYS[Math.min(
                    attempts - 1, RETRY_DELAYS.length - 1
                )];
                repository.markFailed(
                    candidate.track().id(), attempts, retryAt,
                    conciseMessage(exception), now
                );
            }
        }
        if (!candidates.isEmpty()) {
            LOGGER.info(
                "缺失歌曲封面补全完成：处理 {}，成功 {}，失败 {}",
                candidates.size(), succeeded, failed
            );
        }
        return new Result(candidates.size(), succeeded, failed);
    }

    private void backfill(ArtworkBackfillRepository.Candidate candidate) throws Exception {
        var track = candidate.track();
        var scraped = metadataScraper.scrape(new ScrapeRequest(
            track.title(),
            track.artist(),
            track.album(),
            track.durationMs(),
            false,
            false,
            false,
            true,
            false
        ));
        if (scraped.artwork() == null
            || scraped.artwork().length == 0
            || scraped.confidence() < MINIMUM_CONFIDENCE) {
            throw new IllegalStateException("未找到可信封面");
        }
        var artworkPath = artworkStore.save(
            track.id(), scraped.artwork(), scraped.artworkMimeType()
        );
        if (artworkPath == null) {
            throw new IllegalStateException("封面保存失败");
        }
        repository.markSucceeded(track.id(), artworkPath);
    }

    private String conciseMessage(Exception exception) {
        var message = exception.getMessage();
        if (message == null || message.isBlank()) {
            message = exception.getClass().getSimpleName();
        }
        return message.length() <= 500 ? message : message.substring(0, 500);
    }

    record Result(int attempted, int succeeded, int failed) {
    }
}
