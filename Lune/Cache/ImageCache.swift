import AppKit
import SwiftUI

actor ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, NSImage>()
    private let diskDir: URL
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private var writesSincePrune = 0

    /// Artwork on disk is kept under this size; the oldest files go first.
    private static let maxDiskBytes: Int64 = 500 * 1024 * 1024

    init() {
        // Bound by decoded size, not count: an 800px cover is about 2.5 MB in memory.
        memory.totalCostLimit = 128 * 1024 * 1024
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Lune/ArtCache", isDirectory: true)
        diskDir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Task.detached(priority: .utility) { Self.pruneDisk(in: dir) }
    }

    func image(for id: String, size: Int = 300) async -> NSImage? {
        // Namespaced per server so two servers that reuse a cover ID never share a file.
        let name = "\(SubsonicClient.shared.cacheNamespace)_\(id)_\(size)"
        let key = name as NSString

        if let cached = memory.object(forKey: key) { return cached }
        // Many views ask for the same cover at once; share one load between them.
        if let running = inFlight[name] { return await running.value }

        let dir = diskDir
        let task = Task.detached(priority: .userInitiated) {
            await Self.load(name: name, id: id, size: size, diskDir: dir)
        }
        inFlight[name] = task
        let img = await task.value
        inFlight[name] = nil

        if let img {
            memory.setObject(img, forKey: key, cost: Self.cost(of: img))
            writesSincePrune += 1
            if writesSincePrune >= 100 {
                writesSincePrune = 0
                let dir = diskDir
                Task.detached(priority: .utility) { Self.pruneDisk(in: dir) }
            }
        }
        return img
    }

    /// Forgets every cached cover, in memory and on disk.
    func clear() {
        memory.removeAllObjects()
        let files = (try? FileManager.default.contentsOfDirectory(at: diskDir, includingPropertiesForKeys: nil)) ?? []
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    // MARK: - Loading (off the actor, so decoding never blocks other lookups)

    private static func load(name: String, id: String, size: Int, diskDir: URL) async -> NSImage? {
        let diskFile = diskDir.appendingPathComponent("\(name).jpg")
        if let data = try? Data(contentsOf: diskFile), let img = decode(data, maxPixel: size) {
            return img
        }
        guard let url = try? SubsonicClient.shared.coverArtURL(id: id, size: size),
              let (data, response) = try? await TrustedSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let img = decode(data, maxPixel: size) else { return nil }
        try? data.write(to: diskFile, options: .atomic)
        return img
    }

    /// Decodes now, at the size asked for. `NSImage(data:)` defers decoding to the first
    /// draw, which lands on the main thread in the middle of scrolling.
    private static func decode(_ data: Data, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixel, 1),
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private static func cost(of image: NSImage) -> Int {
        Int(image.size.width * image.size.height) * 4
    }

    private static func pruneDisk(in dir: URL) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return }
        var entries: [(url: URL, size: Int64, modified: Date)] = files.map {
            let values = try? $0.resourceValues(forKeys: Set(keys))
            return ($0, Int64(values?.fileSize ?? 0), values?.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > maxDiskBytes else { return }
        entries.sort { $0.modified < $1.modified }
        for entry in entries where total > maxDiskBytes {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}

struct AsyncArtwork: View {
    let coverArtId: String?
    var size: Int = 300
    var cornerRadius: CGFloat = 8

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.quaternary)
                    .overlay { Image(systemName: "music.note").foregroundStyle(.tertiary) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: coverArtId) {
            guard let id = coverArtId else { return }
            image = await ImageCache.shared.image(for: id, size: size)
        }
    }
}
