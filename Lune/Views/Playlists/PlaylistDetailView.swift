import SwiftUI

struct PlaylistListView: View {
    @Environment(LibraryStore.self) private var library
    @State private var isCreating = false
    @State private var newName = ""

    var body: some View {
        List {
            if library.playlists.isEmpty && library.isLoading {
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonPlaylistRow()
                }
            } else {
                ForEach(library.playlists) { playlist in
                    NavigationLink(value: playlist) {
                        HStack(spacing: 10) {
                            if let coverArtId = playlist.coverArtId {
                                AsyncArtwork(coverArtId: coverArtId, size: 80, cornerRadius: 6)
                                    .frame(width: 36, height: 36)
                            } else {
                                CompositePlaylistArt(songs: playlist.songs)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name)
                                Text("\(playlist.songCount) songs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .id(playlist.id)
                    }
                }
                .onDelete { offsets in
                    Task {
                        for i in offsets {
                            try? await SubsonicClient.shared.deletePlaylist(id: library.playlists[i].id)
                        }
                        await library.refreshPlaylists()
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Playlists")
        .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlistId: $0.id) }
        .toolbar {
            ToolbarItem {
                Button { newName = ""; isCreating = true } label: { Image(systemName: "plus") }
                    .help("New Playlist")
            }
        }
        .alert("New Playlist", isPresented: $isCreating) {
            TextField("Name", text: $newName)
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task {
                    try? await SubsonicClient.shared.createPlaylist(name: name)
                    await library.refreshPlaylists()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct PlaylistDetailView: View {
    let playlistId: String
    @Environment(PlayerEngine.self) private var player
    @State private var playlist: Playlist?
    @State private var loadFailed = false
    @State private var sortOrder: SongSortOrder? = nil  // nil = server order

    private var displaySongs: [Song] {
        guard let playlist else { return [] }
        guard let sort = sortOrder else { return playlist.songs }
        switch sort {
        case .title:    return playlist.songs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist:   return playlist.songs.sorted { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .album:    return playlist.songs.sorted { $0.album.localizedCaseInsensitiveCompare($1.album) == .orderedAscending }
        case .duration: return playlist.songs.sorted { $0.duration < $1.duration }
        }
    }

    var body: some View {
        Group {
            if let playlist {
                HStack(alignment: .top, spacing: 0) {
                    // Left: playlist info
                    VStack(alignment: .leading, spacing: 16) {
                        if let coverArtId = playlist.coverArtId {
                            AsyncArtwork(coverArtId: coverArtId, size: 600, cornerRadius: 12)
                                .frame(width: 240, height: 240)
                                .shadow(radius: 16)
                        } else {
                            CompositePlaylistArt(songs: playlist.songs)
                                .frame(width: 240, height: 240)
                                .shadow(radius: 16)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(playlist.name)
                                .font(.title2.weight(.bold))
                            Text("\(playlist.songCount) songs")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 12) {
                            Button {
                                player.play(songs: displaySongs, startingAt: 0)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                player.enqueue(songs: displaySongs)
                            } label: {
                                Label("Add to Queue", systemImage: "text.badge.plus")
                            }
                            .buttonStyle(.bordered)
                        }

                        Spacer()
                    }
                    .padding(24)
                    .frame(width: 290)

                    Divider()

                    // Right: track list
                    List {
                        // Keyed by position: a playlist may contain the same song more than once.
                        let songs = displaySongs
                        ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                            SongRow(song: song, showAlbum: true, collection: songs)
                        }
                    }
                    .listStyle(.plain)
                }
                .navigationTitle(playlist.name)
            } else if loadFailed {
                ContentUnavailableView {
                    Label("Couldn't load playlist", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Check your connection to the server.")
                } actions: {
                    Button("Try Again") { loadFailed = false }
                }
            } else {
                List {
                    ForEach(0..<10, id: \.self) { _ in
                        SkeletonSongRow()
                    }
                }
                .listStyle(.plain)
                .navigationTitle("Loading...")
            }
        }
        .task(id: "\(playlistId)-\(loadFailed)") {
            guard !loadFailed else { return }
            do {
                playlist = try await SubsonicClient.shared.getPlaylist(id: playlistId)
            } catch {
                if !Task.isCancelled { loadFailed = true }
            }
        }
    }
}
