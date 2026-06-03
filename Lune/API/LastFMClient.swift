import Foundation
import AppKit
import CryptoKit

actor LastFMClient {
    static let shared = LastFMClient()

    private let apiKey = LastFMSecrets.apiKey
    private let apiSecret = LastFMSecrets.apiSecret
    private let baseURL = "https://ws.audioscrobbler.com/2.0/"
    private var isAuthenticating = false

    var sessionKey: String? {
        get { UserDefaults.standard.string(forKey: "lastfmSessionKey") }
        set { UserDefaults.standard.set(newValue, forKey: "lastfmSessionKey") }
    }

    var username: String? {
        get { UserDefaults.standard.string(forKey: "lastfmUsername") }
        set { UserDefaults.standard.set(newValue, forKey: "lastfmUsername") }
    }

    var isAuthenticated: Bool {
        sessionKey != nil && username != nil
    }

    // MARK: - Auth Flow

    func getToken() async throws -> String {
        guard !isAuthenticating else { return "" }
        isAuthenticating = true
        defer { isAuthenticating = false }

        var params: [String: String] = [
            "method": "auth.getToken",
            "api_key": apiKey,
            "format": "json"
        ]
        params["api_sig"] = sign(params, secret: apiSecret)

        let response = try await makeRequest(params, method: "POST")
        guard let token = response["token"] as? String else {
            throw LastFMError.missingToken
        }
        return token
    }

    func openAuthPage(token: String) {
        let urlString = "https://www.last.fm/api/auth/?api_key=\(apiKey)&token=\(token)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    func getSession(token: String) async throws {
        var params: [String: String] = [
            "method": "auth.getSession",
            "token": token,
            "api_key": apiKey,
            "format": "json"
        ]
        params["api_sig"] = sign(params, secret: apiSecret)

        let response = try await makeRequest(params, method: "POST")
        guard let session = response["session"] as? [String: Any],
              let sessionKey = session["key"] as? String,
              let username = session["name"] as? String else {
            throw LastFMError.invalidSession
        }

        self.sessionKey = sessionKey
        self.username = username
    }

    func disconnect() async {
        sessionKey = nil
        username = nil
    }

    // MARK: - Scrobbling

    func updateNowPlaying(song: Song) {
        guard let sessionKey = UserDefaults.standard.string(forKey: "lastfmSessionKey"),
              UserDefaults.standard.bool(forKey: "lastfmEnabled") else { return }

        Task {
            await _updateNowPlaying(song: song, sessionKey: sessionKey)
        }
    }

    func scrobble(song: Song, startedAt: Date, duration: Int) {
        guard let sessionKey = UserDefaults.standard.string(forKey: "lastfmSessionKey"),
              UserDefaults.standard.bool(forKey: "lastfmEnabled") else { return }

        let elapsedSeconds = Int(Date().timeIntervalSince(startedAt))
        let minPlayedSeconds = min(duration / 2, 240) // 50% or 4 min

        guard elapsedSeconds >= minPlayedSeconds else { return }

        Task {
            await _scrobble(song: song, startedAt: startedAt, sessionKey: sessionKey)
        }
    }

    // MARK: - Private

    private func _updateNowPlaying(song: Song, sessionKey: String) async {
        var params: [String: String] = [
            "method": "track.updateNowPlaying",
            "track": song.title,
            "artist": song.artist,
            "album": song.album,
            "duration": String(song.duration),
            "api_key": apiKey,
            "sk": sessionKey,
            "format": "json"
        ]
        params["api_sig"] = sign(params, secret: apiSecret)

        _ = try? await makeRequest(params, method: "POST")
    }

    private func _scrobble(song: Song, startedAt: Date, sessionKey: String) async {
        var params: [String: String] = [
            "method": "track.scrobble",
            "track": song.title,
            "artist": song.artist,
            "album": song.album,
            "timestamp": String(Int(startedAt.timeIntervalSince1970)),
            "api_key": apiKey,
            "sk": sessionKey,
            "format": "json"
        ]
        params["api_sig"] = sign(params, secret: apiSecret)

        _ = try? await makeRequest(params, method: "POST")
    }

    private func makeRequest(
        _ params: [String: String],
        method: String
    ) async throws -> [String: Any] {
        var components = URLComponents(string: baseURL)!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LastFMError.decodingFailed
        }

        if let error = json["error"] as? Int {
            throw LastFMError.apiError(code: error, message: json["message"] as? String ?? "Unknown")
        }

        return json
    }

    private func sign(_ params: [String: String], secret: String) -> String {
        let sorted = params
            .filter { $0.key != "format" && $0.key != "callback" }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)\($0.value)" }
            .joined()

        let toSign = sorted + secret
        let digest = Insecure.MD5.hash(data: toSign.data(using: .utf8) ?? Data())
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}

enum LastFMError: Error, LocalizedError {
    case missingToken
    case invalidSession
    case decodingFailed
    case apiError(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Failed to obtain Last.fm token"
        case .invalidSession:
            return "Failed to create Last.fm session"
        case .decodingFailed:
            return "Failed to decode Last.fm response"
        case .apiError(let code, let message):
            return "Last.fm error \(code): \(message)"
        }
    }
}
