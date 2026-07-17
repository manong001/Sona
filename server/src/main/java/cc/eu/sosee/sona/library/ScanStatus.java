package cc.eu.sosee.sona.library;

public record ScanStatus(
    State state,
    Phase phase,
    String currentDirectory,
    int completedDirectories,
    int totalDirectories,
    int discovered,
    int imported,
    int updated,
    int skipped,
    int failed,
    String message,
    java.util.List<String> errors
) {

    public enum State {
        IDLE,
        RUNNING,
        COMPLETED,
        FAILED
    }

    public enum Phase {
        IDLE,
        DISCOVERING_DIRECTORIES,
        SCANNING_FILES,
        SYNCING_PLAYLIST,
        FINALIZING,
        COMPLETED,
        FAILED
    }

    static ScanStatus idle() {
        return status(
            State.IDLE, Phase.IDLE, null, 0, 0,
            new ScanResult(0, 0, 0, 0, 0), null, java.util.List.of()
        );
    }

    static ScanStatus running() {
        return running(
            new ScanResult(0, 0, 0, 0, 0), Phase.DISCOVERING_DIRECTORIES, null, 0, 0
        );
    }

    static ScanStatus running(
        ScanResult result, Phase phase, String currentDirectory,
        int completedDirectories, int totalDirectories
    ) {
        return status(
            State.RUNNING, phase, currentDirectory, completedDirectories, totalDirectories,
            result, null, java.util.List.of()
        );
    }

    static ScanStatus completed(
        ScanResult result, java.util.List<String> errors, int totalDirectories
    ) {
        return status(
            State.COMPLETED, Phase.COMPLETED, null, totalDirectories, totalDirectories,
            result, null, errors
        );
    }

    static ScanStatus failed(Exception exception, ScanStatus previous) {
        var result = new ScanResult(
            previous.discovered(), previous.imported(), previous.updated(), previous.skipped(),
            Math.max(1, previous.failed())
        );
        return status(
            State.FAILED, Phase.FAILED, previous.currentDirectory(),
            previous.completedDirectories(), previous.totalDirectories(),
            result, exception.getMessage(), previous.errors()
        );
    }

    private static ScanStatus status(
        State state, Phase phase, String currentDirectory,
        int completedDirectories, int totalDirectories, ScanResult result,
        String message, java.util.List<String> errors
    ) {
        return new ScanStatus(
            state, phase, currentDirectory, completedDirectories, totalDirectories,
            result.discovered(), result.imported(), result.updated(), result.skipped(),
            result.failed(), message, errors
        );
    }
}
