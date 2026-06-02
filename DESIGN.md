# Design Document — Lune
### Native macOS Navidrome Client
**Version:** 1.0  
**Date:** 2026-05-29

---

## 1. Visual Design

### 1.1 Design Language
Lune follows Apple's Human Interface Guidelines and takes strong cues from the macOS Music app and Vinyls (iOS). The aesthetic is:
- **Clean and content-forward** — album art is the hero
- **Dark-mode first** — music apps live in dark mode
- **High contrast typography** — legible at small sizes in the sidebar
- **Vibrancy** — sidebar and player use NSVisualEffectView / `.ultraThinMaterial`

### 1.2 Color Palette
| Role | Light | Dark |
|---|---|---|
| Background | `systemBackground` | `systemBackground` |
| Secondary BG | `secondarySystemBackground` | |
| Accent | Dynamic, sampled from current album art | |
| Primary text | `label` | |
| Secondary text | `secondaryLabel` | |

The accent color is sampled from the dominant hue of the playing album's cover art using `UIColor(ciImage:)` / Core Image palette extraction, giving the UI a dynamic per-album feel.

### 1.3 Typography
- Titles: SF Pro Display, Semibold
- Body / metadata: SF Pro Text, Regular
- Timestamps / secondary: SF Pro Text, Regular, `secondaryLabel`

---

## 2. Layout & Navigation

### 2.1 Window Structure
```
┌─────────────────────────────────────────────────────────────┐
│  Toolbar (search, window controls)                          │
├──────────────┬──────────────────────────────────────────────┤
│              │                                              │
│   Sidebar    │         Content Area                         │
│   (220pt)    │         (NavigationStack)                    │
│              │                                              │
│  ── Library  │                                              │
│    Artists   │                                              │
│    Albums    │                                              │
│    Songs     │                                              │
│    Genres    │                                              │
│  ── Playlists│                                              │
│    + New     │                                              │
│              │                                              │
├──────────────┴──────────────────────────────────────────────┤
│  Now Playing Bar (fixed, 80pt tall)                         │
│  [art][title/artist][──────────seek──────────][vol][queue]  │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Navigation Model
- `NavigationSplitView` with sidebar + detail
- Sidebar items map to top-level `NavigationStack` destinations
- Now Playing expands to a full sheet (`NavigationLink` to `NowPlayingView`)

### 2.3 Key Views

**AlbumGridView** — 3-column grid of album cards (art + title + artist). Clicking opens `AlbumDetailView`.

**AlbumDetailView** — Large hero art (left column), track list (right column). Play button starts album from track 1. Each track row has play/add-to-queue context menu.

**NowPlayingView** (full screen overlay) — Large blurred album art background, centered art, title, artist, seek bar, controls, lyrics panel (if available).

**QueueView** — Sheet from Now Playing bar. Drag-to-reorder track list. Current track highlighted.

**SearchView** — Inline results as user types, grouped by Artists / Albums / Songs.

---

## 3. Architecture

### 3.1 Technology Stack
| Layer | Technology |
|---|---|
| UI | SwiftUI |
| Audio | AVFoundation (`AVPlayer` + `AVPlayerItem`) |
| Networking | `URLSession` (async/await) |
| Persistence | SwiftData (library cache, queue, settings) |
| Credentials | Keychain via `Security` framework |
| Now Playing | `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter` |
| Image cache | `NSCache` + disk cache in Application Support |

### 3.2 Package Structure
```
Lune/
├── App/
│   ├── LuneApp.swift           # @main entry point
│   └── AppDelegate.swift       # Menu bar extra, app lifecycle
├── API/
│   ├── SubsonicClient.swift     # All API calls
│   ├── SubsonicModels.swift     # Codable response types
│   └── APIError.swift
├── Audio/
│   ├── PlayerEngine.swift       # AVPlayer wrapper, singleton
│   ├── PlaybackQueue.swift      # Observable queue state
│   └── NowPlayingBridge.swift   # MPNowPlayingInfoCenter
├── Cache/
│   ├── TrackCache.swift         # Disk cache for audio files
│   └── ImageCache.swift         # In-memory + disk art cache
├── Models/
│   ├── Song.swift
│   ├── Album.swift
│   ├── Artist.swift
│   └── Playlist.swift
├── Persistence/
│   └── LibraryStore.swift       # SwiftData container
├── Views/
│   ├── Sidebar/
│   ├── Library/
│   │   ├── ArtistListView.swift
│   │   ├── AlbumGridView.swift
│   │   ├── AlbumDetailView.swift
│   │   └── SongListView.swift
│   ├── NowPlaying/
│   │   ├── NowPlayingBar.swift
│   │   └── NowPlayingView.swift
│   ├── Queue/
│   │   └── QueueView.swift
│   ├── Playlists/
│   │   ├── PlaylistListView.swift
│   │   └── PlaylistDetailView.swift
│   ├── Search/
│   │   └── SearchView.swift
│   └── Settings/
│       └── SettingsView.swift
└── Utilities/
    ├── ColorExtractor.swift     # Dominant color from album art
    └── DurationFormatter.swift
