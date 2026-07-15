import Foundation

@main
private struct AppUpdateSettingsUITest {
    static func main() throws {
        let settings = try String(
            contentsOfFile: "ios/Sona/Views/SettingsView.swift",
            encoding: .utf8
        )

        for required in [
            "Section(\"App 更新\")",
            "Button(\"检查更新\"",
            "ProgressView(value: downloadProgress)",
            "UIActivityViewController"
        ] {
            precondition(settings.contains(required), "Missing update UI: \(required)")
        }

        print("App update settings UI OK")
    }
}
