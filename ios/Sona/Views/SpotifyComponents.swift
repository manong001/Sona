import PhotosUI
import SwiftUI
import UIKit

enum SonaHapticStrength: String, CaseIterable, Identifiable {
    case off
    case light
    case medium
    case heavy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "关闭"
        case .light: "轻"
        case .medium: "中"
        case .heavy: "重"
        }
    }
}

enum SonaHaptics {
    static let preferenceKey = "hapticStrength"

    static func buttonFeedback() -> SensoryFeedback? {
#if os(iOS) && !targetEnvironment(macCatalyst)
        let rawValue = UserDefaults.standard.string(forKey: preferenceKey)
            ?? SonaHapticStrength.medium.rawValue
        switch SonaHapticStrength(rawValue: rawValue) {
        case .off:
            return nil
        case .light:
            return .impact(weight: .light, intensity: 0.45)
        case .medium:
            return .impact(weight: .medium, intensity: 0.72)
        case .heavy:
            return .impact(weight: .heavy)
        case nil:
            return nil
        }
#else
        return nil
#endif
    }

    static func selectionChanged() {
#if os(iOS) && !targetEnvironment(macCatalyst)
        let rawValue = UserDefaults.standard.string(forKey: preferenceKey)
            ?? SonaHapticStrength.medium.rawValue
        guard SonaHapticStrength(rawValue: rawValue) != .off else { return }
        UISelectionFeedbackGenerator().selectionChanged()
#endif
    }
}

enum SonaTrackSortMode: String, CaseIterable {
    case original
    case alphabetical

    var title: String {
        switch self {
        case .original: "默认顺序"
        case .alphabetical: "首字母排序"
        }
    }

    var systemImage: String {
        switch self {
        case .original: "line.3.horizontal"
        case .alphabetical: "textformat.abc"
        }
    }
}

struct SonaAlphabeticalTrackSection: Identifiable {
    let id: String
    let tracks: [Track]
}

func sonaAlphabeticalTrackSections(_ tracks: [Track]) -> [SonaAlphabeticalTrackSection] {
    let sorted = tracks.enumerated().map { index, track in
        (
            index: index,
            section: sonaTrackInitial(track.title),
            key: sonaTrackAlphabeticalKey(track.title),
            track: track
        )
    }
    .sorted { lhs, rhs in
        let comparison = lhs.key.localizedStandardCompare(rhs.key)
        if comparison == .orderedSame { return lhs.index < rhs.index }
        return comparison == .orderedAscending
    }

    var grouped: [String: [Track]] = [:]
    for value in sorted {
        grouped[value.section, default: []].append(value.track)
    }
    return grouped.keys
        .sorted { sonaAlphabetOrder($0) < sonaAlphabetOrder($1) }
        .map { SonaAlphabeticalTrackSection(id: $0, tracks: grouped[$0] ?? []) }
}

func sonaTrackSortSignature(_ tracks: [Track]) -> Int {
    var hasher = Hasher()
    for track in tracks {
        hasher.combine(track.id)
        hasher.combine(track.title)
    }
    return hasher.finalize()
}

private func sonaTrackInitial(_ title: String) -> String {
    let value = sonaTrackAlphabeticalKey(title)
    guard let scalar = value.unicodeScalars.first else { return "#" }
    let initial = String(scalar).uppercased()
    return initial.range(of: "^[A-Z]$", options: .regularExpression) == nil ? "#" : initial
}

private func sonaTrackAlphabeticalKey(_ title: String) -> String {
    let latin = title.applyingTransform(.toLatin, reverse: false) ?? title
    let folded = latin.folding(
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
        locale: Locale(identifier: "zh_CN")
    )
    return String(folded.drop { character in
        character.unicodeScalars.allSatisfy {
            !CharacterSet.alphanumerics.contains($0)
        }
    })
}

private func sonaAlphabetOrder(_ value: String) -> Int {
    guard value != "#", let scalar = value.unicodeScalars.first else { return 0 }
    return Int(scalar.value) - Int(UnicodeScalar("A").value) + 1
}

struct SonaTrackSortMenu: View {
    @Binding var mode: SonaTrackSortMode

    var body: some View {
        Menu {
            Picker("歌曲排序", selection: $mode) {
                ForEach(SonaTrackSortMode.allCases, id: \.self) { option in
                    Label(option.title, systemImage: option.systemImage)
                        .tag(option)
                }
            }
        } label: {
            Image(systemName: mode.systemImage)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("歌曲排序：\(mode.title)")
    }
}

struct SonaAlphabetIndexBar: View {
    private static let alphabet = ["#"] + (65...90).compactMap {
        UnicodeScalar($0).map(String.init)
    }

