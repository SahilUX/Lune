import SwiftUI
import AppKit

struct FullPlayerView: View {
    @Binding var isShowing: Bool
    @Environment(PlayerEngine.self) private var player

    @State private var showControls = true
    @State private var showLyrics = false
    @State private var useRecord = false
    @State private var hideTask: DispatchWorkItem?

    private var song: Song? { player.currentSong }
    private var lyrics: LyricsData? { player.currentLyrics }

    var body: some View {
        ZStack(alignment: .center) {
            // Solid black — no tint, no translucency
            Color.black.ignoresSafeArea()

            // Center art + optional lyrics, sized from the window so a big display is actually used.
            GeometryReader { geo in
                let size = geo.size
                let artSide = min(size.height * 0.58, size.width * (showLyrics ? 0.36 : 0.5), 900)
                let gap = max(40, size.width * 0.04)
                let lyricsWidth = min(size.width * 0.42, 820)
                let lyricsSize = max(20, min(size.height / 24, 44))

                HStack(spacing: gap) {
                    Group {
                        if useRecord {
                            RecordView(coverArtId: song?.coverArtId, isPlaying: player.isPlaying, size: artSide)
                        } else {
                            AsyncArtwork(coverArtId: song?.coverArtId, size: 1000, cornerRadius: artSide * 0.06)
                                .frame(width: artSide, height: artSide)
                                .shadow(color: .black.opacity(0.8), radius: 40, y: 20)
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: useRecord)

                    if showLyrics {
                        Group {
                            if let lyrics, !lyrics.isEmpty {
                                LyricsPanelView(lyrics: lyrics, baseSize: lyricsSize)
                            } else {
                                VStack(spacing: 12) {
                                    Spacer()
                                    Image(systemName: "text.bubble").font(.largeTitle).foregroundStyle(.tertiary)
                                    Text(lyrics == nil ? "Loading…" : "No lyrics available")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                            }
                        }
                        // The stage is always on black, whatever the system appearance is.
                        .environment(\.colorScheme, .dark)
                        .frame(width: lyricsWidth, height: size.height * 0.66)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.35), value: showLyrics)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Controls overlay — always fills the full frame so Spacer() works
            if showControls {
                VStack(spacing: 0) {
                    // ── Top bar ──────────────────────────────────────────
                    HStack(alignment: .center) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { isShowing = false }
                        } label: {
                            Image(systemName: "chevron.down.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        HStack(spacing: 14) {
                            Toggle(isOn: $showLyrics.animation(.spring(duration: 0.35))) {
                                Label(showLyrics ? "Hide Lyrics" : "Lyrics",
                                      systemImage: showLyrics ? "text.bubble.fill" : "text.bubble")
                            }
                            .toggleStyle(.button)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(showLyrics ? .accentColor : nil)

                            Toggle(isOn: $useRecord.animation(.easeInOut(duration: 0.3))) {
                                Label(useRecord ? "Album Art" : "Vinyl",
                                      systemImage: useRecord ? "square.fill" : "record.circle")
                            }
                            .toggleStyle(.button)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .colorScheme(.dark)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 24)

                    Spacer()

                    // ── Bottom controls ───────────────────────────────────
                    VStack(spacing: 14) {
                        VStack(spacing: 3) {
                            Text(song?.title ?? "Not Playing")
                                .font(.title2.bold()).foregroundStyle(.white)
                                .lineLimit(1)
                            Text(song?.artist ?? "")
                                .font(.title3).foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }

                        SeekBar()
                            .frame(maxWidth: 900)
                            .colorScheme(.dark)

                        HStack(spacing: 44) {
                            FullPlayerShuffleButton()
                            FullPlayerSkipBackButton()
                            FullPlayerPlayPauseButton()
                            FullPlayerSkipForwardButton()
                            FullPlayerRepeatButton()
                        }

                        VolumeSlider().frame(maxWidth: 220).colorScheme(.dark)
                    }
                    .padding(.bottom, 48)
                    .padding(.horizontal, 60)
                    .background(
                        LinearGradient(colors: [.clear, .black.opacity(0.85)],
                                       startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                    )
                    .ignoresSafeArea(edges: .bottom)
                }
                // *** This is the key fix: controls VStack must fill the whole frame ***
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        // Lives outside `if showControls`, so Esc still closes the player once the controls hide.
        .background {
            Button("Close Full Player") {
                withAnimation(.easeInOut(duration: 0.25)) { isShowing = false }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
            .accessibilityHidden(true)
        }
        // contentShape ensures hover events hit the full black background
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            guard case .active = phase else { return }
            revealControls()
        }
        .onAppear { scheduleHide() }
        .onDisappear {
            hideTask?.cancel()
            NSCursor.unhide()
        }
        .animation(.easeInOut(duration: 0.3), value: showControls)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func revealControls() {
        if !showControls {
            withAnimation(.easeIn(duration: 0.15)) { showControls = true }
        }
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        let item = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.4)) { showControls = false }
            NSCursor.setHiddenUntilMouseMoves(true)
        }
        hideTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }
}

// MARK: - Shared lyrics panel

/// Reads the playback position itself, so the views that show it don't re-render
/// every half second just to move the highlight.
struct LyricsPanelView: View {
    let lyrics: LyricsData
    /// Text size of a normal line; the current line is drawn larger.
    var baseSize: CGFloat = 15
    @Environment(PlayerEngine.self) private var player

    /// Index of the line being sung: the last line that has started. Lines are in time order.
    private var currentIndex: Int? {
        guard lyrics.isSynced else { return nil }
        let ms = Int(player.currentTime * 1000)
        var low = 0, high = lyrics.lines.count
        while low < high {
            let mid = (low + high) / 2
            if lyrics.lines[mid].startMs <= ms { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }

    var body: some View {
        let current = currentIndex
        let currentID = current.map { lyrics.lines[$0].id }

        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: baseSize * 1.3) {
                    ForEach(lyrics.lines) { line in
                        if !line.text.isEmpty {
                            LyricRow(text: line.text, isCurrent: line.id == currentID, baseSize: baseSize)
                                .id(line.id)
                        }
                    }
                }
                .padding(.vertical, 60)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                // Opening the panel mid-song should land on the current line, not the top.
                if let currentID { proxy.scrollTo(currentID, anchor: .center) }
            }
            .onChange(of: current) { _, idx in
                guard let idx, idx < lyrics.lines.count else { return }
                withAnimation(.easeInOut(duration: 0.5)) {
                    proxy.scrollTo(lyrics.lines[idx].id, anchor: .center)
                }
            }
        }
    }
}

private struct LyricRow: View {
    let text: String
    let isCurrent: Bool
    let baseSize: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: isCurrent ? baseSize * 1.35 : baseSize, weight: isCurrent ? .bold : .regular))
            .foregroundStyle(isCurrent ? Color.primary : Color.secondary.opacity(0.5))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            // Only the rows that actually change animate.
            .animation(.easeInOut(duration: 0.3), value: isCurrent)
    }
}

// MARK: - Full Player Button Variants (white, larger for full-screen mode)

struct FullPlayerShuffleButton: View {
    @Environment(PlayerEngine.self) private var player

    var body: some View {
        Button {
            player.isShuffling.toggle()
            if player.isShuffling { player.shuffle() }
        } label: {
            Image(systemName: "shuffle")
                .font(.title3)
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

struct FullPlayerSkipBackButton: View {
    @Environment(PlayerEngine.self) private var player

    var body: some View {
        Button { player.skipBackward() } label: {
            Image(systemName: "backward.fill")
                .font(.title2)
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

struct FullPlayerPlayPauseButton: View {
    @Environment(PlayerEngine.self) private var player
    @Environment(LibraryStore.self) private var library

    var body: some View {
        Button {
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
                .font(.system(size: 58))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

struct FullPlayerSkipForwardButton: View {
    @Environment(PlayerEngine.self) private var player

    var body: some View {
        Button { player.skipForward() } label: {
            Image(systemName: "forward.fill")
                .font(.title2)
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

struct FullPlayerRepeatButton: View {
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
                .font(.title3)
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
