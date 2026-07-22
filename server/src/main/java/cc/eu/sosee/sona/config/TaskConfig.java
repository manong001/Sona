package cc.eu.sosee.sona.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.task.TaskExecutor;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

@Configuration
class TaskConfig {

    @Bean
    TaskExecutor scanTaskExecutor() {
        var executor = new ThreadPoolTaskExecutor();
        executor.setThreadNamePrefix("sona-library-scan-");
        executor.setCorePoolSize(1);
        executor.setMaxPoolSize(1);
        executor.setQueueCapacity(20);
        executor.initialize();
        return executor;
    }

    @Bean
    TaskExecutor downloadTaskExecutor() {
        var executor = new ThreadPoolTaskExecutor();
        executor.setThreadNamePrefix("sona-download-");
        executor.setCorePoolSize(4);
        executor.setMaxPoolSize(4);
        executor.setQueueCapacity(500);
        executor.initialize();
        return executor;
    }
}
