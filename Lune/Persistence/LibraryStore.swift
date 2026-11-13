import Foundation
import Observation

@Observable
@MainActor
final class LibraryStore {
    static let shared: LibraryStore = {
        MainActor.assumeIsolated { LibraryStore() }
    }()

    var serverConfig: ServerConfig?
    var artists: [Artist] = []
    var albums: [Album] = []
    var songs: [Song] = []
    var starredSongs: [Song] = []
    var playlists: [Playlist] = []
    var isLoading = false
    var error: String?

    private init() {
        loadServerConfig()
    }

    // MARK: - Server Config

    func saveServerConfig(_ config: ServerConfig, password: String) {
        serverConfig = config
        let data = try! JSONEncoder().encode(config)
        UserDefaults.standard.set(data, forKey: "serverConfig")
        KeychainStore.store(password, for: .serverPassword)
        Task { await SubsonicClient.shared.configure(config: config, password: password) }
    }

    private func loadServerConfig() {
        guard let data = UserDefaults.standard.data(forKey: "serverConfig"),
              let config = try? JSONDecoder().decode(ServerConfig.self, from: data) else { return }
        serverConfig = config
        let password = KeychainStore.value(for: .serverPassword) ?? ""
        Task { await SubsonicClient.shared.configure(config: config, password: password) }
    }

    // MARK: - Library Loading

    func loadLibrary() async {
        guard serverConfig != nil else { return }
        await MainActor.run { isLoading = true; error = nil }
        do {
            async let artistsTask = SubsonicClient.shared.getArtists()
            async let albumsTask = SubsonicClient.shared.getAlbumList(type: .alphabeticalByName, size: 500)
            async let playlistsTask = SubsonicClient.shared.getPlaylists()
            async let songsTask = SubsonicClient.shared.getAllSongs()
            async let starredTask = SubsonicClient.shared.getStarred()
            let (a, al, pl, s, st) = try await (artistsTask, albumsTask, playlistsTask, songsTask, starredTask)
            await MainActor.run {
                artists = a
                albums = al
                playlists = pl
                songs = s
                starredSongs = st
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func refreshStarred() async {
        if let updated = try? await SubsonicClient.shared.getStarred() {
            await MainActor.run { starredSongs = updated }
        }
    }

    func refreshPlaylists() async {
        guard serverConfig != nil else { return }
        if let updated = try? await SubsonicClient.shared.getPlaylists() {
            await MainActor.run { playlists = updated }
        }
    }

}
