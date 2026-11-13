import SwiftUI

struct QueueView: View {
    @Environment(PlayerEngine.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.offset) { index, song in
                    HStack(spacing: 10) {
                        // Playing indicator or index
                        Group {
                            if index == player.currentIndex {
                                Image(systemName: "waveform")
                                    .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                                    .foregroundStyle(Color.accentColor)
                            } else {
                                Text("\(index + 1)")
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                            }
                        }
                        .frame(width: 20, alignment: .trailing)

                        AsyncArtwork(coverArtId: song.coverArtId, size: 60, cornerRadius: 4)
                            .frame(width: 36, height: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.subheadline)
                                .foregroundStyle(index == player.currentIndex ? Color.accentColor : Color.primary)
                                .lineLimit(1)
                            Text(song.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(song.formattedDuration)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()

                        // Drag handle
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                            .frame(width: 20)
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Play Now") { player.play(songs: player.queue, startingAt: index) }
                        Button("Remove from Queue", role: .destructive) {
                            player.remove(at: IndexSet(integer: index))
                        }
                    }
                    .onTapGesture(count: 1) {
                        player.play(songs: player.queue, startingAt: index)
                    }
                }
                .onMove { player.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { player.remove(at: $0) }
            }
            .listStyle(.plain)
            .navigationTitle("Queue (\(player.queue.count))")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem {
                    Button(role: .destructive) { player.clearQueue() } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(player.queue.isEmpty)
                }
            }
        }
        .frame(width: 420, height: 600)
    }
}