```

### 3.3 State Management
```
                     ┌─────────────────┐
                     │  PlayerEngine   │  @Observable singleton
                     │  (AVPlayer)     │  owns playback state
                     └────────┬────────┘
                              │ publishes
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
         NowPlayingBar   NowPlayingView   QueueView
```

- `PlayerEngine` is an `@Observable` class injected via `.environment`
- `LibraryStore` (SwiftData) owns cached library data
- `SubsonicClient` is stateless — pure async functions, takes server config

### 3.4 Audio Streaming Flow
```
User taps Play
   → PlayerEngine.play(song:)
   → Check TrackCache for local file
       → Hit: AVPlayer(url: localFileURL)
       → Miss: AVPlayer(url: streamURL + apiKey) — streams directly
   → AVPlayerItem plays
   → TrackCache.store() saves bytes as they arrive (for future offline)
```

### 3.5 Subsonic API Mapping
| Feature | Subsonic Endpoint |
|---|---|
| Browse artists | `getArtists` |
| Browse albums | `getArtist`, `getAlbumList2` |
| Album detail | `getAlbum` |
| Stream | `stream` |
| Cover art | `getCoverArt` |
| Search | `search3` |
| Playlists | `getPlaylists`, `getPlaylist`, `createPlaylist`, `updatePlaylist`, `deletePlaylist` |
| Star/Unstar | `star`, `unstar` |
| Scrobble | `scrobble` |

---

## 4. Data Models

```swift
struct Song: Identifiable, Codable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let albumId: String
    let duration: Int        // seconds
    let trackNumber: Int?
    let year: Int?
    let coverArtId: String?
    let isStarred: Bool
}

struct Album: Identifiable, Codable {
    let id: String
    let name: String
    let artist: String
    let artistId: String
    let coverArtId: String?
    let songCount: Int
    let duration: Int
    let year: Int?
    let genre: String?
}

struct Artist: Identifiable, Codable {
    let id: String
    let name: String
    let albumCount: Int
    let coverArtId: String?
}

struct Playlist: Identifiable, Codable {
    let id: String
    let name: String
    let songCount: Int
    let duration: Int
    var songs: [Song]
}
```

---

## 5. Settings

Stored in `UserDefaults` (non-sensitive) and Keychain (password):

| Setting | Storage | Default |
|---|---|---|
| Server URL | UserDefaults | — |
| Username | UserDefaults | — |
| Password | Keychain | — |
| Stream quality (bitrate cap) | UserDefaults | Original |
| Cache size limit | UserDefaults | 2 GB |
| Menu bar player enabled | UserDefaults | false |
| ReplayGain mode | UserDefaults | Track |

---

## 6. Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| Play / Pause | Space |
| Next Track | ⌘→ |
| Previous Track | ⌘← |
| Seek +10s | ⌥→ |
| Seek -10s | ⌥← |
| Volume Up | ⌘↑ |
| Volume Down | ⌘↓ |
| Toggle Queue | ⌘U |
| Search | ⌘F |
| Now Playing | ⌘L |
| Star current track | ⌘D |

---

## 7. Menu Bar Extra (Optional)

When enabled in settings, Lune shows a mini-player in the macOS menu bar:
- Click icon to expand popover
- Popover shows: art thumbnail, title, artist, play/pause/skip buttons, seek bar
- Lune can continue playing with main window closed when menu bar player is active
