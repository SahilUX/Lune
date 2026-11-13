import SwiftUI

@main
struct LuneApp: App {
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
