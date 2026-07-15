import Foundation

let mainTabView = try String(
    contentsOfFile: "ios/Sona/Views/MainTabView.swift",
    encoding: .utf8
)

precondition(
    mainTabView.contains("if selectedTab != .search"),
    "The mini player must be hidden while the search tab is selected"
)

print("Search mini player visibility OK")
