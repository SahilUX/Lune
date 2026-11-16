import Foundation

/// Tracks kept on disk so replaying them needs no network. A track is added in the
/// background once the listener has stayed with it for a few seconds (see `PlayerEngine`),
/// and the least recently played ones are dropped when the size limit is reached.
actor TrackCache {
    static let shared = TrackCache()

    private let cacheDir: URL
    private var downloading: Set<String> = []

    /// Size limit from Settings. Defaults to 2 GB; 0 means unlimited.
    private var maxBytes: Int64? {
        let gb = UserDefaults.standard.object(forKey: "cacheSizeGB") as? Int ?? 2
        return gb > 0 ? Int64(gb) * 1024 * 1024 * 1024 : nil
    }

    init(directory: URL? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDir = directory ?? appSupport.appendingPathComponent("Lune/TrackCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// The cached file for `song`, if it has one. Counts as a play for eviction order.
    func cachedURL(for song: Song) -> URL? {
        let file = fileURL(for: song)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return file
    }

    /// Downloads `song` into the cache. Safe to call repeatedly; does nothing if the track is
    /// already cached or being fetched, and stops if the calling task is cancelled.
    func cache(song: Song) async {
        let file = fileURL(for: song)
        let name = file.lastPathComponent
        guard !FileManager.default.fileExists(atPath: file.path), downloading.insert(name).inserted else { return }
        defer { downloading.remove(name) }

        guard let url = try? SubsonicClient.shared.streamURL(songId: song.id),
              let (temp, response) = try? await TrustedSession.shared.download(from: url) else { return }
        defer { try? FileManager.default.removeItem(at: temp) }

        // The server answers errors with a 200 and a JSON/XML body, so check what came back.
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
        let type = (http.mimeType ?? "").lowercased()
        guard !(type.hasPrefix("text/") || type.contains("json") || type.contains("xml")) else { return }

        // Only keep a complete file: it must be the size the server says the track is.
        let size = Int64((try? temp.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard size > 0 else { return }
        if let expected = song.size, abs(size - expected) > max(expected / 50, 4096) { return }

        do {
            try FileManager.default.moveItem(at: temp, to: file)
        } catch {
            return
        }
        prune(keeping: file)
    }

    /// Bytes currently used by cached tracks.
    func totalBytes() -> Int64 {
        entries().reduce(0) { $0 + $1.size }
    }

    /// Deletes every cached track.
    func clear() {
        for entry in entries() { try? FileManager.default.removeItem(at: entry.url) }
    }

    // MARK: - Private

    private func fileURL(for song: Song) -> URL {
        // Namespaced per server so two servers that reuse an ID never share a file.
        let id = song.id.replacingOccurrences(of: "/", with: "_")
        return cacheDir.appendingPathComponent("\(SubsonicClient.shared.cacheNamespace)_\(id).\(song.suffix ?? "mp3")")
    }

    private func entries() -> [(url: URL, size: Int64, modified: Date)] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: keys)) ?? []
        return files.map {
            let values = try? $0.resourceValues(forKeys: Set(keys))
            return ($0, Int64(values?.fileSize ?? 0), values?.contentModificationDate ?? .distantPast)
        }
    }

    /// Drops the least recently played tracks until the cache fits its limit.
    private func prune(keeping keep: URL) {
        guard let limit = maxBytes else { return }
        var all = entries()
        var total = all.reduce(0) { $0 + $1.size }
        guard total > limit else { return }
        all.sort { $0.modified < $1.modified }
        for entry in all where total > limit && entry.url != keep {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}