    let availableSections: Set<String>
    let onSelect: (String) -> Void
    @State private var activeLetter: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .trailing) {
                if let activeLetter {
                    Text(activeLetter)
                        .font(.title.bold())
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .offset(x: -38)
                }

                VStack(spacing: 0) {
                    ForEach(Self.alphabet, id: \.self) { letter in
                        Text(letter)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(
                                availableSections.contains(letter)
                                    ? Color.sonaGreen : Color.white.opacity(0.24)
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 28)
                .padding(.vertical, 6)
                .background(.black.opacity(0.18), in: Capsule())
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            selectLetter(at: value.location.y, height: proxy.size.height)
                        }
                        .onEnded { value in
                            selectLetter(at: value.location.y, height: proxy.size.height)
                            activeLetter = nil
                        }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .frame(width: 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("字母快速索引")
        .accessibilityValue(activeLetter ?? "")
    }

    private func selectLetter(at y: CGFloat, height: CGFloat) {
        guard height > 0 else { return }
        let itemHeight = height / CGFloat(Self.alphabet.count)
        let index = min(
            Self.alphabet.count - 1,
            max(0, Int(y / max(itemHeight, 1)))
        )
        guard let letter = nearestAvailableLetter(to: index),
              letter != activeLetter else { return }
        activeLetter = letter
        SonaHaptics.selectionChanged()
        onSelect(letter)
    }

    private func nearestAvailableLetter(to index: Int) -> String? {
        Self.alphabet.indices
            .filter { availableSections.contains(Self.alphabet[$0]) }
            .min { abs($0 - index) < abs($1 - index) }
            .map { Self.alphabet[$0] }
    }
}

struct Button<Content: View>: View {
    private let role: ButtonRole?
    private let action: () -> Void
    private let content: Content
    @State private var hapticTrigger = false

    init(
        role: ButtonRole? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Content
    ) {
        self.role = role
        self.action = action
        content = label()
    }

    var body: some View {
        SwiftUI.Button(role: role) {
            hapticTrigger.toggle()
            action()
        } label: {
            content
        }
        .sensoryFeedback(trigger: hapticTrigger) {
            SonaHaptics.buttonFeedback()
        }
    }
}

extension Button where Content == Text {
    init(
        _ titleKey: LocalizedStringKey,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.init(role: role, action: action) {
            Text(titleKey)
        }
    }

    init<S>(
        _ title: S,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) where S: StringProtocol {
        self.init(role: role, action: action) {
            Text(title)
        }
    }
}

extension Button where Content == Label<Text, Image> {
    init(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.init(role: role, action: action) {
            Label(titleKey, systemImage: systemImage)
        }
    }

    init<S>(
        _ title: S,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) where S: StringProtocol {
        self.init(role: role, action: action) {
            Label(title, systemImage: systemImage)
        }
    }
}

struct SonaCollection: Identifiable {
    enum Shape {
        case square
        case circle
    }

    let id: String
    let title: String
    let subtitle: String
    let artworkURL: String?
    let artworkURLs: [String]
    let rotatesArtworkHourly: Bool
    let tracks: [Track]
    let shape: Shape

    init(
        id: String,
        title: String,
        subtitle: String,
        artworkURL: String?,
        artworkURLs: [String] = [],
        rotatesArtworkHourly: Bool = false,
        tracks: [Track],
        shape: Shape
    ) {
        let validArtworkURLs = sonaArtworkPaths(artworkURLs)
        let preferredArtworkURL = sonaArtworkPaths(artworkURL.map { [$0] } ?? []).first
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = preferredArtworkURL
            ?? validArtworkURLs.first
            ?? sonaFirstArtworkURL(in: tracks)
        self.artworkURLs = validArtworkURLs
        self.rotatesArtworkHourly = rotatesArtworkHourly
        self.tracks = tracks
        self.shape = shape
    }
}

func sonaAlbums(from tracks: [Track]) -> [SonaCollection] {
    Dictionary(grouping: tracks) { $0.album }
        .map { album, albumTracks in
            return SonaCollection(
                id: "album-\(album)",
                title: album,
                subtitle: albumTracks.first?.artist ?? "未知艺人",
                artworkURL: sonaFirstArtworkURL(in: albumTracks),
                tracks: albumTracks.sorted {
                    ($0.trackNumber ?? Int.max, $0.title) < ($1.trackNumber ?? Int.max, $1.title)
                },
                shape: .square
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
}

func sonaArtists(from tracks: [Track]) -> [SonaCollection] {
    var displayNames: [String: String] = [:]
    var groupedTracks: [String: [String: Track]] = [:]
    for track in tracks {
        let artist = (track.artists.first ?? track.artist)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !artist.isEmpty else { continue }
        let key = artist.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        if displayNames[key] == nil { displayNames[key] = artist }
        groupedTracks[key, default: [:]][track.id] = track
    }
    return groupedTracks
        .map { key, tracksByID in
            let artist = displayNames[key] ?? "未知艺人"
            let uniqueTracks = tracksByID.values.sorted {
                let leftIsCanonical = $0.artist.trimmingCharacters(in: .whitespacesAndNewlines) == artist
                let rightIsCanonical = $1.artist.trimmingCharacters(in: .whitespacesAndNewlines) == artist
                if leftIsCanonical != rightIsCanonical { return leftIsCanonical }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return SonaCollection(
                id: "artist-\(artist)",
                title: artist,
                subtitle: "艺人",
                artworkURL: sonaFirstArtworkURL(in: uniqueTracks),
                tracks: uniqueTracks,
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
    @EnvironmentObject private var session: SessionStore
    let username: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SonaAvatarView(
                username: username,
                avatarPreset: session.currentUser?.avatarPreset,
                avatarURL: session.currentUser?.avatarURL,
                size: 32
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开账户菜单")
    }
}

struct SonaAvatarView: View {
    let username: String
    var avatarPreset: String?
    var avatarURL: String?
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let avatarURL, avatarPreset == nil {
                ArtworkView(path: avatarURL, cornerRadius: size / 2)
            } else {
                Circle()
                    .fill(avatarGradient)
                    .overlay {
                        if let preset = AvatarPreset(rawValue: avatarPreset ?? "") {
                            Image(preset.assetName)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Text(String(
                                username.trimmingCharacters(in: .whitespaces).first ?? "S"
                            ).uppercased())
                                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                                .foregroundStyle(.black.opacity(0.82))
                        }
                    }
            }
        }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
    }

    private var avatarGradient: LinearGradient {
        let colors: [Color] = switch AvatarPreset(rawValue: avatarPreset ?? "") {
        case .aurora: [.green, .purple]
        case .cosmos: [.indigo, .blue]
        case .forest: [.green, .brown]
        case .ocean: [.cyan, .blue]
        case .sunset: [.orange, .pink]
        case .candy: [.pink, .purple]
        case .ember: [.red, .orange]
        case .midnight: [.black, .indigo]
        case nil: [.sonaGreen.opacity(0.95), Color(red: 0.02, green: 0.28, blue: 0.14)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
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
            .padding(.horizontal, 13)
            .frame(height: 30)
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
    var onColorResolved: ((Color) -> Void)? = nil

    var body: some View {
        Group {
            if collection.rotatesArtworkHourly {
                TimelineView(.periodic(from: .now, by: 60 * 60)) { context in
                    ArtworkView(
                        path: rotatingArtwork(at: context.date),
                        cornerRadius: collection.shape == .circle ? size / 2 : 6,
                        thumbnailSize: requestedThumbnailSize,
                        onColorResolved: onColorResolved
                    )
                }
            } else if collection.artworkURLs.count < 2 {
                ArtworkView(
                    path: collection.artworkURLs.first ?? collection.artworkURL,
                    cornerRadius: collection.shape == .circle ? size / 2 : 6,
                    thumbnailSize: requestedThumbnailSize,
                    onColorResolved: onColorResolved
                )
            } else {
                SonaMosaicArtwork(
                    paths: collection.artworkURLs,
                    thumbnailSize: requestedThumbnailSize / 2,
                    onColorResolved: onColorResolved
                )
            }
        }
            .frame(width: size, height: size)
            .clipShape(collection.shape == .circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
    }

    private func rotatingArtwork(at date: Date) -> String? {
        guard !collection.artworkURLs.isEmpty else {
            return collection.artworkURL
        }
        let hour = UInt64(date.timeIntervalSince1970 / (60 * 60))
        let offset = collection.id.utf8.reduce(UInt64(0)) { $0 &* 31 &+ UInt64($1) }
        let index = Int((hour &+ offset) % UInt64(collection.artworkURLs.count))
        return collection.artworkURLs[index]
    }

    private var requestedThumbnailSize: Int {
        size <= 80 ? 256 : 512
    }
}

struct SonaRadioCover: View {
    let collection: SonaCollection
    let color: Color
    var size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: size * 0.11, weight: .bold))
                Spacer()
                Text("电台")
                    .font(.system(size: size * 0.07, weight: .black))
            }
            .padding(.horizontal, size * 0.06)
            .padding(.top, size * 0.055)

            Spacer(minLength: size * 0.02)
            SonaRadioArtworkCluster(paths: collection.artworkURLs, size: size)
                .frame(height: size * 0.46)
            Spacer(minLength: size * 0.02)

            Text(collection.title)
                .font(.system(size: size * 0.13, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .padding(.horizontal, size * 0.06)
                .padding(.bottom, size * 0.055)
        }
        .foregroundStyle(.black)
        .frame(width: size, height: size)
        .background(color, in: RoundedRectangle(cornerRadius: size * 0.048))
    }
}

private struct SonaRadioArtworkCluster: View {
    let paths: [String]
    let size: CGFloat

    var body: some View {
        HStack(spacing: -size * 0.07) {
            radioArtwork(index: 1, diameter: size * 0.31)
                .zIndex(0)
            radioArtwork(index: 0, diameter: size * 0.50)
                .zIndex(1)
            radioArtwork(index: 2, diameter: size * 0.31)
                .zIndex(0)
        }
        .frame(maxWidth: .infinity)
    }

    private func radioArtwork(index: Int, diameter: CGFloat) -> some View {
        ArtworkView(
            path: index < paths.count ? paths[index] : paths.first,
            cornerRadius: diameter / 2,
            thumbnailSize: 384
        )
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(Circle().stroke(.black.opacity(0.06), lineWidth: 1))
    }
}

private struct SonaMosaicArtwork: View {
    let paths: [String]
    let thumbnailSize: Int
    var onColorResolved: ((Color) -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            let cellSize = proxy.size.width / 2
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(cellSize), spacing: 0), count: 2),
                spacing: 0
            ) {
                ForEach(0..<4, id: \.self) { index in
                    ArtworkView(
                        path: index < paths.count ? paths[index] : nil,
                        cornerRadius: 0,
                        thumbnailSize: thumbnailSize,
                        onColorResolved: index == 0 ? onColorResolved : nil
                    )
                    .frame(width: cellSize, height: cellSize)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct SonaMediaCard: View {
    let collection: SonaCollection
    var width: CGFloat = 168

    private let dailyColors: [Color] = [
        Color(red: 0.13, green: 0.91, blue: 0.91),
        Color(red: 0.91, green: 0.95, blue: 0.18),
        Color(red: 1.00, green: 0.27, blue: 0.16),
        Color(red: 0.96, green: 0.48, blue: 0.74),
        Color(red: 0.35, green: 0.78, blue: 0.58),
        Color(red: 0.62, green: 0.49, blue: 0.95)
    ]

    private var dailyIndex: Int? {
        guard collection.id.hasPrefix("daily-") else { return nil }
        return Int(collection.id.dropFirst("daily-".count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let dailyIndex {
                dailyArtwork(color: dailyColors[dailyIndex % dailyColors.count])
            } else {
                SonaCollectionArtwork(collection: collection, size: width)
                Text(collection.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Text(collection.subtitle)
                .font(.caption)
                .foregroundStyle(Color.sonaSecondaryText)
                .lineLimit(2)
        }
        .frame(width: width, alignment: .leading)
    }

    private func dailyArtwork(color: Color) -> some View {
            SonaCollectionArtwork(collection: collection, size: width)
            .overlay(alignment: .topLeading) {
                Image(systemName: "waveform")
                    .font(.caption.bold())
                    .foregroundStyle(Color.sonaBackground)
                    .frame(width: 26, height: 26)
                    .background(color, in: Circle())
                    .padding(8)
            }
            .overlay(alignment: .bottom) {
                Text(collection.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.sonaBackground)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(color.opacity(0.94))
                    .padding(6)
            }
    }
}

struct SonaMacHoverMediaCard<Content: View>: View {
    var artworkSize: CGFloat = 168
    let playAction: () -> Void
    private let content: Content
    @State private var isHovered = false

    init(
        artworkSize: CGFloat = 168,
        playAction: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.artworkSize = artworkSize
        self.playAction = playAction
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        #if targetEnvironment(macCatalyst)
        ZStack(alignment: .topLeading) {
            content
                .padding(10)
                .background(
                    isHovered ? Color.white.opacity(0.09) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )

            if isHovered {
                Button(action: playAction) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 48, height: 48)
                        .background(Color.sonaGreen, in: Circle())
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("播放")
                .offset(x: artworkSize - 46, y: artworkSize - 46)
                .transition(.scale(scale: 0.88).combined(with: .opacity))
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovered)
        #else
        content
        #endif
    }
}

struct SonaMacHoverShortcutCard<Content: View>: View {
    let playAction: () -> Void
    private let content: Content
    @State private var isHovered = false

    init(playAction: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.playAction = playAction
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        #if targetEnvironment(macCatalyst)
        ZStack(alignment: .trailing) {
            cardContent

            if isHovered {
                Button(action: playAction) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 34, height: 34)
                        .background(Color.sonaGreen, in: Circle())
                        .shadow(color: .black.opacity(0.32), radius: 5, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("播放")
                .padding(.trailing, 8)
                .transition(.scale(scale: 0.88).combined(with: .opacity))
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovered)
        #else
        cardContent
        #endif
    }

    private var cardContent: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.sonaSurface.opacity(0.95))
                    .overlay {
                        if isHovered {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.09))
                        }
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct SonaTrackListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var personal: PersonalStore
    @AppStorage("miniPlayerMode") private var miniPlayerMode = "floating"
    @State private var isSelecting = false
    @State private var selectedIDs = Set<String>()
    @State private var showsImporter = false
    @State private var showsServerDirectoryPicker = false
    @State private var importMessage: String?
    @State private var isImportingServerDirectory = false
    @State private var importProgressMessage = ""
    @State private var loadedPlaylistTracks: [String: Track] = [:]
    @State private var isLoadingPlaylistTracks = false
    @State private var editedTracks: [String: Track] = [:]
    @State private var editingTrack: Track?
    @State private var madeForYouHeaderColor = Color(red: 0.24, green: 0.12, blue: 0.18)
    @State private var playlistHeaderColor = Color(red: 0.08, green: 0.22, blue: 0.16)
    @State private var showsArtworkPicker = false
    @State private var showsArtworkMenu = false
    @State private var artworkPhotoItem: PhotosPickerItem?
    @State private var trackSortMode = SonaTrackSortMode.original
    @State private var alphabeticalSections: [SonaAlphabeticalTrackSection] = []
    @State private var isPreparingAlphabeticalSort = false
    let collection: SonaCollection
    let playbackQueue: [Track]?
    let dailyRecommendationQueues: [[Track]]?
    let loadsMoreFromLibrary: Bool
    let radioColor: Color?

    init(
        collection: SonaCollection,
        playbackQueue: [Track]? = nil,
        dailyRecommendationQueues: [[Track]]? = nil,
        loadsMoreFromLibrary: Bool = false,
        radioColor: Color? = nil
    ) {
        self.collection = collection
        self.playbackQueue = playbackQueue
        self.dailyRecommendationQueues = dailyRecommendationQueues
        self.loadsMoreFromLibrary = loadsMoreFromLibrary
        self.radioColor = radioColor
    }

    private var playlist: Playlist? {
        guard collection.id.hasPrefix("playlist-") else { return nil }
        let id = String(collection.id.dropFirst("playlist-".count))
        return personal.playlists.first { $0.id == id }
    }

    private var displayedCollection: SonaCollection {
        guard let playlist else { return collection }
        return SonaCollection(
            id: collection.id,
            title: collection.title,
            subtitle: collection.subtitle,
            artworkURL: sonaArtworkPaths(playlist.artworkURLs).first
                ?? sonaFirstArtworkURL(in: tracks),
            artworkURLs: playlist.artworkURLs,
            rotatesArtworkHourly: playlist.artworkTrackID == nil,
            tracks: tracks,
            shape: collection.shape
        )
    }

    private var tracks: [Track] {
        let values: [Track]
        if collection.id == "liked-songs" {
            if !personal.favoriteTracks.isEmpty || personal.favoriteIDs.isEmpty {
                values = personal.favoriteTracks
            } else {
                values = library.tracks.filter { personal.favoriteIDs.contains($0.id) }
            }
        } else if let playlist {
            values = playlist.trackIDs.compactMap {
                library.track(id: $0) ?? loadedPlaylistTracks[$0]
            }
        } else {
            values = loadsMoreFromLibrary ? library.tracks : collection.tracks
        }
        return values
            .map { editedTracks[$0.id] ?? $0 }
            .filter { !personal.hiddenTrackIDs.contains($0.id) }
    }

    private var trackCount: Int {
        if collection.id == "liked-songs" { return personal.favoriteIDs.count }
        return playlist?.trackIDs.count ?? tracks.count
    }

    private var displayedTracks: [Track] {
        guard trackSortMode == .alphabetical else { return tracks }
        return alphabeticalSections.flatMap(\.tracks)
    }

    private var trackSortSignature: Int {
        sonaTrackSortSignature(tracks)
    }

    private var playlistBottomContentMargin: CGFloat {
#if targetEnvironment(macCatalyst)
        24
#else
        miniPlayerMode == "fixed" ? 96 : 24
#endif
    }

    private var queue: [Track] {
        if prioritizedQueueTitle != nil {
            return displayedTracks
        }
        guard let playbackQueue, !playbackQueue.isEmpty else { return displayedTracks }
        return playbackQueue
    }

    private var prioritizedQueueTitle: String? {
        let isPlaylist = collection.id == "liked-songs" ||
            collection.id.hasPrefix("playlist-") ||
            collection.subtitle.hasPrefix("歌单")
        guard collection.id == "daily-recommendations" ||
            isPlaylist || collection.id.hasPrefix("album-") else { return nil }
        return collection.title
    }

    private var queueContextID: String? {
        prioritizedQueueTitle == nil ? nil : collection.id
    }

    private var showsShuffleButton: Bool {
        collection.id == "daily-recommendations" ||
            collection.id == "liked-songs" ||
            collection.id.hasPrefix("playlist-") ||
            collection.subtitle.hasPrefix("歌单")
    }

    private var isRadio: Bool {
        collection.id.hasPrefix("radio-")
    }

    private var isMadeForYou: Bool {
        collection.id.hasPrefix("made-for-you-")
    }

    private var dailyRecommendationIndex: Int? {
        guard collection.id.hasPrefix("daily-") else { return nil }
        return Int(collection.id.dropFirst("daily-".count))
    }

    private var dailyRecommendationColor: Color {
        let colors: [Color] = [
            Color(red: 0.13, green: 0.91, blue: 0.91),
            Color(red: 0.91, green: 0.95, blue: 0.18),
            Color(red: 1.00, green: 0.27, blue: 0.16),
            Color(red: 0.96, green: 0.48, blue: 0.74),
            Color(red: 0.35, green: 0.78, blue: 0.58),
            Color(red: 0.62, green: 0.49, blue: 0.95)
        ]
        guard let dailyRecommendationIndex else { return Color.sonaSurface }
        return colors[dailyRecommendationIndex % colors.count]
    }

    private var detailHeaderColor: Color {
        if isRadio { return radioColor ?? Color.sonaSurface }
        if isMadeForYou { return madeForYouHeaderColor }
        if dailyRecommendationIndex != nil { return dailyRecommendationColor }
        if playlist != nil { return playlistHeaderColor }
        return Color.sonaSurface
    }

    private var detailPageGradientTopOpacity: Double {
        #if targetEnvironment(macCatalyst)
        dailyRecommendationIndex != nil ? 0.40 : 0.78
        #else
        dailyRecommendationIndex != nil ? 0.58 : 0.98
        #endif
    }

    private var detailNavigationBarColor: Color {
        detailBackgroundColor(opacity: detailPageGradientTopOpacity)
    }

    private func detailBackgroundColor(opacity: Double) -> Color {
        #if targetEnvironment(macCatalyst)
        sonaOpaqueBlend(detailHeaderColor, opacity: opacity)
        #else
        detailHeaderColor.opacity(opacity)
        #endif
    }

    private var detailNavigationBarBackgroundVisibility: Visibility {
        #if targetEnvironment(macCatalyst)
        .visible
        #else
        .hidden
        #endif
    }

    private var detailNavigationBarVisibility: Visibility {
        #if targetEnvironment(macCatalyst)
        .hidden
        #else
        .visible
        #endif
    }

    private var detailScrollTopPadding: CGFloat {
        #if targetEnvironment(macCatalyst)
        72
        #else
        0
        #endif
    }

    private var radioCoverSize: CGFloat {
        #if targetEnvironment(macCatalyst)
        260
        #else
        280
        #endif
    }

    @ViewBuilder
    private var detailArtwork: some View {
        if isRadio {
            SonaRadioCover(
                collection: displayedCollection,
                color: radioColor ?? Color.sonaGreen,
                size: radioCoverSize
            )
        } else if isMadeForYou {
            madeForYouCover
        } else if dailyRecommendationIndex != nil {
            dailyRecommendationCover
        } else {
            SonaCollectionArtwork(
                collection: displayedCollection,
                size: 230,
                onColorResolved: playlist == nil ? nil : { playlistHeaderColor = $0 }
            )
        }
    }

    private var dailyRecommendationCover: some View {
        SonaCollectionArtwork(collection: displayedCollection, size: 280)
            .overlay(alignment: .topLeading) {
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(dailyRecommendationColor, in: Circle())
                    .padding(12)
            }
            .overlay(alignment: .bottom) {
                Text(collection.title)
                    .font(.system(size: 25, weight: .black))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(dailyRecommendationColor.opacity(0.96))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var madeForYouCover: some View {
        ArtworkView(
            path: displayedCollection.artworkURL,
            cornerRadius: 6,
            thumbnailSize: 768,
            onColorResolved: { madeForYouHeaderColor = $0 }
        )
        .frame(width: 280, height: 280)
        .overlay(alignment: .topLeading) {
            Image(systemName: "waveform")
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.black)
                .frame(width: 36, height: 36)
                .background(Color.sonaGreen, in: Circle())
                .padding(12)
        }
        .overlay(alignment: .bottom) {
            Text(collection.title)
                .font(.system(size: 25, weight: .black))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.sonaGreen.opacity(0.96))
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    var body: some View {
        ZStack {
            Color.sonaBackground
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    detailBackgroundColor(opacity: detailPageGradientTopOpacity),
                    detailBackgroundColor(
                        opacity: isMadeForYou ? 0.72 : dailyRecommendationIndex != nil ? 0.34 : 0.45
                    ),
                    .sonaBackground,
                    .sonaBackground
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            ScrollViewReader { proxy in
                ZStack(alignment: .trailing) {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                    VStack(spacing: 18) {
                        detailArtwork
                            .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
                        VStack(spacing: 5) {
                            if !isRadio && !isMadeForYou && dailyRecommendationIndex == nil {
                                Text(collection.title)
                                    .font(.title2.bold())
                                    .multilineTextAlignment(.center)
                            }
                            Text(collection.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(Color.sonaSecondaryText)
                        }
                        HStack {
                            Text("\(trackCount) 首歌曲")
                                .font(.caption)
                                .foregroundStyle(Color.sonaSecondaryText)
                            SonaTrackSortMenu(mode: $trackSortMode)
                            if canEditPlaylistArtwork {
                                playlistArtworkMenu
                            }
                            Spacer()
                            if showsShuffleButton {
                                Button {
                                    playRandom()
                                } label: {
                                    Image(systemName: "shuffle")
                                        .font(.title3.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 48, height: 48)
                                        .background(.white.opacity(0.1), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("随机播放")
                                .disabled(
                                    tracks.isEmpty ||
                                    (collection.id == "liked-songs" && personal.isLoadingMoreFavorites)
                                )
                            }
                            Button {
                                if collection.id == "liked-songs" {
                                    Task {
                                        let allTracks = await personal.loadAllFavoriteTracks()
                                        playCollection(
                                            orderedForCurrentSort(allTracks),
                                            shuffled: false
                                        )
                                    }
                                } else {
                                    playCollection(displayedTracks, shuffled: false)
                                }
                            } label: {
                                if collection.id == "liked-songs" {
                                    if personal.isLoadingMoreFavorites {
                                        ProgressView()
                                            .tint(.black)
                                            .frame(width: 48, height: 48)
                                            .background(Color.sonaGreen, in: Circle())
                                    } else {
                                        Label("播放全部", systemImage: "play.fill")
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.black)
                                            .padding(.horizontal, 18)
                                            .frame(height: 48)
                                            .background(Color.sonaGreen, in: Capsule())
                                    }
                                } else {
                                    Image(systemName: "play.fill")
                                        .font(.title2)
                                        .foregroundStyle(.black)
                                        .frame(width: 56, height: 56)
                                        .background(Color.sonaGreen, in: Circle())
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(
                                tracks.isEmpty ||
                                (collection.id == "liked-songs" && personal.isLoadingMoreFavorites)
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)

                    if isLoadingPlaylistTracks && tracks.isEmpty {
                        ProgressView("正在载入歌单…")
                            .padding(.vertical, 18)
                    }

                        if trackSortMode == .alphabetical {
                            ForEach(alphabeticalSections) { section in
                                alphabeticalSectionHeader(section.id)
                                    .id(alphabeticalAnchor(section.id))
                                ForEach(section.tracks) { track in
                                    trackRow(track)
                                }
                            }
                        } else {
                            ForEach(tracks) { track in
                                trackRow(track)
                            }
                        }

                        if isPreparingAlphabeticalSort {
                            ProgressView("正在准备字母索引…")
                                .padding(.vertical, 18)
                        } else if collection.id == "liked-songs" && personal.isLoadingMoreFavorites {
                            ProgressView("载入更多…")
                                .padding(.vertical, 18)
                        } else if loadsMoreFromLibrary && library.isLoadingMore {
                            ProgressView("载入更多…")
                                .padding(.vertical, 18)
                        }
                        }
                    }
                    .scrollIndicators(trackSortMode == .alphabetical ? .hidden : .automatic)
                    .contentMargins(
                        .bottom,
                        playlistBottomContentMargin,
                        for: .scrollContent
                    )
                    .safeAreaPadding(.top, detailScrollTopPadding)

                    if trackSortMode == .alphabetical, !alphabeticalSections.isEmpty {
                        SonaAlphabetIndexBar(
                            availableSections: Set(alphabeticalSections.map(\.id))
                        ) { section in
                            proxy.scrollTo(alphabeticalAnchor(section), anchor: .top)
                        }
                        .padding(.top, 88)
                        .padding(.bottom, playlistBottomContentMargin)
                    }
                }
            }

            #if targetEnvironment(macCatalyst)
            macDetailToolbar
            #endif

            if isImportingServerDirectory {
                DirectoryImportProgressOverlay(message: importProgressMessage)
            }
        }
        .overlay {
            if showsArtworkMenu {
                ZStack {
                    Color.black.opacity(0.24)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { showsArtworkMenu = false }
                    PlaylistArtworkPopup(
                        hasSourceArtwork: playlist?.sourceArtworkURL != nil,
                        hasManualArtwork: playlist?.artworkTrackID != nil,
                        upload: {
                            showsArtworkMenu = false
                            showsArtworkPicker = true
                        },
                        useSourceArtwork: {
                            showsArtworkMenu = false
                            guard let playlist else { return }
                            Task {
                                await personal.useSourcePlaylistArtwork(playlistID: playlist.id)
                            }
                        },
                        clearManualArtwork: {
                            showsArtworkMenu = false
                            guard let playlist else { return }
                            Task {
                                await personal.clearPlaylistArtwork(playlistID: playlist.id)
                            }
                        }
                    )
                    .padding(24)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: showsArtworkMenu)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(detailNavigationBarVisibility, for: .navigationBar)
        .toolbar {
            Button(
                tracks.allSatisfy { offline.downloadedIDs.contains($0.id) }
                    ? "已全部离线" : "全部离线",
                systemImage: "arrow.down.circle"
            ) {
                Task {
                    let values = collection.id == "liked-songs"
                        ? await personal.loadAllFavoriteTracks() : tracks
                    await offline.downloadAll(values)
                }
            }
            .disabled(tracks.isEmpty || tracks.contains { offline.activeDownloads.contains($0.id) })
            if collection.id == "liked-songs" {
                if session.currentUser?.isAdmin == true {
                    Menu("导入", systemImage: "square.and.arrow.down") {
                        Button("扫描服务器音乐目录", systemImage: "externaldrive") {
                            showsServerDirectoryPicker = true
                        }
                        Button("从 App 本地导入", systemImage: "iphone") {
                            showsImporter = true
                        }
                    }
                }
                Button(isSelecting ? "完成" : "多选") {
                    isSelecting.toggle()
                    if !isSelecting { selectedIDs.removeAll() }
                }
                if isSelecting, !selectedIDs.isEmpty {
                    Button("移除 \(selectedIDs.count) 首", role: .destructive) {
                        let ids = selectedIDs
                        Task {
                            await personal.removeFavorites(trackIDs: ids)
                            selectedIDs.removeAll()
                            isSelecting = false
                        }
                    }
                }
            }
        }
        .toolbarBackground(detailNavigationBarColor, for: .navigationBar)
        .toolbarBackground(detailNavigationBarBackgroundVisibility, for: .navigationBar)
        .photosPicker(
            isPresented: $showsArtworkPicker,
            selection: $artworkPhotoItem,
            matching: .images
        )
        .onChange(of: artworkPhotoItem) { _, item in
            guard let item else { return }
            Task { await uploadPlaylistArtwork(from: item) }
        }
        .task(id: playlist?.trackIDs) {
            await loadMissingPlaylistTracks()
        }
        .onChange(of: trackSortMode) { _, mode in
            guard mode == .alphabetical else { return }
            Task { await prepareAlphabeticalSort() }
        }
        .onChange(of: trackSortSignature) { _, _ in
            guard trackSortMode == .alphabetical,
                  !isPreparingAlphabeticalSort else { return }
            alphabeticalSections = sonaAlphabeticalTrackSections(tracks)
        }
        .sheet(item: $editingTrack) { track in
            TrackIdentityEditorView(track: track) { updated in
                editedTracks[updated.id] = updated
                library.applyTrackUpdate(updated)
                personal.applyTrackUpdate(updated)
                if loadedPlaylistTracks[updated.id] != nil {
                    loadedPlaylistTracks[updated.id] = updated
                }
            }
            .desktopSheetSize(.standard)
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            Task { await importLocalFiles(result) }
        }
        .sheet(isPresented: $showsServerDirectoryPicker) {
            ServerDirectoryPicker { directory in
                Task { await importServerDirectory(directory) }
            }
            .desktopSheetSize(.large)
        }
        .alert("导入结果", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("好") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    private func alphabeticalAnchor(_ section: String) -> String {
        "track-section-\(section)"
    }

    private func alphabeticalSectionHeader(_ section: String) -> some View {
        Text(section)
            .font(.headline.bold())
            .foregroundStyle(Color.sonaGreen)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    private func trackRow(_ track: Track) -> some View {
        HStack {
            if isSelecting {
                Image(systemName: selectedIDs.contains(track.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(Color.sonaGreen)
            }
            TrackRow(
                track: track,
                showsOfflineBadge: offline.downloadedIDs.contains(track.id),
                isFavorite: personal.favoriteIDs.contains(track.id),
                moreActionTitle: playlistArtworkActionTitle(for: track),
                moreActionSystemImage: playlist?.artworkTrackID == track.id
                    ? "checkmark.circle.fill" : "photo",
                moreActionDisabled: playlist?.artworkTrackID == track.id,
                moreAction: playlistArtworkAction(for: track),
                deleteTitle: canRemoveTracksFromPlaylist ? "从歌单中移除" : nil,
                deleteAction: removeFromPlaylistAction(for: track),
                tapAction: {
                    if isSelecting {
                        if !selectedIDs.insert(track.id).inserted {
                            selectedIDs.remove(track.id)
                        }
                    } else {
                        play(track)
                    }
                }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contextMenu {
            if session.currentUser?.isAdmin == true {
                Button("编辑歌曲名和歌手", systemImage: "pencil") {
                    editingTrack = track
                }
            }
            Button("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") {
                player.playNext(track)
            }
            Button("添加到播放队列", systemImage: "text.badge.plus") {
                player.addToQueue(track)
            }
        }
        .task {
            guard trackSortMode == .original else { return }
            if collection.id == "liked-songs" {
                await personal.loadNextFavoritePageIfNeeded(currentTrack: track)
            } else if loadsMoreFromLibrary {
                await library.loadNextPageIfNeeded(currentTrack: track)
            }
        }
    }

    private func prepareAlphabeticalSort() async {
        isPreparingAlphabeticalSort = true
        defer { isPreparingAlphabeticalSort = false }

        if collection.id == "liked-songs" {
            let values = await personal.loadAllFavoriteTracks()
            alphabeticalSections = sonaAlphabeticalTrackSections(
                values
                    .map { editedTracks[$0.id] ?? $0 }
                    .filter { !personal.hiddenTrackIDs.contains($0.id) }
            )
            return
        }
        if playlist != nil {
            await loadMissingPlaylistTracks()
        } else if loadsMoreFromLibrary {
            alphabeticalSections = await library.prepareAlphabeticalIndex()
            return
        }
        alphabeticalSections = sonaAlphabeticalTrackSections(tracks)
    }

    private func orderedForCurrentSort(_ values: [Track]) -> [Track] {
        guard trackSortMode == .alphabetical else { return values }
        return sonaAlphabeticalTrackSections(values).flatMap(\.tracks)
    }

    #if targetEnvironment(macCatalyst)
    private var macDetailToolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    macToolbarIcon("chevron.left")
                }
                .accessibilityLabel("返回")

                Spacer()

                Button {
                    Task {
                        let values = collection.id == "liked-songs"
                            ? await personal.loadAllFavoriteTracks() : tracks
                        await offline.downloadAll(values)
                    }
                } label: {
                    macToolbarIcon("arrow.down.circle")
                }
                .accessibilityLabel("全部离线")
                .disabled(
                    tracks.isEmpty || tracks.contains { offline.activeDownloads.contains($0.id) }
                )

                if collection.id == "liked-songs" {
                    if session.currentUser?.isAdmin == true {
                        Menu {
                            Button("扫描服务器音乐目录", systemImage: "externaldrive") {
                                showsServerDirectoryPicker = true
                            }
                            Button("从 App 本地导入", systemImage: "iphone") {
                                showsImporter = true
                            }
                        } label: {
                            macToolbarIcon("square.and.arrow.down")
                        }
                        .accessibilityLabel("导入")
                    }
                    Button {
                        isSelecting.toggle()
                        if !isSelecting { selectedIDs.removeAll() }
                    } label: {
                        macToolbarIcon(isSelecting ? "checkmark" : "checklist")
                    }
                    .accessibilityLabel(isSelecting ? "完成" : "多选")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Spacer()
        }
    }

    private func macToolbarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.title3.bold())
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.black.opacity(0.18), in: Circle())
    }
    #endif

    private func loadMissingPlaylistTracks() async {
        guard let playlist else { return }
        isLoadingPlaylistTracks = true
        defer { isLoadingPlaylistTracks = false }
        let missingIDs = playlist.trackIDs.filter {
            library.track(id: $0) == nil && loadedPlaylistTracks[$0] == nil
        }
        guard !missingIDs.isEmpty, !Task.isCancelled,
              let loaded = try? await APIClient.shared.tracks(ids: missingIDs) else { return }
        var updated = loadedPlaylistTracks
        loaded.forEach { updated[$0.id] = $0 }
        loadedPlaylistTracks = updated
    }

    private func playlistArtworkActionTitle(for track: Track) -> String? {
        guard canEditPlaylistArtwork,
              track.artworkURL != nil else { return nil }
        return playlist?.artworkTrackID == track.id ? "当前歌单封面" : "用此歌曲图片作为封面"
    }

    private func playlistArtworkAction(for track: Track) -> (() -> Void)? {
        guard canEditPlaylistArtwork,
              let playlist,
              track.artworkURL != nil else { return nil }
        return {
            guard playlist.artworkTrackID != track.id else { return }
            Task {
                await personal.setPlaylistArtwork(
                    playlistID: playlist.id,
                    trackID: track.id
                )
            }
        }
    }

    private var canRemoveTracksFromPlaylist: Bool {
        playlist?.isDirectoryPlaylist == false
    }

    private func removeFromPlaylistAction(for track: Track) -> (() -> Void)? {
        guard let playlist, !playlist.isDirectoryPlaylist else { return nil }
        return {
            Task {
                await personal.setTrack(
                    track.id,
                    in: playlist.id,
                    isIncluded: false
                )
            }
        }
    }

    private var canEditPlaylistArtwork: Bool {
        guard let playlist else { return false }
        return session.currentUser?.isAdmin == true ||
            (!playlist.featured && !playlist.isDirectoryPlaylist)
    }

    private var playlistArtworkMenu: some View {
        Button {
            showsArtworkMenu = true
        } label: {
            Image(systemName: "photo")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("设置歌单封面")
    }

    private func uploadPlaylistArtwork(from item: PhotosPickerItem) async {
        defer { artworkPhotoItem = nil }
        guard let playlist,
              let data = try? await item.loadTransferable(type: Data.self),
              let jpeg = playlistArtworkJPEGData(data) else { return }
        await personal.uploadPlaylistArtwork(playlistID: playlist.id, imageData: jpeg)
    }

    private func playlistArtworkJPEGData(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, 1600 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let normalized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return normalized.jpegData(compressionQuality: 0.86)
    }

    private func play(_ track: Track) {
        if let dailyRecommendationQueues,
           let queueIndex = Int(collection.id.dropFirst("daily-".count)) {
            player.playDailyRecommendations(
                track: track,
                queues: dailyRecommendationQueues,
                queueIndex: queueIndex,
                offlineURLProvider: offline.localURL(for:)
            )
            return
        }
        player.play(
            track: track,
            queue: queue,
            prioritizedQueueTitle: prioritizedQueueTitle,
            queueContextID: queueContextID,
            offlineURLProvider: offline.localURL(for:)
        )
    }

    private func playRandom() {
        if collection.id == "liked-songs" {
            Task {
                playCollection(await personal.loadAllFavoriteTracks(), shuffled: true)
            }
        } else {
            playCollection(tracks, shuffled: true)
        }
    }

    private func playCollection(_ values: [Track], shuffled: Bool) {
        let queue = shuffled ? values.shuffled() : values
        guard let first = queue.first else { return }
        if !shuffled,
           let dailyRecommendationQueues,
           let queueIndex = Int(collection.id.dropFirst("daily-".count)) {
            player.playDailyRecommendations(
                track: first,
                queues: dailyRecommendationQueues,
                queueIndex: queueIndex,
                offlineURLProvider: offline.localURL(for:)
            )
            return
        }
        player.play(
            track: first, queue: queue,
            prioritizedQueueTitle: collection.title,
            queueContextID: collection.id,
            offlineURLProvider: offline.localURL(for:)
        )
    }

    private func importServerDirectory(_ directory: ServerMusicDirectory) async {
        isImportingServerDirectory = true
        importProgressMessage = "正在加入已入库歌曲…"
        defer { isImportingServerDirectory = false }
        do {
            let result = try await APIClient.shared.importFavorites(directory: directory.path)
            await personal.refresh()
            importMessage = result.scanning == true
                ? "“\(directory.name)”已快速加入收藏 \(result.importedCount) 首，后台正在补入新歌曲"
                : "“\(directory.name)”已加入收藏 \(result.importedCount) 首"
        } catch {
            importMessage = error.localizedDescription
        }
    }

    private func importLocalFiles(_ result: Result<[URL], Error>) async {
        do {
            let urls = try result.get()
            let record = try? await APIClient.shared.createImportRecord(
                type: .localFiles,
                source: "\(urls.count) 个本地文件",
                target: "正常歌曲池",
                total: urls.count
            )
            let upload = await APIClient.shared.uploadTracks(urls: urls)
            guard upload.succeeded > 0 else {
                if let record {
                    let _ = try? await APIClient.shared.updateImportRecord(
                        id: record.id,
                        update: ImportRecordUpdate(
                            state: .failed,
                            succeeded: 0,
                            failed: upload.failed,
                            message: upload.message ?? "文件上传失败"
                        )
                    )
                }
                importMessage = upload.message ?? "文件上传失败"
                return
            }
            if let record {
                let _ = try? await APIClient.shared.updateImportRecord(
                    id: record.id,
                    update: ImportRecordUpdate(
                        state: .running,
                        succeeded: upload.succeeded,
                        failed: upload.failed,
                        message: "正在扫描曲库…"
                    )
                )
            }
            await library.scan()
            if let errorMessage = library.errorMessage {
                if let record {
                    let _ = try? await APIClient.shared.updateImportRecord(
                        id: record.id,
                        update: scanRecordUpdate(
                            state: .failed,
                            status: library.scanStatus,
                            succeeded: upload.succeeded,
                            failed: upload.failed + max(library.scanStatus?.failed ?? 0, 1),
                            message: errorMessage
                        )
                    )
                }
                importMessage = errorMessage
                return
            }
            if let record {
                let _ = try? await APIClient.shared.updateImportRecord(
                    id: record.id,
                    update: scanRecordUpdate(
                        state: .completed,
                        status: library.scanStatus,
                        succeeded: upload.succeeded,
                        failed: upload.failed,
                        message: upload.failed > 0 ? "部分文件上传失败" : "已完成"
                    )
                )
            }
            await personal.refresh()
            importMessage = upload.failed == 0
                ? "已导入 \(upload.succeeded) 首到正常歌曲池"
                : "已导入 \(upload.succeeded) 首，失败 \(upload.failed) 首"
        } catch {
            importMessage = error.localizedDescription
        }
    }
}

func sonaOpaqueBlend(_ foreground: Color, opacity: Double) -> Color {
    let foregroundColor = UIColor(foreground)
    let backgroundColor = UIColor(Color.sonaBackground)
    var foregroundRed: CGFloat = 0
    var foregroundGreen: CGFloat = 0
    var foregroundBlue: CGFloat = 0
    var foregroundAlpha: CGFloat = 0
    var backgroundRed: CGFloat = 0
    var backgroundGreen: CGFloat = 0
    var backgroundBlue: CGFloat = 0
    var backgroundAlpha: CGFloat = 0
    guard foregroundColor.getRed(
        &foregroundRed,
        green: &foregroundGreen,
        blue: &foregroundBlue,
        alpha: &foregroundAlpha
    ), backgroundColor.getRed(
        &backgroundRed,
        green: &backgroundGreen,
        blue: &backgroundBlue,
        alpha: &backgroundAlpha
    ) else {
        return foreground.opacity(opacity)
    }
    let amount = CGFloat(opacity)
    return Color(
        red: Double(foregroundRed * amount + backgroundRed * (1 - amount)),
        green: Double(foregroundGreen * amount + backgroundGreen * (1 - amount)),
        blue: Double(foregroundBlue * amount + backgroundBlue * (1 - amount))
    )
}

struct DirectoryImportProgressOverlay: View {
    let message: String

    var body: some View {
        Color.black.opacity(0.45)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Color.sonaGreen)
                    Text(message)
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.center)
                    Text("目录较大时可能需要几分钟")
                        .font(.caption)
                        .foregroundStyle(Color.sonaSecondaryText)
                }
                .padding(24)
                .frame(maxWidth: 260)
                .background(Color.sonaSurface, in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("服务器目录导入中，\(message)")
    }
}
