import Foundation

// MARK: - Song Model

struct Song: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let albumId: String
    let duration: Int
    let trackNumber: Int?
    let discNumber: Int?
    let year: Int?
    let coverArtId: String?
    let contentType: String?
    let suffix: String?
    let transcodedSuffix: String?
    let transcodedContentType: String?
    let bitRate: Int?
    let size: Int64?
    var isStarred: Bool

    var formattedDuration: String {
        let m = duration / 60
        let s = duration % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct Album: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let artist: String
    let artistId: String
    let coverArtId: String?
    let songCount: Int
    let duration: Int
    let year: Int?
    let genre: String?
    var isStarred: Bool
    var songs: [Song]
}

struct Artist: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let albumCount: Int
    let coverArtId: String?
    var albums: [Album]
}

struct Playlist: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let songCount: Int
    let duration: Int
    let coverArtId: String?
    var songs: [Song]
}

struct Genre: Identifiable, Codable, Hashable {
    let id: String
    var name: String { id }
    let songCount: Int
    let albumCount: Int
}

struct SearchResult: Codable {
    let artists: [Artist]
    let albums: [Album]
    let songs: [Song]
}

struct ServerConfig: Codable {
    let localURL: String?      // Local network URL (e.g., http://192.168.1.100:4533)
    let remoteURL: String?     // Remote URL (e.g., https://music.example.com)
    let username: String
    // password retrieved from Keychain separately

    // For backwards compatibility, support old `url` field
    var url: String { localURL ?? remoteURL ?? "" }

    init(localURL: String? = nil, remoteURL: String? = nil, username: String) {
        self.localURL = localURL?.trimmingCharacters(in: .whitespaces).isEmpty == true ? nil : localURL
        self.remoteURL = remoteURL?.trimmingCharacters(in: .whitespaces).isEmpty == true ? nil : remoteURL
        self.username = username
    }

    // Backwards compatibility: init with single url parameter
    init(url: String, username: String) {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        self.localURL = trimmed.isEmpty ? nil : trimmed
        self.remoteURL = nil
        self.username = username
    }
}
