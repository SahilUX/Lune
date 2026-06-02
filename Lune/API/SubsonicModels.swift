import Foundation

// MARK: - Envelope

struct SubsonicEnvelope<T: Decodable>: Decodable {
    let subsonicResponse: SubsonicResponse<T>
    enum CodingKeys: String, CodingKey { case subsonicResponse = "subsonic-response" }
}

struct SubsonicResponse<T: Decodable>: Decodable {
    let status: String
    let version: String
    let error: SubsonicError?
    let data: T?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
        status = try container.decode(String.self, forKey: .init(stringValue: "status"))
        version = try container.decode(String.self, forKey: .init(stringValue: "version"))
        error = try container.decodeIfPresent(SubsonicError.self, forKey: .init(stringValue: "error"))
        data = try? T(from: decoder)
    }
}

struct SubsonicError: Codable {
    let code: Int
    let message: String
}

struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.intValue = intValue; self.stringValue = "\(intValue)" }
}

// MARK: - Response Types

struct ArtistsResult: Decodable {
    let artists: ArtistsIndex
}

struct ArtistsIndex: Decodable {
    let index: [ArtistIndexEntry]
    enum CodingKeys: String, CodingKey { case index }
}

struct ArtistIndexEntry: Decodable {
    let name: String
    let artist: [Artist]
}

struct ArtistResult: Decodable {
    let artist: Artist
}

struct AlbumResult: Decodable {
    let album: Album
}

struct AlbumListResult: Decodable {
    let albumList2: AlbumList2
}

struct AlbumList2: Decodable {
    let album: [Album]?
}

struct PlaylistsResult: Decodable {
    let playlists: PlaylistList
}

struct PlaylistList: Decodable {
    let playlist: [Playlist]?
}

struct PlaylistResult: Decodable {
    let playlist: Playlist
}

struct SearchResult3: Decodable {
    let searchResult3: SearchResults3Inner
}

struct SearchResults3Inner: Decodable {
    let artist: [Artist]?
    let album: [Album]?
    let song: [Song]?
}

struct EmptyResult: Decodable {}

struct LyricsListResult: Decodable {
    let lyricsList: LyricsList
}

struct LyricsList: Decodable {
    let structuredLyrics: [StructuredLyrics]?
}

struct StructuredLyrics: Decodable {
    let synced: Bool
    let line: [LyricLineDTO]?
}

struct LyricLineDTO: Decodable {
    let value: String
    let start: Int?
}

struct LyricsResult: Decodable {
    let lyrics: PlainLyrics
}

struct PlainLyrics: Decodable {
    let value: String?
    // Subsonic returns lyrics as {"artist":"..","title":"..","value":"text"}
    enum CodingKeys: String, CodingKey { case value }
}

struct Starred2Result: Decodable {
    let starred2: Starred2Inner
}

struct Starred2Inner: Decodable {
    let song: [Song]?
    let album: [Album]?
    let artist: [Artist]?
}

// MARK: - Model Decodable Conformance

extension Song {
    enum CodingKeys: String, CodingKey {
        case id, title, artist, album, albumId = "albumId"
        case duration, trackNumber = "track", discNumber = "discNumber"
        case year, coverArtId = "coverArt"
        case contentType, suffix
        case transcodedSuffix, transcodedContentType
        case bitRate, size
        case isStarred = "starred"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? "Unknown Artist"
        album = try c.decodeIfPresent(String.self, forKey: .album) ?? "Unknown Album"
        albumId = try c.decodeIfPresent(String.self, forKey: .albumId) ?? ""
        duration = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 0
        trackNumber = try c.decodeIfPresent(Int.self, forKey: .trackNumber)
        discNumber = try c.decodeIfPresent(Int.self, forKey: .discNumber)
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        coverArtId = try c.decodeIfPresent(String.self, forKey: .coverArtId)
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType)
        suffix = try c.decodeIfPresent(String.self, forKey: .suffix)
        transcodedSuffix = try c.decodeIfPresent(String.self, forKey: .transcodedSuffix)
        transcodedContentType = try c.decodeIfPresent(String.self, forKey: .transcodedContentType)
        bitRate = try c.decodeIfPresent(Int.self, forKey: .bitRate)
        size = try c.decodeIfPresent(Int64.self, forKey: .size)
        isStarred = (try? c.decodeIfPresent(String.self, forKey: .isStarred)) != nil
    }
}

extension Album {
    enum CodingKeys: String, CodingKey {
        case id, name, artist, artistId
        case coverArtId = "coverArt"
        case songCount, duration, year, genre
        case isStarred = "starred"
        case songs = "song"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? "Unknown Artist"
        artistId = try c.decodeIfPresent(String.self, forKey: .artistId) ?? ""
        coverArtId = try c.decodeIfPresent(String.self, forKey: .coverArtId)
        songCount = try c.decodeIfPresent(Int.self, forKey: .songCount) ?? 0
        duration = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 0
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        genre = try c.decodeIfPresent(String.self, forKey: .genre)
        isStarred = (try? c.decodeIfPresent(String.self, forKey: .isStarred)) != nil
        songs = (try? c.decodeIfPresent([Song].self, forKey: .songs)) ?? []
    }
}

extension Artist {
    enum CodingKeys: String, CodingKey {
        case id, name, albumCount
        case coverArtId = "coverArt"
        case albums = "album"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        albumCount = try c.decodeIfPresent(Int.self, forKey: .albumCount) ?? 0
        coverArtId = try c.decodeIfPresent(String.self, forKey: .coverArtId)
        albums = (try? c.decodeIfPresent([Album].self, forKey: .albums)) ?? []
    }
}

extension Playlist {
    enum CodingKeys: String, CodingKey {
        case id, name, songCount, duration
        case coverArtId = "coverArt"
        case songs = "entry"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        songCount = try c.decodeIfPresent(Int.self, forKey: .songCount) ?? 0
        duration = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 0
        coverArtId = try c.decodeIfPresent(String.self, forKey: .coverArtId)
        songs = (try? c.decodeIfPresent([Song].self, forKey: .songs)) ?? []
    }
}
