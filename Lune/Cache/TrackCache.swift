import Foundation

actor TrackCache {
    static let shared = TrackCache()

    private let cacheDir: URL
    private let maxBytes: Int64 = 2 * 1024 * 1024 * 1024  // 2 GB default

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDir = appSupport.appendingPathComponent("Lune/TrackCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func cachedURL(for song: Song) -> URL? {
        let file = cacheDir.appendingPathComponent(cacheFileName(for: song))
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    func store(data: Data, for song: Song) {
        let file = cacheDir.appendingPathComponent(cacheFileName(for: song))
        try? data.write(to: file, options: .atomic)
        pruneIfNeeded()
    }

    /// Deletes every cached track.
    func clear() {
        let files = (try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)) ?? []
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    private func cacheFileName(for song: Song) -> String {
        let ext = song.suffix ?? "mp3"
        return "\(song.id).\(ext)"
    }

    private func pruneIfNeeded() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey]
        ) else { return }

        var total: Int64 = 0
        var files: [(url: URL, size: Int64, accessed: Date)] = []

        for url in contents {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentAccessDateKey])
            let size = Int64(values?.fileSize ?? 0)
            let accessed = values?.contentAccessDate ?? .distantPast
            total += size
            files.append((url, size, accessed))
        }

        guard total > maxBytes else { return }

        let sorted = files.sorted { $0.accessed < $1.accessed }
        var freed: Int64 = 0
        let target = total - maxBytes

        for file in sorted {
            try? FileManager.default.removeItem(at: file.url)
            freed += file.size
            if freed >= target { break }
        }
    }
}
