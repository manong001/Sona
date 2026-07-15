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
            return SonaCollection(
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
    var displayNames: [String: String] = [:]
    var groupedTracks: [String: [String: Track]] = [:]
    for track in tracks {
        let rawArtist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = rawArtist.contains("林俊杰") ? "林俊杰" : rawArtist
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
                artworkURL: uniqueTracks.first(where: { $0.artworkURL != nil })?.artworkURL,
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
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var personal: PersonalStore
    @State private var isSelecting = false
    @State private var selectedIDs = Set<String>()
    @State private var showsImporter = false
    @State private var showsServerDirectoryPicker = false
    @State private var importMessage: String?
    @State private var isImportingServerDirectory = false
    @State private var importProgressMessage = ""
    let collection: SonaCollection
    let playbackQueue: [Track]?
    let loadsMoreFromLibrary: Bool

    init(
        collection: SonaCollection,
        playbackQueue: [Track]? = nil,
        loadsMoreFromLibrary: Bool = false
    ) {
        self.collection = collection
        self.playbackQueue = playbackQueue
        self.loadsMoreFromLibrary = loadsMoreFromLibrary
    }

    private var tracks: [Track] {
        if collection.id == "liked-songs" {
            if !personal.favoriteTracks.isEmpty || personal.favoriteIDs.isEmpty {
                return personal.favoriteTracks
            }
            return library.tracks.filter { personal.favoriteIDs.contains($0.id) }
        }
        return loadsMoreFromLibrary ? library.tracks : collection.tracks
    }

    private var queue: [Track] {
        if collection.id == "liked-songs" {
            return tracks
        }
        guard let playbackQueue, !playbackQueue.isEmpty else { return tracks }
        return playbackQueue
    }

    private var prioritizedQueueTitle: String? {
        let isPlaylist = collection.id == "liked-songs" ||
            collection.id.hasPrefix("playlist-") ||
            collection.subtitle.hasPrefix("歌单")
        guard isPlaylist || collection.id.hasPrefix("album-") else { return nil }
        return collection.title
    }

    private var queueContextID: String? {
        prioritizedQueueTitle == nil ? nil : collection.id
    }

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
                            Text("\(collection.id == "liked-songs" ? personal.favoriteIDs.count : tracks.count) 首歌曲")
                                .font(.caption)
                                .foregroundStyle(Color.sonaSecondaryText)
                            Spacer()
                            Button {
                                if collection.id == "liked-songs" {
                                    Task {
                                        let allTracks = await personal.loadAllFavoriteTracks()
                                        guard let first = allTracks.first else { return }
                                        player.play(
                                            track: first,
                                            queue: allTracks,
                                            prioritizedQueueTitle: prioritizedQueueTitle,
                                            queueContextID: queueContextID,
                                            offlineURLProvider: offline.localURL(for:)
                                        )
                                    }
                                } else {
                                    guard let first = tracks.first else { return }
                                    player.play(
                                        track: first,
                                        queue: queue,
                                        prioritizedQueueTitle: prioritizedQueueTitle,
                                        queueContextID: queueContextID,
                                        offlineURLProvider: offline.localURL(for:)
                                    )
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
                            .disabled(
                                tracks.isEmpty ||
                                (collection.id == "liked-songs" && personal.isLoadingMoreFavorites)
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)

                    ForEach(tracks) { track in
                        Button {
                            if isSelecting {
                                if !selectedIDs.insert(track.id).inserted { selectedIDs.remove(track.id) }
                                return
                            }
                            player.play(
                                track: track,
                                queue: queue,
                                prioritizedQueueTitle: prioritizedQueueTitle,
                                queueContextID: queueContextID,
                                offlineURLProvider: offline.localURL(for:)
                            )
                        } label: {
                            HStack {
                                if isSelecting {
                                    Image(systemName: selectedIDs.contains(track.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(Color.sonaGreen)
                                }
                                TrackRow(
                                    track: track,
                                    showsOfflineBadge: offline.downloadedIDs.contains(track.id),
                                    isFavorite: personal.favoriteIDs.contains(track.id)
                                )
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") {
                                player.playNext(track)
                            }
                            Button("添加到播放队列", systemImage: "text.badge.plus") {
                                player.addToQueue(track)
                            }
                        }
                        .task {
                            if collection.id == "liked-songs" {
                                await personal.loadNextFavoritePageIfNeeded(currentTrack: track)
                            } else if loadsMoreFromLibrary {
                                await library.loadNextPageIfNeeded(currentTrack: track)
                            }
                        }
                    }

                    if collection.id == "liked-songs" && personal.isLoadingMoreFavorites {
                        ProgressView("载入更多…")
                            .padding(.vertical, 18)
                    } else if loadsMoreFromLibrary && library.isLoadingMore {
                        ProgressView("载入更多…")
                            .padding(.vertical, 18)
                    }
                }
                .padding(.bottom, 24)
            }

            if isImportingServerDirectory {
                DirectoryImportProgressOverlay(message: importProgressMessage)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
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
        .toolbarBackground(.hidden, for: .navigationBar)
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
