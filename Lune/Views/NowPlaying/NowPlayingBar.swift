import SwiftUI

struct NowPlayingBar: View {
    @Binding var showNowPlaying: Bool
    @Environment(PlayerEngine.self) private var player
    @Environment(LibraryStore.self) private var library
    @State private var showQueue = false

    private var lyricsSnippet: String? {
        player.currentLyrics?.snippet(at: player.currentTime)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Left: artwork + track info
            HStack(spacing: 10) {
                AsyncArtwork(coverArtId: player.currentSong?.coverArtId, size: 80, cornerRadius: 8)
                    .frame(width: 44, height: 44)
                    .shadow(radius: 4)
                    .onTapGesture {
                        guard player.currentSong != nil else { return }
                        withAnimation(.spring(duration: 0.35)) { showNowPlaying = true }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentSong?.title ?? "Not Playing")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let snippet = lyricsSnippet {
                        Text(snippet)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor.opacity(0.8))
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .transition(.opacity)
                    } else {
                        Text(player.currentSong?.artist ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: lyricsSnippet)
                .frame(width: 120, alignment: .leading)
            }

            Divider()

            // Center: controls + seek
            VStack(spacing: 4) {
                HStack(spacing: 12) {
                    ShuffleButton().font(.caption)
                    SkipBackButton().font(.caption)
                    PlayPauseButton().font(.system(size: 32))
                    SkipForwardButton().font(.caption)
                    RepeatButton().font(.caption)
                }

                SeekBar().frame(maxWidth: 280)
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Right: volume + heart + queue + pip + expanded
            HStack(spacing: 8) {
                VolumeSlider().frame(width: 150)

                if let song = player.currentSong {
                    HeartButton(song: song)
                }

                Button { showQueue.toggle() } label: {
                    Image(systemName: "list.bullet")
                }
                .buttonStyle(.plain)
                .foregroundStyle(showQueue ? Color.accentColor : Color.primary)
                .keyboardShortcut("u", modifiers: .command)

                Button {
                    let hidesMain = UserDefaults.standard.bool(forKey: "pipHidesMainWindow")
                    PiPWindowController.shared.open(hidingMainWindow: hidesMain)
                } label: {
                    Image(systemName: "pip.enter")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .help("Picture in Picture")

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showNowPlaying = true }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .help("Expanded Player")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: 80)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showQueue) { QueueView() }
    }
}

// MARK: - Shared controls

struct SeekBar: View {
    @Environment(PlayerEngine.self) private var player
    @State private var isDragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        // Sample AVPlayer every frame while playing so the thumb glides instead of
        // jumping on the engine's 0.5s time-observer ticks.
        TimelineView(.animation(paused: !player.isPlaying || isDragging)) { _ in
            let position = isDragging ? dragValue : player.livePosition()
            HStack(spacing: 8) {
                Text(format(position))
                    .font(.caption2).foregroundStyle(.secondary)
                    .monospacedDigit().frame(width: 36, alignment: .trailing)

                // One binding for the whole gesture. Swapping bindings when the drag
                // starts (or re-creating one every TimelineView frame) makes the slider
                // lose the drag, so the thumb snaps back to the playback position.
                Slider(
                    value: Binding(
                        get: { isDragging ? dragValue : position },
                        set: { newValue in
                            dragValue = newValue
                            // A change outside a drag (keyboard, accessibility) seeks right away.
                            if !isDragging { player.seek(to: newValue) }
                        }
                    ),
                    in: 0...(max(player.duration, 1))
                ) { editing in
                    if editing { dragValue = player.livePosition() }
                    isDragging = editing
                    if !editing { player.seek(to: dragValue) }
                }

                Text(format(player.duration))
                    .font(.caption2).foregroundStyle(.secondary)
                    .monospacedDigit().frame(width: 36, alignment: .leading)
            }
        }
    }

    private func format(_ t: Double) -> String {
        guard t.isFinite else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct VolumeSlider: View {
    @Environment(PlayerEngine.self) private var player
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "speaker.fill").font(.caption2).foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { Double(player.volume) },
                set: { player.volume = Float($0) }
            ), in: 0...1)
            Image(systemName: "speaker.wave.3.fill").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct ShuffleButton: View {
    @Environment(PlayerEngine.self) private var player

    var body: some View {
        Button {
            player.isShuffling.toggle()
            if player.isShuffling { player.shuffle() }
        } label: {
            Image(systemName: "shuffle")
        }
        .buttonStyle(.plain)
        .foregroundStyle(player.isShuffling ? Color.accentColor : Color.secondary)
    }
}

struct RepeatButton: View {
    @Environment(PlayerEngine.self) private var player

    var body: some View {
        Button {
            player.repeatMode = switch player.repeatMode {
            case .none: .all
            case .all: .one
            case .one: .none
            }
        } label: {
            Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
        }
        .buttonStyle(.plain)
        .foregroundStyle(player.repeatMode == .none ? Color.secondary : Color.accentColor)
    }
}

struct SkipBackButton: View {
    @Environment(PlayerEngine.self) private var player

    var body: some View {
        Button { player.skipBackward() } label: {
            Image(systemName: "backward.fill")
        }
        .buttonStyle(.plain)
        .font(.title3)
        .disabled(player.currentSong == nil)
    }
}

struct PlayPauseButton: View {
    @Environment(PlayerEngine.self) private var player
    @Environment(LibraryStore.self) private var library
    @State private var scale: CGFloat = 1

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { scale = 0.9 }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.65).delay(0.08)) { scale = 1 }

            if player.currentSong == nil {
                var songs = library.songs
                guard !songs.isEmpty else { return }
                songs.shuffle()
                player.play(songs: songs, startingAt: 0)
            } else {
                player.togglePlayPause()
            }
        } label: {
            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 32))
                .scaleEffect(scale)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(" ", modifiers: [])
    }
}

struct SkipForwardButton: View {
    @Environment(PlayerEngine.self) private var player

    var body: some View {
        Button { player.skipForward() } label: {
            Image(systemName: "forward.fill")
        }
        .buttonStyle(.plain)
        .font(.title3)
        .disabled(player.currentSong == nil)
    }
}
