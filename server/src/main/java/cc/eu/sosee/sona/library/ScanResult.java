package cc.eu.sosee.sona.library;

public record ScanResult(
    int discovered,
    int imported,
    int updated,
    int skipped,
    int failed
) {
}

