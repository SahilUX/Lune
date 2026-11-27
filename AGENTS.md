# Lune

A native macOS music client for Navidrome and other Subsonic servers, with Last.fm scrobbling. Swift 6, SwiftUI, macOS 14+. The Xcode project is `Lune.xcodeproj`, generated from `project.yml` with XcodeGen and committed. Everything is in one app target, `Lune`; there are no third-party dependencies.

See `README.md` for features and setup, `DESIGN.md` for the UI reference, and `PRD.md` and `BRD.md` for the requirements (parts of `HANDOFF.md`, `PRD.md` and `BRD.md` predate the 1.0 release).

## Layout

- `Lune/API/`: Subsonic and Last.fm clients, lyrics, TLS certificate pinning (`ServerTrust.swift`, `PinnedAssetLoader.swift`).
- `Lune/Audio/`: playback engine, queue and Now Playing integration.
- `Lune/Cache/`: offline track cache and image cache.
- `Lune/Persistence/`: the library store and Keychain access (settings live in `UserDefaults`).
- `Lune/Models/`, `Lune/Components/`, `Lune/Utilities/`, `Lune/Views/`: models, shared UI and the screens.
- `scripts/release.sh`: builds a notarized DMG (see "Releasing").

## Build and test

Xcode builds only run on macOS. The commands below are for a Mac with Xcode (`project.yml` sets Xcode 16 as the minimum).

1. Copy `Lune/Config/Secrets.swift.template` to `Lune/Config/Secrets.swift`. The file is gitignored. Placeholder keys are enough to compile; real Last.fm keys are only needed to scrobble.
2. Build:

   ```sh
   xcodebuild -project Lune.xcodeproj -scheme Lune -configuration Debug CODE_SIGNING_ALLOWED=NO build
   ```

   Verified 2026-11-27 on macOS 27.0.1 with Xcode 27.2 from a fresh clone: `BUILD SUCCEEDED` in about 22 seconds with no signing setup. (Add `-derivedDataPath <dir>` to keep the build products out of Xcode's shared DerivedData.) Building from Xcode with Cmd+B also works.
3. Tests: there is no test target. `xcodebuild ... test` fails with "Scheme Lune is not currently configured for the test action". Check a change by building and by using the app against a Navidrome server.

If you change `project.yml`, run `xcodegen generate` and commit the regenerated `Lune.xcodeproj` and `Lune/Info.plist`. The app version (`CFBundleShortVersionString`, `CFBundleVersion`) is set in `project.yml`; editing the plist alone gets reset. `xcodegen generate` itself was not run while writing this file.

## Conventions

- Swift 6 strict concurrency: mark UI types `@MainActor`, keep shared state in actors or `@Observable` types, and avoid `@unchecked Sendable` and `nonisolated(unsafe)` (the certificate-pinning code uses the former; don't add more without a comment saying why).
- SwiftUI for all UI. No third-party packages; use system frameworks.
- Credentials go in the Keychain, never in `UserDefaults` or source. Never commit `Lune/Config/Secrets.swift`.
- Certificate trust is pinned per host, with normal TLS checks everywhere else. Don't add a code path that accepts any certificate.
- Stored data (UserDefaults keys, Keychain items, the track cache layout) is read by every installed version. Changing it needs a migration.
- Branch from `main`, keep commits focused, and open a pull request.

## Releasing

`scripts/release.sh` builds a signed, notarized Developer ID DMG; `README.md` ("Releasing") has the steps and prerequisites. It needs the maintainer's signing certificate and notarytool profile, so it only runs on the maintainer's Mac.
