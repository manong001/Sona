import Foundation

let downloadView = try String(
    contentsOfFile: "ios/Sona/Views/MusicDownloadView.swift",
    encoding: .utf8
)

precondition(
    downloadView.contains("Button(\"搜索\", systemImage: \"magnifyingglass\")"),
    "Music download search must expose a visible button instead of relying only on keyboard submit"
)

print("Music download search trigger OK")
