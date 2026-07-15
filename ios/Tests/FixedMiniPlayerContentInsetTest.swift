import Foundation

let mainTabView = try String(
    contentsOfFile: "ios/Sona/Views/MainTabView.swift",
    encoding: .utf8
)

precondition(
    mainTabView.contains("@AppStorage(\"miniPlayerMode\")"),
    "Main tab layout must react to the selected mini player mode"
)
precondition(
    mainTabView.contains(".safeAreaInset(edge: .bottom, spacing: 0)"),
    "Scrollable page content must reserve room above the fixed mini player"
)
precondition(
    mainTabView.contains("miniPlayerMode == \"fixed\" && selectedTab != .search"),
    "Content clearance must apply only while the fixed mini player is visible"
)

print("Fixed mini player content inset OK")
