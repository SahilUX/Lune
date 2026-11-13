import SwiftUI
import AppKit

struct NowPlayingView: View {
    @Binding var isShowing: Bool
    var openFullPlayer: () -> Void = {}
    @Environment(PlayerEngine.self) private var player

    @State private var showLyrics = false
    @State private var useRecord = false

    private var song: Song? { player.currentSong }
    private var lyrics: LyricsData? { player.currentLyrics }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

            BlurredBackdrop(coverArtId: song?.coverArtId).ignoresSafeArea()

            VStack(spacing: 0) {
                // Top: Artwork + optional lyrics panel (expands)
                VStack {
                    Spacer()

                    HStack(spacing: 0) {
                        if !showLyrics { Spacer() }

                        // Artwork (centered if no lyrics, left half if lyrics shown)
                        Group {
                            if useRecord {
                                RecordView(coverArtId: song?.coverArtId, isPlaying: player.isPlaying, size: 260)
                            } else {
                                AsyncArtwork(coverArtId: song?.coverArtId, size: 800, cornerRadius: 18)
                                    .frame(width: 260, height: 260)
                                    .shadow(color: .black.opacity(0.4), radius: 30, y: 15)
                            }
                        }
                        .animation(.easeInOut(duration: 0.3), value: useRecord)
                        .frame(maxWidth: showLyrics ? .infinity : nil)

                        if showLyrics {
                            // Right: Lyrics (takes right half)
                            Group {
                                if let lyrics, !lyrics.isEmpty {
                                    LyricsPanelView(lyrics: lyrics)
                                } else {
                                    VStack(spacing: 12) {
                                        Spacer()
                                        Image(systemName: "text.bubble").font(.largeTitle).foregroundStyle(.tertiary)
                                        Text("No lyrics")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        } else {
                            Spacer()
                        }
                    }
                    .padding(40)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: 400)

                // Bottom: Song info + controls
                VStack(alignment: .center, spacing: 16) {
                VStack(alignment: .center, spacing: 8) {
                    Text(song?.title ?? "Not Playing")
                        .font(.title2.bold()).lineLimit(2)
                    Text(song?.artist ?? "").font(.title3).foregroundStyle(.secondary)
                }

                if let song { AudioFormatBadge(song: song) }

                SeekBar().frame(maxWidth: .infinity)

                // Controls in one row: Exit | Shuffle | Back | Play | Forward | Repeat | Vinyl | Lyrics | Volume | PiP | FullPlayer
                HStack(spacing: 20) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { isShowing = false }
                    } label: {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("Close (Esc)")

                    ShuffleButton().font(.title3)
                    Button { player.skipBackward() } label: {
                        Image(systemName: "backward.fill").font(.title2)
                    }.buttonStyle(.plain)
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 48))
                    }.buttonStyle(.plain)
                    Button { player.skipForward() } label: {
                        Image(systemName: "forward.fill").font(.title2)
                    }.buttonStyle(.plain)
                    RepeatButton().font(.title3)

                    Divider().frame(height: 28)

                    Picker("", selection: Binding(
                        get: { useRecord ? 1 : 0 },
                        set: { useRecord = $0 == 1 }
                    )) {
                        Image(systemName: "square.fill").tag(0)
                        Image(systemName: "record.circle").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .labelsHidden()

                    Toggle(isOn: $showLyrics.animation(.spring(duration: 0.35))) {
                        Image(systemName: showLyrics ? "text.bubble.fill" : "text.bubble")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .tint(showLyrics ? .accentColor : nil)
                    .help(showLyrics ? "Hide Lyrics" : "Show Lyrics")

                    VolumeSlider().frame(maxWidth: 150)

                    Button {
                        let hidesMain = UserDefaults.standard.bool(forKey: "pipHidesMainWindow")
                        PiPWindowController.shared.open(hidingMainWindow: hidesMain)
                    } label: {
                        Image(systemName: "pip.enter")
                    }
                    .buttonStyle(.bordered)
                    .help("Picture in Picture")

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { openFullPlayer() }
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.bordered)
                    .help("Full Player")
                }
                .padding(.horizontal, 16)
                }
                .padding(.vertical, 40)
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Soft artwork glow behind the player. The blur is applied to a tiny image that is then
/// scaled up, instead of blurring a window-sized layer every frame (that cost a lot of GPU).
struct BlurredBackdrop: View {
    let coverArtId: String?
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .blur(radius: 5)
                        .drawingGroup()
                        .scaleEffect(max(geo.size.width, geo.size.height) / 64 * 1.2)
                } else {
                    Color.clear
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .opacity(0.3)
            .clipped()
        }
        .task(id: coverArtId) {
            guard let id = coverArtId else { image = nil; return }
            image = await ImageCache.shared.image(for: id, size: 64)
        }
    }
}

struct AudioFormatBadge: View {
    let song: Song

    private var originalFormat: String { (song.suffix ?? "?").uppercased() }
    private var streamFormat: String { (song.transcodedSuffix ?? song.suffix ?? "?").uppercased() }
    private var isTranscoded: Bool { song.transcodedSuffix != nil && song.transcodedSuffix != song.suffix }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(originalFormat).fontWeight(.semibold)
                if isTranscoded {
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                    Text(streamFormat).fontWeight(.semibold)
                }
            }
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.quaternary, in: Capsule())

            if let br = song.bitRate {
                Text("\(br) kbps")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }

            if let bytes = song.size {
                Text(String(format: "%.1f MB", Double(bytes) / 1_048_576))
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}

// MARK: - Picture-in-Picture Window

import AppKit

@MainActor
final class PiPWindowController {
    static let shared = PiPWindowController()

    private var panel: NSPanel?
    private var hostingController: NSViewController?
    /// Set only when this controller hid the main window, so closing restores just that.
    private var hidMainWindow = false

    func open(hidingMainWindow: Bool) {
        if let existingPanel = panel {
            existingPanel.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 300, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = PiPContentView(onClose: { [weak self] in
            self?.close()
        })

        let hostingController = NSHostingController(rootView: content.environment(PlayerEngine.shared))
        panel.contentView = hostingController.view

        panel.orderFrontRegardless()

        self.panel = panel
        self.hostingController = hostingController

        if hidingMainWindow, let main = MainWindow.shared.window {
            main.orderOut(nil)
            hidMainWindow = true
        }
    }

    func close() {
        panel?.close()
        panel = nil
        hostingController = nil

        if hidMainWindow {
            hidMainWindow = false
            MainWindow.shared.window?.makeKeyAndOrderFront(nil)
        }
    }
}

struct PiPContentView: View {
    let onClose: () -> Void
    @Environment(PlayerEngine.self) private var player

    var body: some View {
        HStack(spacing: 10) {
            AsyncArtwork(
                coverArtId: player.currentSong?.coverArtId,
                size: 80,
                cornerRadius: 8
            )
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(player.currentSong?.title ?? "Not Playing")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(player.currentSong?.artist ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 14) {
                    Button { player.skipBackward() } label: {
                        Image(systemName: "backward.fill").font(.caption)
                    }.buttonStyle(.plain)

                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.subheadline)
                    }.buttonStyle(.plain)

                    Button { player.skipForward() } label: {
                        Image(systemName: "forward.fill").font(.caption)
                    }.buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
        }
        .padding(12)
        .frame(width: 300, height: 100)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
    }
}
