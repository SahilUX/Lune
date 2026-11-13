import Foundation

actor LyricsService {
    static let shared = LyricsService()

    /// A cached `nil` means the server has no lyrics for the track, so replaying it
    /// doesn't repeat the lookups. Failed lookups are not cached.
    private var cache: [String: LyricsData?] = [:]
    private var inFlight: [String: Task<Fetched, Never>] = [:]
    private static let maxCached = 200

    private struct Fetched: Sendable {
        let lyrics: LyricsData?
        /// False when a request failed, so the result may be wrong and shouldn't stick.
        let cacheable: Bool
    }

    func lyrics(for song: Song) async -> LyricsData? {
        if let hit = cache[song.id] { return hit }
        // Share one lookup between callers asking for the same track at once.
        if let running = inFlight[song.id] { return await running.value.lyrics }

        let task = Task { await Self.fetch(song: song) }
        inFlight[song.id] = task
        let result = await task.value
        inFlight[song.id] = nil

        if result.cacheable {
            if cache.count >= Self.maxCached { cache.removeAll() }
            cache[song.id] = .some(result.lyrics)
        }
        return result.lyrics
    }

    private static func fetch(song: Song) async -> Fetched {
        var failed = false

        // Try structured lyrics first
        do {
            let structured = try await SubsonicClient.shared.getLyricsBySongId(songId: song.id)
            let lines = structured.lines
                .map { LyricsLine(text: $0.text.trimmingCharacters(in: .whitespaces), startMs: $0.startMs) }
                // Unsynced lines have no timing, so blank ones are only noise.
                .filter { structured.synced || !$0.text.isEmpty }
            if !lines.isEmpty {
                return Fetched(lyrics: LyricsData(lines: lines, isSynced: structured.synced), cacheable: true)
            }
        } catch {
            failed = true
        }

        // Fall back to plain text
        do {
            let plain = try await SubsonicClient.shared.getLyrics(artist: song.artist, title: song.title)
            let lines = plain
                .components(separatedBy: "\n")
                .map { LyricsLine(text: $0.trimmingCharacters(in: .whitespaces), startMs: 0) }
                .filter { !$0.text.isEmpty }
            if !lines.isEmpty {
                return Fetched(lyrics: LyricsData(lines: lines, isSynced: false), cacheable: true)
            }
        } catch {
            failed = true
        }

        return Fetched(lyrics: nil, cacheable: !failed)
    }
}
