import SwiftUI

struct LastFMStatsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            Group {
                if LastFMClient.shared.sessionKey == nil {
                    ContentUnavailableView(
                        "Not Connected",
                        systemImage: "dot.radiowaves.left.and.right",
                        description: Text("Sign in to Last.fm in Settings to view your stats.")
                    )
                } else {
                    VStack(spacing: 0) {
                        // Tab switcher with toggle buttons
                        HStack(spacing: 8) {
                            TabToggleButton(label: "Recent", icon: "clock", isSelected: selectedTab == 0) {
                                selectedTab = 0
                            }
                            TabToggleButton(label: "Tracks", icon: "music.note", isSelected: selectedTab == 1) {
                                selectedTab = 1
                            }
                            TabToggleButton(label: "Artists", icon: "music.mic", isSelected: selectedTab == 2) {
                                selectedTab = 2
                            }
                            TabToggleButton(label: "Albums", icon: "square.stack", isSelected: selectedTab == 3) {
                                selectedTab = 3
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Divider()

                        // Tab content
                        Group {
                            switch selectedTab {
                            case 0: RecentScrobblesTab()
                            case 1: TopTracksTab()
                            case 2: TopArtistsTab()
                            default: TopAlbumsTab()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Last.fm")
            .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
            .navigationDestination(for: Artist.self) { artist in
                ArtistDetailView(artist: artist)
            }
        }
    }
}

struct TabToggleButton: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? .accentColor : nil)
        .opacity(isSelected ? 1 : 0.6)
    }
}

// MARK: - Recent Scrobbles

struct RecentScrobblesTab: View {
    @State private var tracks: [[String: Any]] = []
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ForEach(0..<10, id: \.self) { _ in
                        SkeletonScrobbleRow()
                    }
                }
                .padding()
            } else if tracks.isEmpty {
                ContentUnavailableView("No scrobbles yet", systemImage: "music.note")
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(tracks.indices, id: \.self) { index in
                            ScrobbleRow(track: tracks[index], isNowPlaying: index == 0 && tracks[index]["nowplaying"] != nil)
                        }
                    }
                    .padding()
                }
            }
        }
        .task {
            await loadTracks()
        }
    }

    private func loadTracks() async {
        isLoading = true
        do {
            tracks = try await LastFMClient.shared.getRecentTracks(limit: 50)
        } catch {
            print("[Last.fm] Failed to load recent tracks: \(error)")
        }
        isLoading = false
    }
}

struct ScrobbleRow: View {
    let track: [String: Any]
    let isNowPlaying: Bool
    @State private var selectedAlbum: Album?
    @Environment(LibraryStore.self) private var library

    var trackName: String {
        (track["name"] as? String) ?? "Unknown"
    }

    var artistName: String {
        if let artist = track["artist"] as? [String: Any],
           let name = artist["#text"] as? String {
            return name
        }
        return "Unknown Artist"
    }

    var timestamp: String {
        if let date = track["date"] as? [String: Any],
           let timestamp = date["#text"] as? String {
            return timestamp
        }
        return ""
    }

    var imageURL: URL? {
        if let images = track["image"] as? [[String: Any]] {
            // Try sizes in order: extralarge, large, medium, small
            let preferredSizes = ["extralarge", "large", "medium", "small"]
            for size in preferredSizes {
                for image in images {
                    if let imageSize = image["size"] as? String,
                       imageSize == size,
                       let url = image["#text"] as? String,
                       !url.isEmpty {
                        return URL(string: url)
                    }
                }
            }
        }
        return nil
    }

    var body: some View {
        NavigationLink(value: selectedAlbum) {
            HStack(spacing: 12) {
                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Image(systemName: "music.note")
                                .foregroundStyle(.secondary)
                        case .empty:
                            SkeletonView()
                        @unknown default:
                            SkeletonView()
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipped()
                    .cornerRadius(4)
                } else {
                    Image(systemName: "music.note")
                        .frame(width: 40, height: 40)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(trackName)
                            .font(.body)
                            .lineLimit(1)
                        if isNowPlaying {
                            Text("Now Playing")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    Text(artistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !timestamp.isEmpty {
                        Text(timestamp)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .task {
            await searchAndNavigate()
        }
    }

    private func searchAndNavigate() async {
        do {
            var result = try await SubsonicClient.shared.search(query: "\(trackName) \(artistName)")

            // If no results and artist is "Unknown", try just the track name
            if result.albums.isEmpty && artistName == "Unknown" {
                result = try await SubsonicClient.shared.search(query: trackName)
            }

            selectedAlbum = result.albums.first
            if selectedAlbum != nil && imageURL != nil {
                print("[Last.fm] Found album for: \(trackName)")
            }
        } catch {
            print("[Last.fm] Failed to search album: \(error)")
        }
    }
}

struct SkeletonScrobbleRow: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonView()
                .frame(width: 40, height: 40)
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 6) {
                SkeletonView()
                    .frame(height: 14)
                    .frame(maxWidth: 150)
                SkeletonView()
                    .frame(height: 12)
                    .frame(maxWidth: 120)
            }

            Spacer()
        }
    }
}

// MARK: - Top Tracks

struct TopTracksTab: View {
    @State private var period: LastFMPeriod = .month
    @State private var tracks: [[String: Any]] = []
    @State private var isLoading = false

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]

