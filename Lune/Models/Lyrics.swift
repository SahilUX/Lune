import Foundation

struct LyricsLine: Identifiable {
    let id = UUID()
    let text: String
    let startMs: Int  // 0 for unsynced lines
}

struct LyricsData {
    let lines: [LyricsLine]
    let isSynced: Bool

    var isEmpty: Bool { lines.isEmpty }

    /// Returns the line active at `seconds`, nil if unsynced or before first line
    func currentLine(at seconds: Double) -> LyricsLine? {
        guard isSynced else { return lines.first }
        let ms = Int(seconds * 1000)
        var active: LyricsLine? = nil
        for line in lines {
            if line.startMs <= ms { active = line } else { break }
        }
        return active
    }

    /// Full text of the current synced line. Returns nil for unsynced lyrics.
    func snippet(at seconds: Double) -> String? {
        guard isSynced, let line = currentLine(at: seconds), !line.text.isEmpty else { return nil }
        return line.text
    }
}
