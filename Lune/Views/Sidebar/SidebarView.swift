import SwiftUI

enum SidebarItem: Hashable {
    case artists, albums, songs, genres, favorites, lastFMStats
    case playlist(String)
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerEngine.self) private var player

    var body: some View {
        List(selection: $selection) {
            Section {
                HStack {
                    Button {
                        var shuffled = library.songs
                        shuffled.shuffle()
                        player.play(songs: shuffled, startingAt: 0)
                    } label: {
                        Label("Shuffle All", systemImage: "shuffle")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
            }

            Section("Library") {
                Label("Artists", systemImage: "music.mic")
                    .tag(SidebarItem.artists)
                Label("Albums", systemImage: "square.stack")
                    .tag(SidebarItem.albums)
                Label("Songs", systemImage: "music.note")
                    .tag(SidebarItem.songs)
                Label("Genres", systemImage: "guitars")
                    .tag(SidebarItem.genres)
                Label("Favorites", systemImage: "heart.fill")
                    .tag(SidebarItem.favorites)
                Label("Last.fm", systemImage: "chart.bar.fill")
                    .tag(SidebarItem.lastFMStats)
            }

            Section("Playlists") {
                ForEach(library.playlists) { playlist in
                    Label(playlist.name, systemImage: "music.note.list")
                        .tag(SidebarItem.playlist(playlist.id))
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .controlBackgroundColor))
        .navigationTitle("Lune")
    }
}
