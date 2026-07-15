import Foundation

let libraryView = try String(
    contentsOfFile: "ios/Sona/Views/MusicLibraryView.swift",
    encoding: .utf8
)
let spotifyComponents = try String(
    contentsOfFile: "ios/Sona/Views/SpotifyComponents.swift",
    encoding: .utf8
)
let apiClient = try String(
    contentsOfFile: "ios/Sona/Networking/APIClient.swift",
    encoding: .utf8
)

precondition(
    libraryView.contains("ServerDirectoryPicker"),
    "Playlist import must open the mounted server directory picker"
)
precondition(
    spotifyComponents.contains("ServerDirectoryPicker"),
    "Favorite import must open the mounted server directory picker"
)
precondition(
    apiClient.contains("func serverMusicDirectories(path: String)"),
    "The app must load server directories lazily"
)
precondition(
    apiClient.contains("func startScan(directory: String)"),
    "The selected server directory must be sent to the scan API"
)

print("Server directory import UI wiring OK")
