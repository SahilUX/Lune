# Lune Project Handoff

**Last Updated:** June 9, 2026  
**Status:** Active Development (v1.0 approaching)  
**Platform:** macOS (Sonoma 14+)

---

## Quick Overview

Lune is a native macOS music player for Navidrome servers. It's written in Swift 6 with SwiftUI and provides a polished, first-party Apple-like experience for self-hosted music libraries.

**Key Achievement:** Full-featured music player with Last.fm integration (scrobbling + stats dashboard)

---

## Current Status

### ✅ Completed Features (v0.4)
- Server connection & library browsing (Artists, Albums, Songs, Genres, Playlists, Favorites)
- Full playback control (play, pause, skip, seek, volume, repeat, shuffle)
- Queue management (view, reorder tracks)
- Album & artist detail views with track listings
- Search across library
- Star/favorite songs, albums, artists
- macOS media keys support (hardware play/pause/next/prev)
- Now Playing bar + expanded player overlay
- Full-screen player (press F or button)
- Picture-in-Picture window
- Track caching for offline playback
- **Last.fm scrobbling** (real-time now-playing + track scrobble at 50% or 4 min threshold)
- **Last.fm stats dashboard** with 4 tabs:
  - Recent Scrobbles (list with now-playing badge)
  - Top Tracks (grid with 6 time periods)
  - Top Artists (grid with 6 time periods)
  - Top Albums (grid with 6 time periods)
- Last.fm → Library navigation (click items to view in Navidrome)

### 🔄 In Progress
- Image loading optimization for Last.fm (investigation ongoing)
- Polish & testing for v1.0 release

### ⏳ Planned (v1.1+)
- Home screen with recents/most played
- Lyrics display (synced)
- ReplayGain / volume normalization
- Additional sort/filter options
- Full keyboard shortcut suite

---

## Architecture

### Tech Stack
| Layer | Technology |
|---|---|
| UI | SwiftUI 6 + Swift concurrency (async/await) |
| Audio | AVFoundation (AVPlayer) |
| Networking | URLSession |
| Persistence | SwiftData + UserDefaults |
| Credentials | Keychain |
| Now Playing Info | MPNowPlayingInfoCenter |
| Image Cache | NSCache + disk cache |
| Last.fm | Last.fm API (OAuth 3-step flow) |

### Key Files

#### App Entry
- `LuneApp.swift` — @main entry, window setup, commands
- `ContentView.swift` — Main layout (sidebar + detail + player bar)
- `AppDelegate.swift` — macOS window configuration

#### Playback & State
- `PlayerEngine.swift` — AVPlayer wrapper, singleton, observable
- `PlaybackQueue.swift` — Queue state management
- `NowPlayingBridge.swift` — MPNowPlayingInfoCenter integration

#### API & Networking
- `SubsonicClient.swift` — Navidrome/Subsonic API client
- `SubsonicModels.swift` — Codable response types
- `LastFMClient.swift` — Last.fm API + OAuth flow (actor-based)
- `Secrets.swift.template` — Last.fm credentials template (user fills in)

#### Views (UI)
- `SidebarView.swift` — Sidebar navigation (enum SidebarItem)
- `AlbumGridView.swift` — 3-column album grid with search/filter
- `AlbumDetailView.swift` — Album detail + track list
- `ArtistListView.swift` → `ArtistDetailView` — Artist + albums
- `SongListView.swift` — All songs list
- `GenreListView.swift` — Browse by genre
- `FavoritesView.swift` — Starred items
- `PlaylistDetailView.swift` — Playlist + track list
- `SearchView.swift` — Full-text search
- `LastFMStatsView.swift` — Last.fm stats dashboard (4 tabs)
- `NowPlayingBar.swift` — Bottom playback bar
- `NowPlayingView.swift` — Expanded player (side-by-side art + lyrics)
- `FullPlayerView.swift` — Full-screen immersive player
- `QueueView.swift` — Queue management
- `SettingsView.swift` — Server config + Last.fm auth + prefs

#### Cache & Storage
- `TrackCache.swift` — Disk cache for audio files
- `ImageCache.swift` — Album art in-memory + disk cache
- `LibraryStore.swift` — SwiftData persistence