    var body: some View {
        VStack(spacing: 0) {
            Picker("Period", selection: $period) {
                ForEach(LastFMPeriod.allCases, id: \.self) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            ScrollView {
                if isLoading {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(0..<12, id: \.self) { _ in
                            SkeletonGridCard()
                        }
                    }
                    .padding(20)
                } else if tracks.isEmpty {
                    ContentUnavailableView("No data", systemImage: "chart.bar")
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(tracks.indices, id: \.self) { index in
                            TopTrackCard(track: tracks[index], rank: index + 1)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .task(id: period) {
            await loadTracks()
        }
    }

    private func loadTracks() async {
        isLoading = true
        do {
            tracks = try await LastFMClient.shared.getTopTracks(period: period, limit: 50)
            if let firstTrack = tracks.first {
                if let images = firstTrack["image"] {
                    print("[Last.fm] First track images: \(images)")
                } else {
                    print("[Last.fm] No images in first track")
                }
            }
        } catch {
            print("[Last.fm] Failed to load top tracks: \(error)")
        }
        isLoading = false
    }
}

struct TopTrackCard: View {
    let track: [String: Any]
    let rank: Int
    @State private var selectedAlbum: Album?

    var trackName: String {
        (track["name"] as? String) ?? "Unknown"
    }

    var artistName: String {
        if let artist = track["artist"] as? [String: Any],
           let name = artist["#text"] as? String {
            return name
        }
        return "Unknown"
    }

    var playCount: Int {
        Int((track["playcount"] as? String) ?? "0") ?? 0
    }

    var imageURL: URL? {
        if let images = track["image"] as? [[String: Any]] {
            // Try sizes in order: extralarge, large, medium, small
            let preferredSizes = ["extralarge", "large", "medium", "small"]
            for size in preferredSizes {
                for image in images {
                    if let imageSize = image["size"] as? String,
                       imageSize == size,
                       let url = image["#text"] as? String,
                       !url.isEmpty {
                        return URL(string: url)
                    }
                }
            }
        }
        return nil
    }

    var body: some View {
        NavigationLink(value: selectedAlbum) {
            VStack(alignment: .center, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if let imageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            case .failure(let error):
                                Image(systemName: "music.note")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .onAppear { print("[Last.fm] Image load failed for \(trackName): \(error)") }
                            case .empty:
                                SkeletonView()
                            @unknown default:
                                SkeletonView()
                            }
                        }
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .onAppear { print("[Last.fm] No image URL found for: \(trackName)") }
                    }

                    Text("#\(rank)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                        .padding(6)
                }
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .cornerRadius(8)

                VStack(alignment: .center, spacing: 2) {
                    Text(trackName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text(artistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("\(playCount) plays")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .task {
            await searchAndNavigate()
        }
    }

    private func searchAndNavigate() async {
        do {
            var result = try await SubsonicClient.shared.search(query: "\(trackName) \(artistName)")

            // If no results and artist is "Unknown", try just the track name
            if result.albums.isEmpty && artistName == "Unknown" {
                result = try await SubsonicClient.shared.search(query: trackName)
            }

            selectedAlbum = result.albums.first
            if selectedAlbum != nil && imageURL != nil {
                print("[Last.fm] Found album for: \(trackName)")
            }
        } catch {
            print("[Last.fm] Failed to search album: \(error)")
        }
    }
}

// MARK: - Top Artists

struct TopArtistsTab: View {
    @State private var period: LastFMPeriod = .month
    @State private var artists: [[String: Any]] = []
    @State private var isLoading = false

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]

    var body: some View {
        VStack(spacing: 0) {
            Picker("Period", selection: $period) {
                ForEach(LastFMPeriod.allCases, id: \.self) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            ScrollView {
                if isLoading {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(0..<12, id: \.self) { _ in
                            SkeletonGridCard()
                        }
                    }
                    .padding(20)
                } else if artists.isEmpty {
                    ContentUnavailableView("No data", systemImage: "chart.bar")
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(artists.indices, id: \.self) { index in
                            TopArtistCard(artist: artists[index], rank: index + 1)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .task(id: period) {
            await loadArtists()
        }
    }

    private func loadArtists() async {
        isLoading = true
        do {
            artists = try await LastFMClient.shared.getTopArtists(period: period, limit: 50)
        } catch {
            print("[Last.fm] Failed to load top artists: \(error)")
        }
        isLoading = false
    }
}

struct TopArtistCard: View {
    let artist: [String: Any]
    let rank: Int
    @State private var selectedArtist: Artist?

    var artistName: String {
        (artist["name"] as? String) ?? "Unknown"
    }

    var playCount: Int {
        Int((artist["playcount"] as? String) ?? "0") ?? 0
    }

    var imageURL: URL? {
        if let images = artist["image"] as? [[String: Any]] {
            for image in images.reversed() {
                if let size = image["size"] as? String,
                   size == "extralarge",
                   let url = image["#text"] as? String,
                   !url.isEmpty {
                    return URL(string: url)
                }
            }
        }
        return nil
    }

    var body: some View {
        NavigationLink(value: selectedArtist) {
            VStack(alignment: .center, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if let imageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            case .failure:
                                Image(systemName: "music.mic")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color(nsColor: .controlBackgroundColor))
                            case .empty:
                                SkeletonView()
                            @unknown default:
                                SkeletonView()
                            }
                        }
                    } else {
                        Color(nsColor: .controlBackgroundColor)
                    }

                    Text("#\(rank)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                        .padding(6)
                }
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .cornerRadius(90)

                VStack(alignment: .center, spacing: 2) {
                    Text(artistName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text("\(playCount) plays")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .task {
            await searchAndNavigate()
        }
    }

    private func searchAndNavigate() async {
        do {
            let result = try await SubsonicClient.shared.search(query: artistName)
            selectedArtist = result.artists.first
        } catch {
            print("[Last.fm] Failed to search artist: \(error)")
        }
    }
}

// MARK: - Top Albums

struct TopAlbumsTab: View {
    @State private var period: LastFMPeriod = .month
    @State private var albums: [[String: Any]] = []
    @State private var isLoading = false

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]

    var body: some View {
        VStack(spacing: 0) {
            Picker("Period", selection: $period) {
                ForEach(LastFMPeriod.allCases, id: \.self) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            ScrollView {
                if isLoading {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(0..<12, id: \.self) { _ in
                            SkeletonGridCard()
                        }
                    }
                    .padding(20)
                } else if albums.isEmpty {
                    ContentUnavailableView("No data", systemImage: "chart.bar")
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(albums.indices, id: \.self) { index in
                            TopAlbumCard(album: albums[index], rank: index + 1)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .task(id: period) {
            await loadAlbums()
        }
    }

    private func loadAlbums() async {
        isLoading = true
        do {
            albums = try await LastFMClient.shared.getTopAlbums(period: period, limit: 50)
        } catch {
            print("[Last.fm] Failed to load top albums: \(error)")
        }
        isLoading = false
    }
}

struct TopAlbumCard: View {
    let album: [String: Any]
    let rank: Int
    @State private var selectedAlbum: Album?

    var albumName: String {
        (album["name"] as? String) ?? "Unknown"
    }

    var artistName: String {
        if let artist = album["artist"] as? [String: Any],
           let name = artist["#text"] as? String {
            return name
        }
        return "Unknown"
    }

    var playCount: Int {
        Int((album["playcount"] as? String) ?? "0") ?? 0
    }

    var imageURL: URL? {
        if let images = album["image"] as? [[String: Any]] {
            for image in images.reversed() {
                if let size = image["size"] as? String,
                   size == "extralarge",
                   let url = image["#text"] as? String,
                   !url.isEmpty {
                    return URL(string: url)
                }
            }
        }
        return nil
    }

    var body: some View {
        NavigationLink(value: selectedAlbum) {
            VStack(alignment: .center, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if let imageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            case .failure:
                                Image(systemName: "square.stack")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color(nsColor: .controlBackgroundColor))
                            case .empty:
                                SkeletonView()
                            @unknown default:
                                SkeletonView()
                            }
                        }
                    } else {
                        Color(nsColor: .controlBackgroundColor)
                    }

                    Text("#\(rank)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                        .padding(6)
                }
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .cornerRadius(8)

                VStack(alignment: .center, spacing: 2) {
                    Text(albumName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text(artistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("\(playCount) plays")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .task {
            await searchAndNavigate()
        }
    }

    private func searchAndNavigate() async {
        do {
            var result = try await SubsonicClient.shared.search(query: "\(albumName) \(artistName)")

            // If no results and artist is "Unknown", try just the album name
            if result.albums.isEmpty && artistName == "Unknown" {
                result = try await SubsonicClient.shared.search(query: albumName)
            }

            selectedAlbum = result.albums.first
        } catch {
            print("[Last.fm] Failed to search album: \(error)")
        }
    }
}

// MARK: - Skeleton Loaders

struct SkeletonView: View {
    @State private var isShimmering = false

    var body: some View {
        Color(nsColor: .controlBackgroundColor)
            .overlay {
                LinearGradient(
                    gradient: Gradient(colors: [
                        .clear,
                        Color.white.opacity(0.1),
                        .clear
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: isShimmering ? 400 : -400)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isShimmering = true
                }
            }
    }
}

struct SkeletonGridCard: View {
    var body: some View {
        VStack(spacing: 8) {
            SkeletonView()
                .aspectRatio(1, contentMode: .fill)
                .cornerRadius(8)

            SkeletonView()
                .frame(height: 14)
            SkeletonView()
                .frame(height: 12)
                .frame(maxWidth: 100)
        }
    }
}
