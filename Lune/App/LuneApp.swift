import SwiftUI

@main
struct LuneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var playerEngine = PlayerEngine.shared
    @State private var libraryStore: LibraryStore

    init() {
        // Before anything reads a secret.
        KeychainStore.migrateFromUserDefaults()
        _libraryStore = State(initialValue: LibraryStore.shared)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(playerEngine)
                .environment(libraryStore)
        }
        .defaultSize(width: 1100, height: 720)
        .commands { PlaybackCommands() }

        Settings {
            SettingsView()
                .environment(libraryStore)
        }

        MenuBarExtra("Lune", systemImage: "music.note") {
            MenuBarPlayerView()
                .environment(playerEngine)
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        configureWindow()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        configureWindow()
    }

    private func configureWindow() {
        if let window = NSApp.windows.first {
            window.minSize = NSSize(width: 1000, height: 850)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            window.styleMask.insert(.titled)
            window.styleMask.insert(.closable)
            window.styleMask.insert(.miniaturizable)
            window.styleMask.insert(.resizable)
        }
    }
}

