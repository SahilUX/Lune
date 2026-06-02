import SwiftUI

struct SearchView: View {
    @Environment(PlayerEngine.self) private var player
    @State private var query = ""
    @State private var result: SearchResult?
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            VStack {
                if query.isEmpty {
                    ContentUnavailableView("Search Your Library", systemImage: "magnifyingglass",
                                          description: Text("Type to search artists, albums, and songs."))
                } else if isSearching {
                    ProgressView().frame(width: 24, height: 24)
                } else if let result {
                    List {
                        if !result.artists.isEmpty {
                            Section("Artists") {
                                ForEach(result.artists) { artist in
                                    NavigationLink(value: artist) {
                                        HStack {
                                            AsyncArtwork(coverArtId: artist.coverArtId, size: 80, cornerRadius: 16)
                                                .frame(width: 36, height: 36)
                                            Text(artist.name)
                                        }
                                    }
                                }
                            }
                        }
                        if !result.albums.isEmpty {
                            Section("Albums") {
                                ForEach(result.albums) { album in
                                    NavigationLink(value: album) {
                                        HStack {
                                            AsyncArtwork(coverArtId: album.coverArtId, size: 80, cornerRadius: 6)
                                                .frame(width: 36, height: 36)
                                            VStack(alignment: .leading) {
                                                Text(album.name)
                                                Text(album.artist).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if !result.songs.isEmpty {
                            Section("Songs") {
                                ForEach(result.songs) { song in
                                    SongRow(song: song, showAlbum: true)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, placement: .toolbar, prompt: "Artists, albums, songs")
            .navigationDestination(for: Artist.self) { ArtistDetailView(artist: $0) }
            .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
        }
        .onChange(of: query) { _, new in
            guard !new.isEmpty else { result = nil; return }
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard query == new else { return }
                isSearching = true
                result = try? await SubsonicClient.shared.search(query: new)
                isSearching = false
            }
        }
    }
}
