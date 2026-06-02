import SwiftUI

// MARK: - Genres

struct GenreListView: View {
    @Environment(LibraryStore.self) private var library
    @State private var sortByCount = false
    @State private var useGridView = true

    private var genres: [(name: String, count: Int)] {
        var map: [String: Int] = [:]
        for album in library.albums {
            if let g = album.genre { map[g, default: 0] += album.songCount }
        }
        let pairs = map.map { (name: $0.key, count: $0.value) }
        return sortByCount
            ? pairs.sorted { $0.count > $1.count }
            : pairs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 20)]

    var body: some View {
        NavigationStack {
            Group {
                if useGridView {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(genres, id: \.name) { genre in
                                NavigationLink(value: genre.name) {
                                    GenreCard(name: genre.name, count: genre.count)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(20)
                    }
                } else {
                    List {
                        ForEach(genres, id: \.name) { genre in
                            NavigationLink(value: genre.name) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color.accentColor.opacity(0.2),
                                                    Color.accentColor.opacity(0.05)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ))

                                        Image(systemName: "music.note")
                                            .font(.system(size: 14))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                    .frame(width: 32, height: 32)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(genre.name)
                                            .font(.body.weight(.medium))
                                        Text("\(genre.count) songs")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Genres")
            .navigationDestination(for: String.self) { genre in
                GenreDetailView(genre: genre, albums: library.albums.filter { $0.genre == genre })
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { useGridView.toggle() }
                    } label: {
                        Image(systemName: useGridView ? "square.grid.2x2" : "line.3.horizontal")
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
                ToolbarItem {
                    Menu {
                        Button { sortByCount = false } label: {
                            sortMenuLabel("Name", selected: !sortByCount)
                        }
                        Button { sortByCount = true } label: {
                            sortMenuLabel("Song Count", selected: sortByCount)
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
        }
    }
}

struct GenreCard: View {
    let name: String
    let count: Int

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [
                            Color.accentColor.opacity(0.3),
                            Color.accentColor.opacity(0.1)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                VStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.accentColor)
                    Text("\(count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 120)

            Text(name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }
}

struct GenreDetailView: View {
    let genre: String
    let albums: [Album]
    @Environment(PlayerEngine.self) private var player
    @State private var sortOrder = AlbumSortOrder.name

    private var sorted: [Album] {
        switch sortOrder {
        case .name:   return albums.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .year:   return albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .artist: return albums.sorted { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(sorted) { album in
                    NavigationLink(value: album) {
                        AlbumCard(album: album)
                    }.buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .navigationTitle(genre)
        .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
        .toolbar { AlbumSortMenu(sortOrder: $sortOrder) }
    }
}

// MARK: - Favorites

struct FavoritesView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerEngine.self) private var player
    @State private var sortOrder = SongSortOrder.title
    @State private var searchText = ""

    private var songs: [Song] {
        let filtered = searchText.isEmpty ? library.starredSongs :
            library.starredSongs.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.artist.localizedCaseInsensitiveContains(searchText)
            }
        switch sortOrder {
        case .title:    return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist:   return filtered.sorted { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .album:    return filtered.sorted { $0.album.localizedCaseInsensitiveCompare($1.album) == .orderedAscending }
        case .duration: return filtered.sorted { $0.duration < $1.duration }
        }
    }

    var body: some View {
        Group {
            if library.starredSongs.isEmpty && !library.isLoading {
                ContentUnavailableView(
                    "No Favorites Yet",
                    systemImage: "heart",
                    description: Text("Star songs to add them here.")
                )
            } else {
                List {
                    ForEach(songs) { song in
                        SongRow(song: song, showAlbum: true)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Favorites")
        .searchable(text: $searchText, prompt: "Search favorites")
        .toolbar {
            ToolbarItem {
                Button {
                    var shuffled = songs
                    shuffled.shuffle()
                    player.play(songs: shuffled, startingAt: 0)
                } label: { Label("Shuffle", systemImage: "shuffle") }
                .disabled(songs.isEmpty)
            }
            ToolbarItem { SongSortMenu(sortOrder: $sortOrder) }
        }
        .task { await library.refreshStarred() }
    }
}

// MARK: - Shared sort enums + menus

enum AlbumSortOrder: String, CaseIterable {
    case name = "Name"
    case artist = "Artist"
    case year = "Year"
}

enum SongSortOrder: String, CaseIterable {
    case title = "Title"
    case artist = "Artist"
    case album = "Album"
    case duration = "Duration"
}

struct AlbumSortMenu: View {
    @Binding var sortOrder: AlbumSortOrder
    var body: some View {
        Menu {
            ForEach(AlbumSortOrder.allCases, id: \.self) { order in
                Button { sortOrder = order } label: {
                    sortMenuLabel(order.rawValue, selected: sortOrder == order)
                }
            }
        } label: {
            Label("Sort by \(sortOrder.rawValue)", systemImage: "arrow.up.arrow.down")
        }
    }
}

struct SongSortMenu: View {
    @Binding var sortOrder: SongSortOrder
    var body: some View {
        Menu {
            ForEach(SongSortOrder.allCases, id: \.self) { order in
                Button { sortOrder = order } label: {
                    sortMenuLabel(order.rawValue, selected: sortOrder == order)
                }
            }
        } label: {
            Label("Sort by \(sortOrder.rawValue)", systemImage: "arrow.up.arrow.down")
        }
    }
}

@ViewBuilder
private func sortMenuLabel(_ title: String, selected: Bool) -> some View {
    if selected {
        Label(title, systemImage: "checkmark")
    } else {
        Text(title)
    }
}
