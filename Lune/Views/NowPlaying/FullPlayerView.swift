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

            // Center art + optional lyrics
            VStack(spacing: 0) {
                Spacer()

                HStack(spacing: 60) {
                    Group {
                        if useRecord {
                            RecordView(coverArtId: song?.coverArtId, isPlaying: player.isPlaying, size: 340)
                        } else {
                            AsyncArtwork(coverArtId: song?.coverArtId, size: 800, cornerRadius: 20)
                                .frame(width: 340, height: 340)
                                .shadow(color: .black.opacity(0.8), radius: 40, y: 20)
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: useRecord)

                    if showLyrics {
                        Group {
                            if let lyrics, !lyrics.isEmpty {
                                LyricsPanelView(lyrics: lyrics, currentTime: player.currentTime)
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
                        .frame(minWidth: 260, maxWidth: 320, maxHeight: .infinity)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.35), value: showLyrics)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                        .keyboardShortcut(.escape, modifiers: [])

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
                            .frame(maxWidth: 560)
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

struct LyricsPanelView: View {
    let lyrics: LyricsData
    let currentTime: Double

    private var currentIndex: Int? {
        guard lyrics.isSynced else { return nil }
        let ms = Int(currentTime * 1000)
        var idx: Int? = nil
        for (i, line) in lyrics.lines.enumerated() {
            if line.startMs <= ms { idx = i } else { break }
        }
        return idx
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 20) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                        if !line.text.isEmpty {
                            Text(line.text)
                                .font(index == currentIndex ? .title3.bold() : .body)
                                .foregroundStyle(index == currentIndex
                                    ? Color.primary
                                    : Color.secondary.opacity(0.5))
                                .multilineTextAlignment(.center)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .animation(.easeInOut(duration: 0.3), value: currentIndex)
                                .id(line.id)
                        }
                    }
                }
                .padding(.vertical, 60)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: currentIndex) { _, idx in
                guard let idx, idx < lyrics.lines.count else { return }
                withAnimation(.easeInOut(duration: 0.5)) {
                    proxy.scrollTo(lyrics.lines[idx].id, anchor: .center)
                }
            }
        }
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
