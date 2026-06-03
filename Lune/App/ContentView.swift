import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(LibraryStore.self) private var library
    @State private var selectedSidebarItem: SidebarItem? = .albums
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showNowPlaying = false
    @State private var showFullPlayer = false

    var body: some View {
        Group {
            if library.serverConfig == nil {
                OnboardingView()
            } else {
                mainLayout
            }
        }
        .overlay {
            if showNowPlaying && !showFullPlayer {
                NowPlayingView(isShowing: $showNowPlaying, openFullPlayer: openFullPlayer)
                    .transition(.opacity)
            }
        }
        .overlay {
            if showFullPlayer {
                FullPlayerView(isShowing: $showFullPlayer)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showNowPlaying)
        .animation(.easeInOut(duration: 0.25), value: showFullPlayer)
        // Auto-enter macOS full-screen when full player opens
        .onChange(of: showFullPlayer) { _, isFullPlayer in
            if isFullPlayer {
                enterFullScreen()
            } else {
                exitFullScreen()
                // Return to expanded player
                showNowPlaying = true
            }
        }
        // Handle the user exiting full-screen via macOS (green button / Esc on native FS)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            if showFullPlayer {
                withAnimation(.easeInOut(duration: 0.25)) { showFullPlayer = false }
                showNowPlaying = true
            }
        }
    }

    // MARK: - Full-screen helpers

    private func openFullPlayer() {
        showFullPlayer = true
        // Defer so SwiftUI applies showFullPlayer first, then we kick off the FS animation
        DispatchQueue.main.async { enterFullScreen() }
    }

    private func enterFullScreen() {
        guard let window = luneWindow, !window.styleMask.contains(.fullScreen) else { return }
        window.toggleFullScreen(nil)
    }

    private func exitFullScreen() {
        guard let window = luneWindow, window.styleMask.contains(.fullScreen) else { return }
        window.toggleFullScreen(nil)
    }

    private var luneWindow: NSWindow? {
        // The main Lune window is the first titled, non-panel window
        NSApp.windows.first { $0.styleMask.contains(.titled) && !($0 is NSPanel) }
    }

    // MARK: - Layout

    private var mainLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selectedSidebarItem)
        } detail: {
            ZStack {
                NavigationStack {
                    destinationView(for: selectedSidebarItem)
                }

                VStack {
                    Spacer()
                    NowPlayingBar(showNowPlaying: $showNowPlaying)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .padding(.leading, 12)
        }
        .toolbar(showNowPlaying || showFullPlayer ? .hidden : .automatic, for: .windowToolbar)
        .overlay(alignment: .topLeading) {
            Button("") { openFullPlayer() }
                .keyboardShortcut("f", modifiers: [])
                .hidden()
        }
    }

    @ViewBuilder
    private func destinationView(for item: SidebarItem?) -> some View {
        switch item {
        case .artists:   ArtistListView()
        case .albums:    AlbumGridView()
        case .songs:     SongListView()
        case .genres:    GenreListView()
        case .favorites: FavoritesView()
        case .lastFMStats: LastFMStatsView()
        case .playlist(let id): PlaylistDetailView(playlistId: id)
        case nil:        AlbumGridView()
        }
    }
}
