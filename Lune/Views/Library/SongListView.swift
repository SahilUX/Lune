import SwiftUI

struct SongListView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerEngine.self) private var player
    @State private var searchText = ""
    @State private var sortOrder = SongSortOrder.title
    @State private var selectedIds: Set<String> = []

    private var songs: [Song] {
        var result = library.songs
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.artist.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sortOrder {
        case .title:    return result.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist:   return result.sorted { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .album:    return result.sorted { $0.album.localizedCaseInsensitiveCompare($1.album) == .orderedAscending }
        case .duration: return result.sorted { $0.duration < $1.duration }
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
                    SongRow(song: song, showAlbum: true)
                }
            }
        }
        .listStyle(.plain)
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
    @Environment(PlayerEngine.self) private var player
    @Environment(LibraryStore.self) private var library

    var isPlaying: Bool { player.currentSong?.id == song.id }

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
            player.play(song: song)
        }
    }
}
