import SwiftUI

enum ArtistSortOrder: String, CaseIterable {
    case name = "Name"
    case albumCount = "Album Count"
}

struct ArtistListView: View {
    @Environment(LibraryStore.self) private var library
    @State private var searchText = ""
    @State private var sortOrder = ArtistSortOrder.name
    @State private var useGridView = false

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 20)]

    private var filtered: [Artist] {
        var result = library.artists
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        switch sortOrder {
        case .name:       return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .albumCount: return result.sorted { $0.albumCount > $1.albumCount }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if useGridView {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(filtered) { artist in
                                NavigationLink(value: artist) {
                                    VStack(spacing: 8) {
                                        AsyncArtwork(coverArtId: artist.coverArtId, size: 300, cornerRadius: 90)
                                            .frame(width: 140, height: 140)
                                            .clipShape(Circle())
                                            .shadow(radius: 4)
                                        VStack(spacing: 2) {
                                            Text(artist.name)
                                                .font(.subheadline.weight(.semibold))
                                                .lineLimit(1)
                                            Text("\(artist.albumCount) album\(artist.albumCount == 1 ? "" : "s")")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(20)
                    }
                } else {
                    List {
                        ForEach(filtered) { artist in
                            NavigationLink(value: artist) {
                                HStack(spacing: 12) {
                                    AsyncArtwork(coverArtId: artist.coverArtId, size: 80, cornerRadius: 40)
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(artist.name).font(.body)
                                        Text("\(artist.albumCount) album\(artist.albumCount == 1 ? "" : "s")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Artists")
            .searchable(text: $searchText, prompt: "Search artists")
            .navigationDestination(for: Artist.self) { ArtistDetailView(artist: $0) }
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
                        ForEach(ArtistSortOrder.allCases, id: \.self) { order in
                            Button { sortOrder = order } label: {
                                if sortOrder == order {
                                    Label(order.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(order.rawValue)
                                }
                            }
                        }
                    } label: {
                        Label("Sort by \(sortOrder.rawValue)", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
        }
    }
}

struct ArtistDetailView: View {
    let artist: Artist
    @State private var loadedArtist: Artist?
    @State private var sortOrder = AlbumSortOrder.name

    private var displayArtist: Artist { loadedArtist ?? artist }

    private var sortedAlbums: [Album] {
        switch sortOrder {
        case .name:   return displayArtist.albums.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .artist: return displayArtist.albums.sorted { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .year:   return displayArtist.albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    AsyncArtwork(coverArtId: displayArtist.coverArtId, size: 200, cornerRadius: 60)
                        .frame(width: 100, height: 100)
                    VStack(alignment: .leading) {
                        Text(displayArtist.name).font(.title.bold())
                        Text("\(displayArtist.albumCount) albums").foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(sortedAlbums) { album in
                        NavigationLink(value: album) {
                            AlbumCard(album: album)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle(displayArtist.name)
        .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
        .toolbar { AlbumSortMenu(sortOrder: $sortOrder) }
        .task { loadedArtist = try? await SubsonicClient.shared.getArtist(id: artist.id) }
    }
}
