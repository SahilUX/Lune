import SwiftUI

struct PlaybackCommands: Commands {
    var body: some Commands {
        CommandMenu("Playback") {
            Button("Play / Pause") { PlayerEngine.shared.togglePlayPause() }
                .keyboardShortcut(" ", modifiers: [])

            Button("Next Track") { PlayerEngine.shared.skipForward() }
                .keyboardShortcut(.rightArrow, modifiers: .command)

            Button("Previous Track") { PlayerEngine.shared.skipBackward() }
                .keyboardShortcut(.leftArrow, modifiers: .command)

            Divider()

            Button("Volume Up") { PlayerEngine.shared.volume = min(1, PlayerEngine.shared.volume + 0.1) }
                .keyboardShortcut(.upArrow, modifiers: .command)

            Button("Volume Down") { PlayerEngine.shared.volume = max(0, PlayerEngine.shared.volume - 0.1) }
                .keyboardShortcut(.downArrow, modifiers: .command)

            Divider()

            Button("Star Current Track") { PlayerEngine.shared.starCurrentTrack() }
                .keyboardShortcut("d", modifiers: .command)
        }
    }
}
