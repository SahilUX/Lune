import Foundation
import CryptoKit
import os

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

    /// Server endpoints and which one is currently working. Kept behind a lock (not as actor
    /// state) so streaming and artwork URLs, which are built outside the actor, always see
    /// the endpoint the API calls settled on, and never race a reconfiguration.
    private struct Endpoints: Sendable {
        var primary: SubsonicURLBuilder?
        var remote: SubsonicURLBuilder?
        var preferRemote = false
        var remoteSince: Date?
        var namespace = ""

        var active: SubsonicURLBuilder? { preferRemote ? (remote ?? primary) : primary }
    }

    private let endpoints = OSAllocatedUnfairLock(initialState: Endpoints())

    /// While on the remote endpoint, how long to wait before probing the local one again.
    private static let localRetryInterval: TimeInterval = 300

    func configure(config: ServerConfig, password: String) {
        // Try local URL first, fall back to remote
        let primaryURL = config.localURL ?? config.remoteURL ?? ""
        let primaryBuilder = SubsonicURLBuilder(serverURL: primaryURL, username: config.username, password: password)

        // Store remote builder for fallback if local is available
        let remoteBuilder: SubsonicURLBuilder? = {
            guard let remoteURL = config.remoteURL, remoteURL != primaryURL else { return nil }
            return SubsonicURLBuilder(serverURL: remoteURL, username: config.username, password: password)
        }()

        // Cached files are keyed by this, so two servers that reuse an ID never share an entry.
        let identity = "\(config.remoteURL ?? primaryURL)|\(config.username)"
        let namespace = SHA256.hash(data: Data(identity.utf8)).prefix(6)
            .map { String(format: "%02x", $0) }.joined()

        endpoints.withLock {
            $0 = Endpoints(primary: primaryBuilder, remote: remoteBuilder, namespace: namespace)
        }
    }

    /// Stable per-server prefix for cache keys.
    nonisolated var cacheNamespace: String { endpoints.withLock { $0.namespace } }

    // MARK: - URL Building (nonisolated — for streaming / art in sync contexts)

    nonisolated func streamURL(songId: String, maxBitRate: Int? = nil, format: String? = nil) throws -> URL {
        guard let b = endpoints.withLock({ $0.active }) else { throw APIError.notConfigured }
        var params = [URLQueryItem(name: "id", value: songId)]
        if let maxBitRate, maxBitRate > 0 { params.append(URLQueryItem(name: "maxBitRate", value: "\(maxBitRate)")) }
        if let format, !format.isEmpty { params.append(URLQueryItem(name: "format", value: format)) }
        return try b.buildURL(endpoint: "stream", params: params)
    }

    nonisolated func coverArtURL(id: String, size: Int = 300) throws -> URL {
        guard let b = endpoints.withLock({ $0.active }) else { throw APIError.notConfigured }
        return try b.buildURL(endpoint: "getCoverArt", params: [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "size", value: "\(size)"),
        ])
    }

    // MARK: - Fetch helper with fallback

    private func fetch<T: Decodable>(_ endpoint: String, params: [URLQueryItem] = []) async throws -> T {
        let snapshot = endpoints.withLock { $0 }
        guard let primary = snapshot.primary else { throw APIError.notConfigured }
        guard let remote = snapshot.remote else {
            return try await fetchWithBuilder(primary, endpoint: endpoint, params: params)
        }

        // Once on the remote endpoint, stay there for a while before probing local again.
        if snapshot.preferRemote,
           Date().timeIntervalSince(snapshot.remoteSince ?? .distantPast) < Self.localRetryInterval {
            return try await fetchWithBuilder(remote, endpoint: endpoint, params: params)
        }

        do {
            let result: T = try await fetchWithBuilder(primary, endpoint: endpoint, params: params)
            if snapshot.preferRemote {
                endpoints.withLock { $0.preferRemote = false; $0.remoteSince = nil }
            }
            return result
        } catch {
            // A cancelled request must not spawn a second one against the remote server.
            if Task.isCancelled || error is CancellationError { throw error }
            do {
                let result: T = try await fetchWithBuilder(remote, endpoint: endpoint, params: params)
                endpoints.withLock { $0.preferRemote = true; $0.remoteSince = Date() }
                return result
            } catch let remoteError {
                // Remote also failed. A certificate problem on the primary is
                // the one the user can act on, so report it over a generic failure.
                throw error is UntrustedCertificate && !(remoteError is UntrustedCertificate) ? error : remoteError
            }
        }
    }

    private func fetchWithBuilder<T: Decodable>(_ builder: SubsonicURLBuilder?, endpoint: String, params: [URLQueryItem] = []) async throws -> T {
        guard let builder = builder else { throw APIError.notConfigured }
        let url = try builder.buildURL(endpoint: endpoint, params: params)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await TrustedSession.shared.data(from: url)
        } catch {
            throw ServerTrust.shared.mapError(error, host: url.host)
        }
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

    /// Structured lyrics for a song. `synced` is false when the server only has plain text,
    /// in which case the lines carry no timestamps.
    func getLyricsBySongId(songId: String) async throws -> (lines: [LyricsLine], synced: Bool) {
        let result: LyricsListResult = try await fetch("getLyricsBySongId",
            params: [URLQueryItem(name: "id", value: songId)])
        let all = result.lyricsList.structuredLyrics ?? []
        // Prefer a synced version when the server has several.
        guard let structured = all.first(where: { $0.synced && !($0.line ?? []).isEmpty }) ?? all.first,
              let lines = structured.line else { return ([], false) }
        let mapped = lines.map { LyricsLine(text: $0.value, startMs: structured.synced ? ($0.start ?? 0) : 0) }
        return (mapped, structured.synced)
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
