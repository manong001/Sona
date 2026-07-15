package cc.eu.sosee.sona.library;

public record ScanStatus(
    State state,
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

    static ScanStatus idle() {
        return new ScanStatus(State.IDLE, 0, 0, 0, 0, 0, null, java.util.List.of());
    }

    static ScanStatus running() {
        return new ScanStatus(State.RUNNING, 0, 0, 0, 0, 0, null, java.util.List.of());
    }

    static ScanStatus completed(ScanResult result, java.util.List<String> errors) {
        return new ScanStatus(
            State.COMPLETED,
            result.discovered(),
            result.imported(),
            result.updated(),
            result.skipped(),
            result.failed(),
            null,
            errors
        );
    }

    static ScanStatus failed(Exception exception) {
        return new ScanStatus(
            State.FAILED, 0, 0, 0, 0, 1, exception.getMessage(), java.util.List.of()
        );
    }
}
