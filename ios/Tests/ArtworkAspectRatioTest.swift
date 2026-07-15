import Foundation

let artworkView = try String(
    contentsOfFile: "ios/Sona/Views/ArtworkView.swift",
    encoding: .utf8
)

precondition(
    artworkView.contains(".aspectRatio(1, contentMode: .fill)"),
    "ArtworkView must force every source image into a square frame"
)
precondition(
    artworkView.contains(".scaledToFill()"),
    "ArtworkView must crop square artwork without stretching it"
)

print("Artwork square aspect-ratio behavior OK")
