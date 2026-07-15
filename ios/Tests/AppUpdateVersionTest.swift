import Foundation

@main
private struct AppUpdateVersionTest {
    static func main() {
        let update = AppReleaseInfo(
            available: true,
            version: "0.5.0",
            build: 6,
            notes: "更新中心",
            publishedAt: 1,
            fileSizeBytes: 1024,
            fileName: "Sona-unsigned.ipa",
            downloadURL: "/api/v1/app/releases/latest/ipa"
        )

        precondition(update.isNewer(thanVersion: "0.4.0", build: 99))
        precondition(update.isNewer(thanVersion: "0.5.0", build: 5))
        precondition(!update.isNewer(thanVersion: "0.5.0", build: 6))
        precondition(!update.isNewer(thanVersion: "0.6.0", build: 1))

        print("App update version comparison OK")
    }
}
