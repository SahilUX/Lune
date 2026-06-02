import AppKit
import SwiftUI

actor ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, NSImage>()
    private let diskDir: URL

    init() {
        memory.countLimit = 200
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        diskDir = appSupport.appendingPathComponent("Lune/ArtCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
    }

    func image(for id: String, size: Int = 300) async -> NSImage? {
        let key = "\(id)_\(size)" as NSString

        if let cached = memory.object(forKey: key) { return cached }

        let diskFile = diskDir.appendingPathComponent("\(id)_\(size).jpg")
        if let data = try? Data(contentsOf: diskFile), let img = NSImage(data: data) {
            memory.setObject(img, forKey: key)
            return img
        }

        guard let url = try? SubsonicClient.shared.coverArtURL(id: id, size: size),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let img = NSImage(data: data) else { return nil }

        memory.setObject(img, forKey: key)
        try? data.write(to: diskFile)
        return img
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