#### Utilities
- `ColorExtractor.swift` — Dominant color from album art
- `DurationFormatter.swift` — Format seconds as MM:SS
- `PlaybackCommands.swift` — Keyboard shortcuts (Commands menu)

### Project Structure
```
Lune/
├── App/
│   ├── LuneApp.swift
│   ├── ContentView.swift
│   ├── AppDelegate.swift
│   └── PlaybackCommands.swift
├── API/
│   ├── SubsonicClient.swift
│   ├── SubsonicModels.swift
│   ├── LastFMClient.swift
│   ├── Secrets.swift.template
│   └── APIError.swift
├── Audio/
│   ├── PlayerEngine.swift
│   ├── PlaybackQueue.swift
│   └── NowPlayingBridge.swift
├── Cache/
│   ├── TrackCache.swift
│   └── ImageCache.swift
├── Models/
│   ├── Song.swift
│   ├── Album.swift
│   ├── Artist.swift
│   └── Playlist.swift
├── Persistence/
│   └── LibraryStore.swift
├── Views/
│   ├── Sidebar/
│   │   └── SidebarView.swift
│   ├── Library/
│   │   ├── AlbumGridView.swift
│   │   ├── AlbumDetailView.swift
│   │   ├── ArtistListView.swift
│   │   ├── SongListView.swift
│   │   ├── GenreListView.swift
│   │   ├── FavoritesView.swift
│   │   └── LastFMStatsView.swift
│   ├── NowPlaying/
│   │   ├── NowPlayingBar.swift
│   │   ├── NowPlayingView.swift
│   │   └── FullPlayerView.swift
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
    ├── ColorExtractor.swift
    └── DurationFormatter.swift
```

### State Management
```
PlayerEngine (singleton @Observable)
  ├── publishes: currentSong, isPlaying, duration, currentTime
  ├── publishes: queue, currentIndex
  ├── publishes: volume, shuffle, repeatMode
  └── calls: LastFMClient for scrobbling

LibraryStore (SwiftData environment)
  ├── manages: library cache
  ├── manages: playlists
  └── syncs with: SubsonicClient

LastFMClient (actor singleton)
  ├── OAuth session management
  ├── Scrobbling (updateNowPlaying, scrobble)
  └── Stats queries (getRecentTracks, getTopXxx)
```

---

## Last.fm Integration

### Setup
1. User fills `Lune/Config/Secrets.swift` with Last.fm API key + secret from https://www.last.fm/api/account/create
2. Secrets.swift is .gitignored (never commits credentials)

### Authentication Flow (3-step OAuth)
```
User clicks "Sign in with Last.fm" in Settings
  ↓
getToken() → Last.fm API returns token
  ↓
openAuthPage(token) → Opens browser to https://last.fm/api/auth
  ↓
User approves & browser redirects back
  ↓
getSession(token) → Exchange token for sessionKey + username
  ↓
Store in UserDefaults (sessionKey, username, lastfmEnabled toggle)
```

### Scrobbling
- `PlayerEngine.updateNowPlaying(song:)` called when track loads
- `PlayerEngine.scrobble(song:startedAt:duration:)` called when:
  - Track reaches 50% played, OR
  - 4 minutes elapsed (whichever is first)
- Both are fire-and-forget (async, no UI blocking)

### Stats Dashboard
**Recent Scrobbles Tab:**
- List of last 50 scrobbles
- Shows: artwork, track name, artist, timestamp
- First item gets "Now Playing" green badge
- Click → searches Subsonic for track → opens album

**Top Tracks/Artists/Albums Tabs:**
- Grid layout (5-column adaptive)
- Time period picker: 7 Days, 1 Month, 3 Months, 6 Months, 1 Year, All Time
- Cards show: rank badge, artwork, title, artist/play count
- Click → searches Subsonic, navigates to detail view
- Skeleton loading with shimmer animation while fetching

**Search Behavior:**
- First tries: "Track/Album Name + Artist"
- If artist is "Unknown" and search fails, retries with just name
- No results = link disabled (graceful fallback)

---

## Building & Running

### Prerequisites
- Xcode 15+ (Swift 6 compiler)
- macOS 14 (Sonoma) or later
- Navidrome server (self-hosted music library)
- Last.fm account (optional, for scrobbling)

