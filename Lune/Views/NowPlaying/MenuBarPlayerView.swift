import SwiftUI

struct MenuBarPlayerView: View {
    @Environment(PlayerEngine.self) private var player

    var body: some View {
        VStack(spacing: 0) {
            // Artwork + info
            HStack(spacing: 12) {
                AsyncArtwork(coverArtId: player.currentSong?.coverArtId, size: 120, cornerRadius: 8)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentSong?.title ?? "Not Playing")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(player.currentSong?.artist ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding()

            Divider()

            // Seek
            SeekBar()
                .padding(.horizontal)
                .padding(.top, 8)

            // Controls
            HStack(spacing: 24) {
                Button { player.skipBackward() } label: { Image(systemName: "backward.fill") }
                    .buttonStyle(.plain)
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                Button { player.skipForward() } label: { Image(systemName: "forward.fill") }
                    .buttonStyle(.plain)
            }
            .padding()
        }
        .frame(width: 280)
    }
}
