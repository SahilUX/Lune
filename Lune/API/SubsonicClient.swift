import Foundation
import CryptoKit

// Sendable value type used in nonisolated URL-building paths
struct SubsonicURLBuilder: Sendable {
    let serverURL: String
    let username: String
    let password: String
    let apiVersion = "1.16.1"
    let clientName = "Lune"

    func buildURL(endpoint: String, params: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(string: serverURL) else { throw APIError.invalidURL }
        let salt = "ln\(Int.random(in: 100000...999999))"
        let token = md5(password + salt)
        let auth = [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: apiVersion),
            URLQueryItem(name: "c", value: clientName),
            URLQueryItem(name: "f", value: "json"),
        ]
        components.path = "/rest/\(endpoint)"
        components.queryItems = auth + params
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }

    private func md5(_ string: String) -> String {
        Insecure.MD5.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

actor SubsonicClient {
    static let shared = SubsonicClient()

    private var urlBuilder: SubsonicURLBuilder?
    private var remoteBuilder: SubsonicURLBuilder?
    private var preferRemote = false  // Tracks if local failed and we switched to remote

    // Cached for nonisolated URL building
    nonisolated(unsafe) private var _urlBuilder: SubsonicURLBuilder?

    func configure(config: ServerConfig, password: String) {
        // Try local URL first, fall back to remote
        let primaryURL = config.localURL ?? config.remoteURL ?? ""
        let primaryBuilder = SubsonicURLBuilder(serverURL: primaryURL, username: config.username, password: password)
        urlBuilder = primaryBuilder
        _urlBuilder = primaryBuilder

        // Store remote builder for fallback if local is available
        if let remoteURL = config.remoteURL, remoteURL != primaryURL {
            remoteBuilder = SubsonicURLBuilder(serverURL: remoteURL, username: config.username, password: password)
        } else {
            remoteBuilder = nil
        }
        preferRemote = false
    }

    // MARK: - URL Building (isolated)

    private func url(endpoint: String, params: [URLQueryItem] = []) throws -> URL {
        guard let b = urlBuilder else { throw APIError.notConfigured }
        return try b.buildURL(endpoint: endpoint, params: params)
    }

    // MARK: - URL Building (nonisolated — for streaming / art in sync contexts)

    nonisolated func streamURL(songId: String, maxBitRate: Int? = nil, format: String? = nil) throws -> URL {
        guard let b = _urlBuilder else { throw APIError.notConfigured }
        var params = [URLQueryItem(name: "id", value: songId)]
        if let maxBitRate, maxBitRate > 0 { params.append(URLQueryItem(name: "maxBitRate", value: "\(maxBitRate)")) }
        if let format, !format.isEmpty { params.append(URLQueryItem(name: "format", value: format)) }
        return try b.buildURL(endpoint: "stream", params: params)
    }

    nonisolated func coverArtURL(id: String, size: Int = 300) throws -> URL {
        guard let b = _urlBuilder else { throw APIError.notConfigured }
        return try b.buildURL(endpoint: "getCoverArt", params: [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "size", value: "\(size)"),
        ])
    }

    // MARK: - Fetch helper with fallback

    private func fetch<T: Decodable>(_ endpoint: String, params: [URLQueryItem] = []) async throws -> T {
        // If we previously switched to remote, try remote first; otherwise try primary first
        if preferRemote, let remote = remoteBuilder {
            do {
                return try await fetchWithBuilder(remote, endpoint: endpoint, params: params)
            } catch {
                // Remote also failed, return the error
                throw error
            }
        }

        // Try primary URL
        do {
            return try await fetchWithBuilder(urlBuilder, endpoint: endpoint, params: params)
        } catch {
            // Primary failed; if we have a remote fallback and this was a network error, try it
            if let remote = remoteBuilder {
                do {
                    let result: T = try await fetchWithBuilder(remote, endpoint: endpoint, params: params)
                    preferRemote = true  // Successfully switched; prefer remote going forward
                    return result
                } catch {
                    // Remote also failed; return the original error
                    throw error
                }
            }
            // No fallback available
            throw error
        }
    }

    private func fetchWithBuilder<T: Decodable>(_ builder: SubsonicURLBuilder?, endpoint: String, params: [URLQueryItem] = []) async throws -> T {
        guard let builder = builder else { throw APIError.notConfigured }
        let url = try builder.buildURL(endpoint: endpoint, params: params)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let envelope = try JSONDecoder().decode(SubsonicEnvelope<T>.self, from: data)
        guard envelope.subsonicResponse.status == "ok" else {
            throw APIError.apiError(envelope.subsonicResponse.error?.message ?? "Unknown error")
        }
        guard let result = envelope.subsonicResponse.data else { throw APIError.decodingError }
        return result
    }

    // MARK: - Library

    func getArtists() async throws -> [Artist] {
        let result: ArtistsResult = try await fetch("getArtists")
        return result.artists.index.flatMap(\.artist)
    }

    func getArtist(id: String) async throws -> Artist {
        let result: ArtistResult = try await fetch("getArtist", params: [URLQueryItem(name: "id", value: id)])
        return result.artist
    }

    func getAlbum(id: String) async throws -> Album {
        let result: AlbumResult = try await fetch("getAlbum", params: [URLQueryItem(name: "id", value: id)])
        return result.album
    }

    func getAlbumList(type: AlbumListType = .alphabeticalByName, size: Int = 50, offset: Int = 0) async throws -> [Album] {
        let result: AlbumListResult = try await fetch("getAlbumList2", params: [
            URLQueryItem(name: "type", value: type.rawValue),
            URLQueryItem(name: "size", value: "\(size)"),
            URLQueryItem(name: "offset", value: "\(offset)"),
        ])
        return result.albumList2.album ?? []
    }

    func search(query: String) async throws -> SearchResult {
        let result: SearchResult3 = try await fetch("search3", params: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "artistCount", value: "5"),
            URLQueryItem(name: "albumCount", value: "5"),
            URLQueryItem(name: "songCount", value: "20"),
        ])
        return SearchResult(
            artists: result.searchResult3.artist ?? [],
            albums: result.searchResult3.album ?? [],
            songs: result.searchResult3.song ?? []
        )
    }

    func getAllSongs() async throws -> [Song] {
        var all: [Song] = []
        var offset = 0
        let pageSize = 500
        while true {
            let result: SearchResult3 = try await fetch("search3", params: [
                URLQueryItem(name: "query", value: ""),
                URLQueryItem(name: "artistCount", value: "0"),
                URLQueryItem(name: "albumCount", value: "0"),
                URLQueryItem(name: "songCount", value: "\(pageSize)"),
                URLQueryItem(name: "songOffset", value: "\(offset)"),
            ])
            let page = result.searchResult3.song ?? []
            all.append(contentsOf: page)
            if page.count < pageSize { break }
            offset += pageSize
        }
        return all.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func getStarred() async throws -> [Song] {
        let result: Starred2Result = try await fetch("getStarred2")
        return result.starred2.song ?? []
    }

    func getPlaylists() async throws -> [Playlist] {
        let result: PlaylistsResult = try await fetch("getPlaylists")
        return result.playlists.playlist ?? []
    }

    func getPlaylist(id: String) async throws -> Playlist {
        let result: PlaylistResult = try await fetch("getPlaylist", params: [URLQueryItem(name: "id", value: id)])
        return result.playlist
    }

    func createPlaylist(name: String, songIds: [String] = []) async throws {
        var params = [URLQueryItem(name: "name", value: name)]
        params += songIds.map { URLQueryItem(name: "songId", value: $0) }
        let _: EmptyResult = try await fetch("createPlaylist", params: params)
    }

    func deletePlaylist(id: String) async throws {
        let _: EmptyResult = try await fetch("deletePlaylist", params: [URLQueryItem(name: "id", value: id)])
    }

    func updatePlaylist(id: String, songIdsToAdd: [String]) async throws {
        var params = [URLQueryItem(name: "playlistId", value: id)]
        params += songIdsToAdd.map { URLQueryItem(name: "songIdToAdd", value: $0) }
        let _: EmptyResult = try await fetch("updatePlaylist", params: params)
    }

    func star(id: String) async throws {
        let _: EmptyResult = try await fetch("star", params: [URLQueryItem(name: "id", value: id)])
    }

    func unstar(id: String) async throws {
        let _: EmptyResult = try await fetch("unstar", params: [URLQueryItem(name: "id", value: id)])
    }

    func scrobble(id: String, submission: Bool = true) async throws {
        let _: EmptyResult = try await fetch("scrobble", params: [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "submission", value: submission ? "true" : "false"),
        ])
    }

    func ping() async throws {
        let _: EmptyResult = try await fetch("ping")
    }

    func getLyricsBySongId(songId: String) async throws -> [LyricsLine] {
        let result: LyricsListResult = try await fetch("getLyricsBySongId",
            params: [URLQueryItem(name: "id", value: songId)])
        guard let structured = result.lyricsList.structuredLyrics?.first,
              let lines = structured.line else { return [] }
        return lines.map { LyricsLine(text: $0.value, startMs: $0.start ?? 0) }
    }

    func getLyrics(artist: String, title: String) async throws -> String {
        let result: LyricsResult = try await fetch("getLyrics", params: [
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "title", value: title),
        ])
        return result.lyrics.value ?? ""
    }
}

enum AlbumListType: String {
    case random, newest, frequent, recent, starred, alphabeticalByName, alphabeticalByArtist
}

enum APIError: LocalizedError {
    case notConfigured
    case invalidURL
    case httpError(Int)
    case apiError(String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Server not configured"
        case .invalidURL: return "Invalid server URL"
        case .httpError(let code): return "HTTP error \(code)"
        case .apiError(let msg): return msg
        case .decodingError: return "Failed to decode server response"
        }
    }
}
