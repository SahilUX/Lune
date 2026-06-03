# Product Requirements Document — Lune
### Native macOS Navidrome Client
**Version:** 1.1  
**Date:** 2026-06-03  
**Status:** In Progress

---

## 1. Overview

Lune is a native macOS music player that connects to a self-hosted Navidrome server via the Subsonic API. It is designed to feel like a first-party Apple application — fast, polished, and deeply integrated with macOS — while providing the full power of a personal music library.

---

## 2. Problem Statement

Navidrome users on macOS currently rely on:
- Web browser (no offline caching, no OS integration, no keyboard media keys)
- Cross-platform Electron apps (heavy, non-native feel, high memory use)
- iOS apps running in compatibility mode (poor UX, missing Mac-specific patterns)

There is no purpose-built, native SwiftUI application for Navidrome on macOS.

---

## 3. Goals

| Goal | Metric |
|---|---|
| Launch and be usable in < 2 seconds | Cold launch time |
| Feel native on macOS | Passes HIG checklist |
| Support core music browsing and playback | Feature completeness |
| Work offline with cached tracks | Cache hit rate during offline session |

---

## 4. Non-Goals

- iOS / iPadOS support (v1)
- Podcast or internet radio support (v1)
- Multi-server management beyond switching active server (v1)
- Audio transcoding or format conversion

---

## 5. Target Users

**Primary:** macOS power users who self-host Navidrome and want a dedicated desktop client.  
**Secondary:** macOS users exploring self-hosted music as an alternative to streaming services.

---

## 6. Features

### 6.1 Core (Must Have — v1.0)

| ID | Feature | Description |
|---|---|---|
| F-01 | Server connection | Connect to any Navidrome/Subsonic server with URL + credentials |
| F-02 | Library browsing | Browse by Artists, Albums, Songs, Genres |
| F-03 | Search | Full-text search across library |
| F-04 | Playback | Play, pause, skip, seek, volume control |
| F-05 | Queue | View and reorder playback queue |
| F-06 | Shuffle & Repeat | All repeat modes; shuffle queue |
| F-07 | Album art | High-res cover art display |
| F-08 | Now Playing | Persistent mini-player + full Now Playing view |
| F-09 | Playlists | Browse, create, edit, delete playlists |
| F-10 | Starred / Favorites | Star songs, albums, artists; browse starred |
| F-11 | macOS media keys | Play/pause/next/prev via hardware keys and Touch Bar |
| F-12 | Menu bar integration | Mini-player in menu bar, optional |
| F-13 | Track caching | Cache streamed tracks to disk for offline playback |
| F-14 | Scrobbling | Last.fm scrobbling with real-time now-playing updates |
| F-15 | Last.fm stats | View listening stats: recent scrobbles, top tracks/artists/albums with time period filtering |

### 6.2 Enhanced (Should Have — v1.1)

| ID | Feature |
|---|---|
| F-16 | Home screen with recents, most played, random albums |
| F-17 | Multiple sort/filter options per view |
| F-18 | Keyboard shortcuts (full set) |
| F-19 | Lyrics display (synced if available) |
| F-20 | ReplayGain / volume normalization |
| F-21 | Podcast support |

---

## 7. User Stories

- As a user, I can add my Navidrome server so I can access my library.
- As a user, I can browse albums by artist so I can find music I know.
- As a user, I can search for any track, album, or artist instantly.
- As a user, I can control playback from the macOS lock screen and via media keys.
- As a user, I can queue up albums and reorder tracks before they play.
- As a user, I can star tracks so my favorites sync back to Navidrome.
- As a user, I can listen while offline if I have cached tracks.

---

## 8. Success Metrics

- App Store rating ≥ 4.5 stars
- Cold launch < 2 seconds on M-series Mac
- Memory footprint < 150 MB at idle
- No playback interruption during network hiccups (cache buffer)

---

## 9. Constraints

- macOS 14 (Sonoma) minimum deployment target
- SwiftUI + AVFoundation (no third-party audio engine)
- Subsonic API v1.16.1 compatibility
- Keychain for credential storage (no plaintext)

---

## 10. Timeline

| Milestone | Target | Status |
|---|---|---|
| v0.1 — Playback + Browse | Week 2 | ✅ Complete |
| v0.2 — Playlists + Queue | Week 3 | ✅ Complete |
| v0.3 — Cache + Last.fm Integration | Week 4 | ✅ Complete |
| v0.4 — Last.fm Stats Dashboard | Week 5 | ✅ Complete |
| v1.0 — Polish + Testing + Release | Week 7 | In Progress |
