import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(LibraryStore.self) private var library
    @State private var selectedSidebarItem: SidebarItem? = .albums
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showNowPlaying = false
    @State private var showFullPlayer = false
    @State private var maxWindowSize = ScreenLimits.maxWindowSize

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
        .frame(minWidth: 900, maxWidth: maxWindowSize.width, minHeight: 600, maxHeight: maxWindowSize.height)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            maxWindowSize = ScreenLimits.maxWindowSize
        }
        .background(WindowAccessor { MainWindow.shared.attach($0) })
        // The full player owns native full screen: opening it enters, closing it leaves.
        .onChange(of: showFullPlayer) { _, isFullPlayer in
            MainWindow.shared.setFullScreen(isFullPlayer)
            // Return to expanded player
            if !isFullPlayer { showNowPlaying = true }
        }
        .onAppear {
            // The user left full screen themselves (green button, Ctrl-Cmd-F).
            MainWindow.shared.onUnrequestedExit = {
                withAnimation(.easeInOut(duration: 0.25)) { showFullPlayer = false }
            }
        }
        // F key to open full-screen player
        .onKeyPress("f") {
            openFullPlayer()
            return .handled
        }
    }

    private func openFullPlayer() {
        showFullPlayer = true
    }

    // MARK: - Layout

    private var mainLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selectedSidebarItem)
        } detail: {
            NavigationStack {
                destinationView(for: selectedSidebarItem)
            }
            // An inset (not an overlay) so scrollable content stops above the
            // floating bar and the last row can scroll clear of it.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NowPlayingBar(showNowPlaying: $showNowPlaying)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
            .padding(.leading, 12)
        }
        .toolbar(showNowPlaying || showFullPlayer ? .hidden : .automatic, for: .windowToolbar)
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


// MARK: - Main window

/// Finds the NSWindow hosting a SwiftUI view.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = HostView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class HostView: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}

// MARK: - Full-screen bookkeeping

/// Pure bookkeeping for native full screen, kept free of AppKit so it can be tested.
///
/// Full screen is a transition that takes a second or so, during which AppKit ignores a
/// second toggle. This remembers what the full player wants and applies it once the
/// current transition has finished, so the window and the UI can't end up disagreeing.
struct FullScreenState {
    /// What the caller should do after an event.
    struct Step: Equatable {
        var toggle = false
        /// The user left full screen themselves while the full player still wanted it.
        var userLeft = false
    }

    private(set) var isFullScreen = false
    private(set) var isTransitioning = false
    private(set) var wantsFullScreen = false
    /// Whether the full player put the window into full screen (so it should take it out again).
    private var playerOwnsFullScreen = false
    private var exitWasUnrequested = false

    init(isFullScreen: Bool = false) { self.isFullScreen = isFullScreen }

    mutating func request(_ wanted: Bool) -> Step {
        if wanted {
            // Already full screen (the user's own doing)? Leave it as found when the player closes.
            playerOwnsFullScreen = !isFullScreen
            wantsFullScreen = true
        } else {
            wantsFullScreen = isFullScreen && !playerOwnsFullScreen
            playerOwnsFullScreen = false
        }
        return reconcile()
    }

    mutating func willEnter() { isTransitioning = true }

    mutating func willExit() {
        isTransitioning = true
        // Leaving while the player still wants full screen means the user did it, not us.
        exitWasUnrequested = wantsFullScreen
    }

    mutating func didEnter() -> Step { finish(isFullScreen: true) }
    mutating func didExit() -> Step { finish(isFullScreen: false) }

    private mutating func finish(isFullScreen full: Bool) -> Step {
        isFullScreen = full
        isTransitioning = false
        if !full, exitWasUnrequested {
            exitWasUnrequested = false
            wantsFullScreen = false
            playerOwnsFullScreen = false
            return Step(userLeft: true)
        }
        return reconcile()
    }

    private func reconcile() -> Step {
        Step(toggle: !isTransitioning && isFullScreen != wantsFullScreen)
    }
}

// MARK: - Main window

/// The one main window. Feeds AppKit's full-screen notifications to `FullScreenState`.
@MainActor
final class MainWindow {
    static let shared = MainWindow()

    private(set) weak var window: NSWindow?

    /// Called when the user leaves full screen themselves while the full player wants it.
    var onUnrequestedExit: (() -> Void)?

    private var tokens: [NSObjectProtocol] = []
    private var state = FullScreenState()

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens.removeAll()

        self.window = window
        state = FullScreenState(isFullScreen: window.styleMask.contains(.fullScreen))

        func observe(_ name: Notification.Name, _ handler: @escaping @MainActor (MainWindow) -> Void) {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { handler(self) } }
            })
        }
        observe(NSWindow.willEnterFullScreenNotification) { $0.state.willEnter() }
        observe(NSWindow.willExitFullScreenNotification) { $0.state.willExit() }
        observe(NSWindow.didEnterFullScreenNotification) { $0.apply($0.state.didEnter()) }
        observe(NSWindow.didExitFullScreenNotification) { $0.apply($0.state.didExit()) }
    }

    func setFullScreen(_ wanted: Bool) {
        apply(state.request(wanted))
    }

    private func apply(_ step: FullScreenState.Step) {
        if step.toggle { window?.toggleFullScreen(nil) }
        if step.userLeft { onUnrequestedExit?() }
    }
}

/// Bounds for the window: never bigger than the displays it can be on. Without a cap, a layout
/// that asks for unlimited width gets it (we saw a 100000pt-wide window).
enum ScreenLimits {
    static var maxWindowSize: CGSize {
        let all = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        return all.isNull ? CGSize(width: 8000, height: 6000) : all.size
    }
}
