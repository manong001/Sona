import SwiftUI

struct SonaCollection: Identifiable {
    enum Shape {
        case square
        case circle
    }

    let id: String
    let title: String
    let subtitle: String
    let artworkURL: String?
    let tracks: [Track]
    let shape: Shape
}

func sonaAlbums(from tracks: [Track]) -> [SonaCollection] {
    Dictionary(grouping: tracks) { $0.album }
        .map { album, albumTracks in
            SonaCollection(
                id: "album-\(album)",
                title: album,
                subtitle: albumTracks.first?.artist ?? "未知艺人",
                artworkURL: albumTracks.first(where: { $0.artworkURL != nil })?.artworkURL,
                tracks: albumTracks.sorted {
                    ($0.trackNumber ?? Int.max, $0.title) < ($1.trackNumber ?? Int.max, $1.title)
                },
                shape: .square
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
}

func sonaArtists(from tracks: [Track]) -> [SonaCollection] {
    Dictionary(grouping: tracks) { $0.artist }
        .map { artist, artistTracks in
            SonaCollection(
                id: "artist-\(artist)",
                title: artist,
                subtitle: "艺人",
                artworkURL: artistTracks.first(where: { $0.artworkURL != nil })?.artworkURL,
                tracks: artistTracks,
                shape: .circle
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
}

@MainActor
func sonaUniqueHistoryTracks(_ history: [HistoryItem], library: LibraryStore) -> [Track] {
    var seen = Set<String>()
    return history.compactMap { item in
        guard seen.insert(item.trackID).inserted else { return nil }
        return library.track(id: item.trackID)
    }
}

struct SonaAvatarButton: View {
    let username: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SonaAvatarView(username: username, size: 38)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开账户菜单")
    }
}

struct SonaAvatarView: View {
    let username: String
    var size: CGFloat = 44

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.sonaGreen.opacity(0.95), Color(red: 0.02, green: 0.28, blue: 0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Text(String(username.trimmingCharacters(in: .whitespaces).first ?? "S").uppercased())
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.82))
            }
            .frame(width: size, height: size)
            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
    }
}

struct SonaFilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color.black.opacity(0.86) : .white)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(isSelected ? Color.sonaGreen : Color.sonaChip, in: Capsule())
            .buttonStyle(.plain)
    }
}

struct SonaSectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.white)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.sonaSecondaryText)
            }
        }
    }
}

struct SonaLikedCover: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.30, green: 0.10, blue: 0.95), Color(red: 0.67, green: 0.88, blue: 0.77)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "heart.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

struct SonaCollectionArtwork: View {
    let collection: SonaCollection
    var size: CGFloat

    var body: some View {
        ArtworkView(path: collection.artworkURL, cornerRadius: collection.shape == .circle ? size / 2 : 6)
            .frame(width: size, height: size)
            .clipShape(collection.shape == .circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
    }
}

struct SonaMediaCard: View {
    let collection: SonaCollection
    var width: CGFloat = 158

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SonaCollectionArtwork(collection: collection, size: width)
            Text(collection.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(collection.subtitle)
                .font(.caption)
                .foregroundStyle(Color.sonaSecondaryText)
                .lineLimit(2)
        }
        .frame(width: width, alignment: .leading)
    }
}

struct SonaTrackListView: View {
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var personal: PersonalStore
    let collection: SonaCollection

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.sonaSurface.opacity(0.95), .sonaBackground, .sonaBackground],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 0) {
                    VStack(spacing: 18) {
                        SonaCollectionArtwork(collection: collection, size: 230)
                            .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
                        VStack(spacing: 5) {
                            Text(collection.title)
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                            Text(collection.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(Color.sonaSecondaryText)
                        }
                        HStack {
                            Text("\(collection.tracks.count) 首歌曲")
                                .font(.caption)
                                .foregroundStyle(Color.sonaSecondaryText)
                            Spacer()
                            Button {
                                guard let first = collection.tracks.first else { return }
                                player.play(
                                    track: first,
                                    queue: collection.tracks,
                                    offlineURLProvider: offline.localURL(for:)
                                )
                            } label: {
                                Image(systemName: "play.fill")
                                    .font(.title2)
                                    .foregroundStyle(.black)
                                    .frame(width: 56, height: 56)
                                    .background(Color.sonaGreen, in: Circle())
                            }
                            .disabled(collection.tracks.isEmpty)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)

                    ForEach(collection.tracks) { track in
                        Button {
                            player.play(
                                track: track,
                                queue: collection.tracks,
                                offlineURLProvider: offline.localURL(for:)
                            )
                        } label: {
                            TrackRow(
                                track: track,
                                showsOfflineBadge: offline.downloadedIDs.contains(track.id),
                                isFavorite: personal.favoriteIDs.contains(track.id)
                            )
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.sonaBackground.opacity(0.96), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
