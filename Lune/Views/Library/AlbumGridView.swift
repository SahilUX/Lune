import SwiftUI

struct AlbumGridView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerEngine.self) private var player
    @State private var searchText = ""
    @State private var sortOrder = AlbumSortOrder.name
    @State private var genreFilter: String? = nil
    @State private var useGridView = true

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]

    private var availableGenres: [String] {
        Array(Set(library.albums.compactMap(\.genre))).sorted()
    }

    private var displayedAlbums: [Album] {
        var result = library.albums

        if let genre = genreFilter {
            result = result.filter { $0.genre == genre }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.artist.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sortOrder {
        case .name:   return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .artist: return result.sorted { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .year:   return result.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if useGridView {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 24) {
                            ForEach(displayedAlbums) { album in
                                NavigationLink(value: album) {
                                    AlbumCard(album: album)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(20)
                    }
                } else {
                    List(displayedAlbums) { album in
                        NavigationLink(value: album) {
                            HStack(spacing: 12) {
                                AsyncArtwork(coverArtId: album.coverArtId, size: 80, cornerRadius: 6)
                                    .frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(album.name).font(.body).lineLimit(1)
                                    Text(album.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if let year = album.year {
                                    Text("\(year)").font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Albums")
            .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
            .searchable(text: $searchText, prompt: "Search albums")
            .toolbar {
                ToolbarItem {
                    if library.isLoading { ProgressView().scaleEffect(0.7) }
                }
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
                    // Genre filter
                    Menu {
                        Button { genreFilter = nil } label: {
                            if genreFilter == nil { Label("All Genres", systemImage: "checkmark") }
                            else { Text("All Genres") }
                        }
                        Divider()
                        ForEach(availableGenres, id: \.self) { genre in
                            Button { genreFilter = genre } label: {
                                if genreFilter == genre { Label(genre, systemImage: "checkmark") }
                                else { Text(genre) }
                            }
                        }
                    } label: {
                        Label(genreFilter ?? "Genre",
                              systemImage: genreFilter != nil
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem { AlbumSortMenu(sortOrder: $sortOrder) }
            }
        }
        .task { await library.loadLibrary() }
    }
}

struct AlbumCard: View {
    let album: Album
    @Environment(PlayerEngine.self) private var player
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                AsyncArtwork(coverArtId: album.coverArtId, size: 300, cornerRadius: 10)
                    .aspectRatio(1, contentMode: .fill)
                    .shadow(radius: isHovered ? 12 : 4)

                if isHovered {
                    Button {
                        Task {
                            if let loaded = try? await SubsonicClient.shared.getAlbum(id: album.id) {
                                player.play(songs: loaded.songs, startingAt: 0)
                            }
                        }
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isHovered)

            Text(album.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(album.artist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .onHover { isHovered = $0 }
    }
}
