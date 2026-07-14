package cc.eu.sosee.sona.library;

import cc.eu.sosee.sona.config.SonaProperties;
import java.nio.file.Files;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

@Component
class StartupScan implements ApplicationRunner {

    private final SonaProperties properties;
    private final ScanCoordinator coordinator;

    StartupScan(SonaProperties properties, ScanCoordinator coordinator) {
        this.properties = properties;
        this.coordinator = coordinator;
    }

    @Override
    public void run(ApplicationArguments arguments) {
        if (properties.isScanOnStartup() && Files.isDirectory(properties.getMusicDir())) {
            coordinator.start();
        }
    }
}

