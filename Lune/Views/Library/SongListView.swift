import SwiftUI

struct SongListView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerEngine.self) private var player
    @State private var searchText = ""
    @State private var sortOrder = SongSortOrder.title
    @State private var selectedIds: Set<String> = []

    /// The filtered, sorted list. Computed when its inputs change, not on every render:
    /// sorting a big library on each body evaluation made the view stall.
    @State private var songs: [Song] = []

    private struct Inputs: Equatable {
        var count: Int
        var firstID: String?
        var lastID: String?
        var search: String
        var sort: SongSortOrder
    }

    private var inputs: Inputs {
        Inputs(count: library.songs.count, firstID: library.songs.first?.id, lastID: library.songs.last?.id,
               search: searchText, sort: sortOrder)
    }

    private func recompute() {
        var result = library.songs
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.artist.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sortOrder {
        case .title:    songs = result.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist:   songs = result.sorted { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .album:    songs = result.sorted { $0.album.localizedCaseInsensitiveCompare($1.album) == .orderedAscending }
        case .duration: songs = result.sorted { $0.duration < $1.duration }
        }
    }

    var body: some View {
        List {
            if songs.isEmpty && library.isLoading {
                ForEach(0..<10, id: \.self) { _ in
                    SkeletonSongRow()
                }
            } else {
                ForEach(songs) { song in
                    SongRow(song: song, showAlbum: true, collection: songs)
                }
            }
        }
        .listStyle(.plain)
        .task(id: inputs) {
            // Let typing settle before re-filtering a large library.
            if !searchText.isEmpty { try? await Task.sleep(for: .milliseconds(150)) }
            guard !Task.isCancelled else { return }
            recompute()
        }
        .navigationTitle("Songs")
        .searchable(text: $searchText, prompt: "Search songs")
        .toolbar {
            ToolbarItem {
                Button { player.play(songs: songs, startingAt: 0) } label: {
                    Label("Play All", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            ToolbarItem { SongSortMenu(sortOrder: $sortOrder) }
        }
    }
}

struct SongRow: View {
    let song: Song
    var showAlbum: Bool = true
    /// The list this row is shown in, in display order. Tapping the row plays it from here,
    /// so the queue is the album/playlist on screen rather than just this one song.
    var collection: [Song]? = nil
    @Environment(PlayerEngine.self) private var player
    @Environment(LibraryStore.self) private var library

    var isPlaying: Bool { player.currentSongID == song.id }

    var body: some View {
        HStack(spacing: 10) {
            // Album art thumbnail
            AsyncArtwork(coverArtId: song.coverArtId, size: 80, cornerRadius: 4)
                .frame(width: 40, height: 40)
                .shadow(radius: 2)

            Group {
                if isPlaying {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text(song.trackNumber.map(String.init) ?? "·")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 20, alignment: .trailing)
            .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body)
                    .foregroundStyle(isPlaying ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                if showAlbum {
                    Text("\(song.artist) — \(song.album)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(song.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(song.formattedDuration)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)

            Button(action: { player.enqueue(songs: [song]) }) {
                Image(systemName: "text.badge.plus")
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add to Queue")

            HeartButton(song: song)

            if !library.playlists.isEmpty {
                Menu {
                    ForEach(library.playlists) { playlist in
                        Button(playlist.name) {
                            Task {
                                try? await SubsonicClient.shared.updatePlaylist(id: playlist.id, songIdsToAdd: [song.id])
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.body)
                        .foregroundStyle(.primary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if let collection, let index = collection.firstIndex(where: { $0.id == song.id }) {
                player.play(songs: collection, startingAt: index)
            } else {
                player.play(song: song)
            }
        }
    }
}
