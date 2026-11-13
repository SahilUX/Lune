# Lune

A native macOS music client for Navidrome/Subsonic servers with Last.fm scrobbling support.

## Features

- **Music Playback**: Stream music from your Navidrome/Subsonic server
- **Library Management**: Browse artists, albums, songs, genres, and playlists
- **Now Playing**: Expanded player with album artwork, lyrics, and vinyl/album art toggle
- **Picture-in-Picture**: Floating player window that stays on top
- **Smart Playlist**: Drag-and-drop songs into playlists with multi-select support
- **Formatting Control**: Choose streaming format (MP3, AAC, FLAC, Opus) and bitrate for local and remote networks
- **Favorites**: Star songs for quick access
- **Search**: Full-text search across your library
- **Last.fm Integration**: Scrobble your plays to Last.fm
- **Lyrics**: Display synchronized lyrics when available
- **Caching**: Local cache for offline playback
- **System Integration**: Menu bar player, keyboard shortcuts, system media controls

## Requirements

- macOS 14.0+
- Navidrome or Subsonic server
- Swift 6.0 (only to build from source)

## Install

1. Download `Lune-<version>.dmg` from the [latest release](https://github.com/SahilUX/Lune/releases/latest).
2. Open the DMG.
3. Drag **Lune** onto the **Applications** shortcut in the same window.
4. Eject the DMG and open Lune from Applications or Launchpad.

The DMG is signed with a Developer ID certificate and notarized by Apple, so it opens without Gatekeeper warnings.

## Building from source

1. Clone the repository
2. Open `Lune.xcodeproj` in Xcode
3. Build and run with `Cmd+B`

## Setup

### Server Connection

1. Open Settings > Server
2. Enter your local and/or remote Navidrome/Subsonic server URLs
3. Add your username and password
4. Click "Test Connection" to verify
5. Click "Save"

#### Self-signed certificates

If your server uses a certificate macOS doesn't trust (self-signed, or from a private CA), Lune shows its SHA-256 fingerprint and asks whether to trust it. Trusting pins that exact certificate for that host: Lune accepts it only when it matches, and asks again if the certificate changes. Normal TLS checks stay on for everything else. Pinned hosts are listed under Settings > Server > Trusted Certificates, where you can forget them.

### Last.fm Scrobbling

1. Register an app at [last.fm/api/account/create](https://www.last.fm/api/account/create)
2. Open Settings > Last.fm
3. Paste your API key and secret
4. Click "Connect Last.fm" and authorize in your browser
5. Click "I've authorized — Finish connecting"
6. Toggle "Enable scrobbling" to start sending plays to Last.fm

### Playback Settings

1. Open Settings > Playback
2. Configure format and bitrate for local and remote streaming
3. Enable/disable menu bar player
4. Configure PiP (Picture-in-Picture) window behavior

## Architecture

- **SwiftUI** for the UI with macOS 14+ deployment target
- **Swift 6** strict concurrency (actors, @MainActor, @Observable)
- **AVFoundation** for audio playback
- **Subsonic API v1.16.1** for server communication
- **UserDefaults** for settings persistence
- **Last.fm API** for scrobbling

### Key Components

- `PlayerEngine`: Central audio playback and queue management
- `SubsonicClient`: Network layer for Subsonic API calls
- `LastFMClient`: Last.fm API integration for scrobbling
- `LibraryStore`: Manages music library cache and state
- `TrackCache`: Local file caching for offline playback
- `ImageCache`: Two-tier image caching (memory + disk)

## Project Structure

```
Lune/
├── API/              # Network clients (Subsonic, Last.fm, Lyrics)
├── App/              # Main app entry and content routing
├── Audio/            # Playback engine and bridge
├── Cache/            # Track and image caching
├── Components/       # Reusable UI components
├── Models/           # Data models
├── Persistence/      # Settings and configuration
├── Utilities/        # Helper functions
└── Views/            # UI views by feature
    ├── Library/      # Artists, albums, songs, genres
    ├── NowPlaying/   # Player UI
    ├── Playlists/    # Playlist management
    ├── Queue/        # Queue view
    ├── Search/       # Search interface
    ├── Settings/     # Settings and onboarding
    └── Sidebar/      # Navigation sidebar
```

## Development

### Adding Features

1. Create new feature branches from `main`
2. Build with `xcodebuild -scheme Lune build`
3. Test in Xcode with Cmd+R
4. Commit with clear messages

### Code Style

- Follow Swift style guidelines
- Use SwiftUI for new UI components
- Mark concurrent code with `@MainActor` or `nonisolated` as appropriate
- No external dependencies (uses system frameworks only)

## Releasing

`scripts/release.sh` builds a notarized Developer ID DMG:

1. Archives the Release configuration.
2. Exports it with `ExportOptions.plist` (method `developer-id`, team `627Y9R25T5`, automatic signing).
3. Builds the DMG with `hdiutil`: `Lune.app` plus an `/Applications` link, UDZO compressed, volume name "Lune".
4. Signs the DMG with the Developer ID Application identity for team `627Y9R25T5`.
5. Submits the DMG with `xcrun notarytool submit --keychain-profile lune-notary --wait`, and prints the notary log if Apple rejects it.
6. Staples the ticket to the DMG and checks it with `stapler validate` and `spctl -t open`.

The only output is `~/Downloads/Lune-<version>/Lune-<version>.dmg`. The version comes from `CFBundleShortVersionString` in `Lune/Info.plist`.

To publish it, merge your changes to `main`, run the script from the main checkout, then attach the DMG to a GitHub release:

```sh
gh release create v<version> ~/Downloads/Lune-<version>/Lune-<version>.dmg \
  --title "Lune <version>" --generate-notes
```

Run it from the main checkout, where the real `Lune/Config/Secrets.swift` lives (it is gitignored, so worktrees only get the template). Run it from a normal terminal session: signing and notarytool need full access to the login keychain.

Before the first run you need:

- A **Developer ID Application** certificate for team `627Y9R25T5` in the login keychain.
- A notarytool profile: `xcrun notarytool store-credentials lune-notary --team-id 627Y9R25T5` (set `NOTARY_PROFILE` to use another name).
- `Lune/Config/Secrets.swift` with real Last.fm keys. The script warns if it still has the template placeholders.

## License

Copyright (c) 2026 Sahil Saleem. Licensed under GPL-3.0: you may reuse, change and sell it, but anything you distribute that includes it must stay GPL-3.0 with source. See [LICENSE](LICENSE).

## Contact

Built with Navidrome 🎵
