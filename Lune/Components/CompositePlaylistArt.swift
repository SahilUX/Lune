import SwiftUI

struct CompositePlaylistArt: View {
    let songs: [Song]
    let size: CGFloat = 36

    var body: some View {
        if songs.count >= 4 {
            GridArt(songs: Array(songs.prefix(4)), size: size)
        } else if songs.count >= 2 {
            GridArt(songs: songs + Array(repeating: songs[0], count: 4 - songs.count), size: size)
        } else if let firstSong = songs.first {
            AsyncArtwork(coverArtId: firstSong.coverArtId, size: Int(size * 2), cornerRadius: 4)
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .overlay { Image(systemName: "music.note").foregroundStyle(.tertiary) }
                .frame(width: size, height: size)
        }
    }
}

struct GridArt: View {
    let songs: [Song]
    let size: CGFloat

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 1) {
                if songs.count > 0 {
                    AsyncArtwork(coverArtId: songs[0].coverArtId, size: Int(size), cornerRadius: 2)
                        .frame(width: size / 2, height: size / 2)
                }
                if songs.count > 1 {
                    AsyncArtwork(coverArtId: songs[1].coverArtId, size: Int(size), cornerRadius: 2)
                        .frame(width: size / 2, height: size / 2)
                }
            }
            HStack(spacing: 1) {
                if songs.count > 2 {
                    AsyncArtwork(coverArtId: songs[2].coverArtId, size: Int(size), cornerRadius: 2)
                        .frame(width: size / 2, height: size / 2)
                }
                if songs.count > 3 {
                    AsyncArtwork(coverArtId: songs[3].coverArtId, size: Int(size), cornerRadius: 2)
                        .frame(width: size / 2, height: size / 2)
                }
            }
        }
        .frame(width: size, height: size)
        .cornerRadius(4)
        .clipped()
    }
}