### Build Steps
```bash
# Clone and open
git clone https://github.com/SahilUX/Lune.git
cd Lune
open Lune.xcodeproj

# (Or use command line)
xcodebuild -scheme Lune build
xcodebuild -scheme Lune test
```

### First Run
1. **Server Setup:** Enter Navidrome URL + credentials in Settings
2. **Last.fm (optional):** Fill `Lune/Config/Secrets.swift`, then Settings → Last.fm → Sign in
3. **Player:** Click album → click track to play or use play button

### Key Shortcuts
| Action | Shortcut |
|---|---|
| Play/Pause | Space |
| Next Track | ⌘→ |
| Previous Track | ⌘← |
| Full-Screen Player | F |
| Toggle Queue | ⌘U |
| Toggle Lyrics | Click button in expanded player |
| Volume Up | ⌘↑ |
| Volume Down | ⌘↓ |
| Star Track | ⌘D |

---

## Known Issues & Limitations

### Last.fm Image Loading
**Status:** Investigation ongoing (June 2026)
- Some Last.fm artwork doesn't display (shows placeholder star icon)
- Possible causes:
  1. Last.fm "top tracks/artists/albums" endpoints don't return images
  2. Image URL structure differs between endpoints
  3. URLs are inaccessible/blocked
- **Workaround:** Fallback logic tries multiple image sizes (extralarge → large → medium → small)
- **Debug logs:** Xcode console shows "[Last.fm]" messages when images found/fail

### Artist Navigation
- Clicking a Last.fm artist opens artist detail view (shows albums)
- No dedicated "artist radio" or "similar artists" yet (v1.1 feature)

### Offline Cache
- Tracks cache automatically as they play
- Manual cache management not yet implemented (all tracks cached indefinitely)
- Cache size limit setting exists but not enforced

### Lyrics
- Sync'd lyrics supported in extended player (if Navidrome provides them)
- Full lyrics sheet not yet styled

---

## Recent Changes (Last Week)

### F Key Shortcut
- Press `F` from anywhere to open full-screen player
- Implemented via `.onKeyPress` modifier (native macOS approach)

### Last.fm Tab UI
- Replaced TabView with toggle buttons (matching Lyrics/Vinyl style)
- Shows icon + label with accent highlight
- Cleaner design consistent with expanded player

### Navigation from Last.fm Stats
- Click any track/album/artist → searches Subsonic
- Navigate to detail view for playback
- Fallback search if artist is "Unknown"

### Debug Logging
- "[Last.fm]" console messages for image loading troubleshooting
- Helps diagnose API response structure issues

---

## Testing Checklist

### Before Release
- [ ] Play full album without errors
- [ ] Seek/skip/pause works
- [ ] Media keys (hardware buttons) work
- [ ] Full-screen player (F key) centered and responsive
- [ ] Last.fm sign-in flow completes
- [ ] Scrobbles appear on Last.fm within 5 minutes
- [ ] Last.fm stats load all 4 tabs
- [ ] Click Last.fm item → navigates to album/artist
- [ ] Offline caching works (play without network)
- [ ] Picture-in-Picture window opens
- [ ] Queue reordering works
- [ ] Playlists create/edit/delete
- [ ] Search finds items correctly
- [ ] Favorites/star toggle persists

---

## Next Steps

### High Priority (v1.0)
- [ ] Resolve Last.fm image loading (confirm API structure)
- [ ] Polish full-screen player on different screen sizes
- [ ] Test on M1/M2/Intel Macs
- [ ] Beta test with external users

### Medium Priority (v1.1)
- [ ] Home screen with recents/most played
- [ ] Full keyboard shortcut suite
- [ ] Lyrics display with sync
- [ ] ReplayGain support

### Low Priority (v2.0+)
- [ ] Podcast support
- [ ] Multi-server management
- [ ] Collaborative playlists
- [ ] Music discovery features

---

## Contact & Support

**Repository:** https://github.com/SahilUX/Lune  
**Author Email:** abdulsaleem.ak.1975@gmail.com

For issues: Create GitHub issue with:
- Xcode version
- macOS version
- Steps to reproduce
- Console logs (with [Last.fm] filter)

---

## Document Changelog

| Date | Update |
|---|---|
| 2026-06-09 | Initial handoff document created |

