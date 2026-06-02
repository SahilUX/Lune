import Foundation

actor LyricsService {
    static let shared = LyricsService()
    private var cache: [String: LyricsData] = [:]

    func lyrics(for song: Song) async -> LyricsData? {
        if let cached = cache[song.id] { return cached }
        let data = await fetch(song: song)
        cache[song.id] = data  // cache even nil result (means "no lyrics")
        return data
    }

    private func fetch(song: Song) async -> LyricsData? {
        // Try synced lyrics first
        if let synced = try? await SubsonicClient.shared.getLyricsBySongId(songId: song.id),
           !synced.isEmpty {
            return LyricsData(lines: synced, isSynced: true)
        }
        // Fall back to plain text
        if let plain = try? await SubsonicClient.shared.getLyrics(artist: song.artist, title: song.title),
           !plain.isEmpty {
            let lines = plain
                .components(separatedBy: "\n")
                .map { LyricsLine(text: $0.trimmingCharacters(in: .whitespaces), startMs: 0) }
                .filter { !$0.text.isEmpty }
            return lines.isEmpty ? nil : LyricsData(lines: lines, isSynced: false)
        }
        return nil
    }
}
