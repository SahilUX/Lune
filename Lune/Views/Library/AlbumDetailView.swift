import SwiftUI

struct AlbumDetailView: View {
    let album: Album
    @Environment(PlayerEngine.self) private var player
    @State private var loadedAlbum: Album?
    @State private var isLoading = true

    private var displayAlbum: Album { loadedAlbum ?? album }
    /// Disc/track order. Display, Play and Add to Queue all use this, so they agree.
    private var sortedSongs: [Song] { displayAlbum.songs.sorted(by: trackOrder) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left: album info
            VStack(alignment: .leading, spacing: 16) {
                AsyncArtwork(coverArtId: displayAlbum.coverArtId, size: 600, cornerRadius: 12)
                    .frame(width: 240, height: 240)
                    .shadow(radius: 16)

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayAlbum.name)
                        .font(.title2.weight(.bold))
                    Text(displayAlbum.artist)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    if let year = displayAlbum.year {
                        Text(String(year))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        player.play(songs: sortedSongs, startingAt: 0)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        player.enqueue(songs: sortedSongs)
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
                ForEach(sortedSongs) { song in
                    SongRow(song: song, showAlbum: false, collection: sortedSongs)
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle(displayAlbum.name)
        .task {
            if let loaded = try? await SubsonicClient.shared.getAlbum(id: album.id) {
                loadedAlbum = loaded
            }
            isLoading = false
        }
    }

    private func trackOrder(_ a: Song, _ b: Song) -> Bool {
        let discA = a.discNumber ?? 1
        let discB = b.discNumber ?? 1
        if discA != discB { return discA < discB }
        return (a.trackNumber ?? 0) < (b.trackNumber ?? 0)
    }
}
