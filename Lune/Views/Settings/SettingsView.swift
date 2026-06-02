import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var localURL = ""
    @State private var remoteURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isVerifying = false
    @State private var verifyMessage = ""
    @State private var verifySuccess = false
    @State private var lastfmAPIKey = ""
    @State private var lastfmAPISecret = ""
    @State private var lastfmAuthStep: LastFMAuthStep = .idle
    @State private var lastfmToken = ""
    @State private var lastfmIsAuthenticating = false

    var body: some View {
        TabView {
            serverTab.tabItem { Label("Server", systemImage: "server.rack") }
            playbackTab.tabItem { Label("Playback", systemImage: "speaker.wave.2") }
            cacheTab.tabItem { Label("Cache", systemImage: "internaldrive") }
            lastfmTab.tabItem { Label("Last.fm", systemImage: "dot.radiowaves.left.and.right") }
        }
        .frame(width: 520, height: 340)
        .onAppear { prefill() }
    }

    private var serverTab: some View {
        Form {
            Section("Navidrome / Subsonic Server") {
                TextField("Local URL (optional)", text: $localURL, prompt: Text("http://192.168.1.100:4533"))
                    .textContentType(.URL)
                    .help("Local network address (used first when available)")

                TextField("Remote URL (optional)", text: $remoteURL, prompt: Text("https://music.example.com"))
                    .textContentType(.URL)
                    .help("Remote address (fallback if local unavailable)")

                TextField("Username", text: $username)
                SecureField("Password", text: $password)
            }

            HStack {
                Button("Test Connection") {
                    Task { await testConnection() }
                }
                .disabled((localURL.isEmpty && remoteURL.isEmpty) || username.isEmpty || password.isEmpty || isVerifying)

                if isVerifying { ProgressView().scaleEffect(0.6) }

                if !verifyMessage.isEmpty {
                    Label(verifyMessage, systemImage: verifySuccess ? "checkmark.circle" : "xmark.circle")
                        .foregroundStyle(verifySuccess ? .green : .red)
                        .font(.caption)
                }

                Spacer()

                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled((localURL.isEmpty && remoteURL.isEmpty) || username.isEmpty || password.isEmpty)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var playbackTab: some View {
        Form {
            Section("Local Network Streaming") {
                Picker("Format", selection: Binding(
                    get: { UserDefaults.standard.string(forKey: "localFormat") ?? "" },
                    set: { UserDefaults.standard.set($0, forKey: "localFormat") }
                )) {
                    Text("Original").tag("")
                    Text("MP3").tag("mp3")
                    Text("AAC").tag("aac")
                    Text("FLAC").tag("flac")
                    Text("Opus").tag("opus")
                }

                Picker("Bitrate", selection: Binding(
                    get: { UserDefaults.standard.integer(forKey: "localBitrate") },
                    set: { UserDefaults.standard.set($0, forKey: "localBitrate") }
                )) {
                    Text("Original").tag(0)
                    Text("320 kbps").tag(320)
                    Text("256 kbps").tag(256)
                    Text("192 kbps").tag(192)
                    Text("128 kbps").tag(128)
                }
            }

            Section("Remote Streaming") {
                Picker("Format", selection: Binding(
                    get: { UserDefaults.standard.string(forKey: "remoteFormat") ?? "" },
                    set: { UserDefaults.standard.set($0, forKey: "remoteFormat") }
                )) {
                    Text("Original").tag("")
                    Text("MP3").tag("mp3")
                    Text("AAC").tag("aac")
                    Text("FLAC").tag("flac")
                    Text("Opus").tag("opus")
                }

                Picker("Bitrate", selection: Binding(
                    get: { UserDefaults.standard.integer(forKey: "remoteBitrate") },
                    set: { UserDefaults.standard.set($0, forKey: "remoteBitrate") }
                )) {
                    Text("Original").tag(0)
                    Text("320 kbps").tag(320)
                    Text("256 kbps").tag(256)
                    Text("192 kbps").tag(192)
                    Text("128 kbps").tag(128)
                }
            }

            Section("Other") {
                Toggle("Menu Bar Player", isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: "menuBarEnabled") },
                    set: { UserDefaults.standard.set($0, forKey: "menuBarEnabled") }
                ))

                Toggle("Hide main window when entering PiP", isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: "pipHidesMainWindow") },
                    set: { UserDefaults.standard.set($0, forKey: "pipHidesMainWindow") }
                ))
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var cacheTab: some View {
        Form {
            Picker("Cache Size Limit", selection: Binding(
                get: { UserDefaults.standard.integer(forKey: "cacheSizeGB") },
                set: { UserDefaults.standard.set($0, forKey: "cacheSizeGB") }
            )) {
                Text("1 GB").tag(1)
                Text("2 GB").tag(2)
                Text("5 GB").tag(5)
                Text("10 GB").tag(10)
                Text("Unlimited").tag(0)
            }

            Button("Clear Cache", role: .destructive) {
                // TODO: call TrackCache.shared.clear()
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var lastfmTab: some View {
        Form {
            Section("API Credentials") {
                TextField("API Key", text: $lastfmAPIKey)
                    .help("Get from https://www.last.fm/api/account/create")
                    .onSubmit { UserDefaults.standard.set(lastfmAPIKey, forKey: "lastfmAPIKey") }

                SecureField("API Secret", text: $lastfmAPISecret)
                    .help("Get from https://www.last.fm/api/account/create")
                    .onSubmit { UserDefaults.standard.set(lastfmAPISecret, forKey: "lastfmAPISecret") }
            }

            Section("Account") {
                if let username = UserDefaults.standard.string(forKey: "lastfmUsername"), !username.isEmpty {
                    Label("Connected as \(username)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)

                    Button("Disconnect", role: .destructive) {
                        Task {
                            await LastFMClient.shared.disconnect()
                            prefillLastFM()
                        }
                    }
                } else {
                    switch lastfmAuthStep {
                    case .idle:
                        Button("Connect Last.fm") {
                            Task { await startLastFMAuth() }
                        }
                        .disabled(lastfmAPIKey.isEmpty || lastfmAPISecret.isEmpty)

                    case .authorized:
                        Button("I've authorized — Finish connecting") {
                            Task { await finishLastFMAuth() }
                        }

                        Button("Cancel", role: .cancel) {
                            lastfmAuthStep = .idle
                        }
                    }

                    if lastfmIsAuthenticating {
                        ProgressView()
                    }
                }
            }

            Section("Scrobbling") {
                Toggle("Enable scrobbling", isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: "lastfmEnabled") },
                    set: { UserDefaults.standard.set($0, forKey: "lastfmEnabled") }
                ))
                .disabled(UserDefaults.standard.string(forKey: "lastfmUsername")?.isEmpty != false)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func prefill() {
        if let config = library.serverConfig {
            localURL = config.localURL ?? ""
            remoteURL = config.remoteURL ?? ""
            username = config.username
        }
        prefillLastFM()
    }

    private func prefillLastFM() {
        lastfmAPIKey = UserDefaults.standard.string(forKey: "lastfmAPIKey") ?? ""
        lastfmAPISecret = UserDefaults.standard.string(forKey: "lastfmAPISecret") ?? ""
        lastfmAuthStep = .idle
        lastfmToken = ""
    }

    private func save() {
        let config = ServerConfig(localURL: localURL, remoteURL: remoteURL, username: username)
        library.saveServerConfig(config, password: password)
    }

    private func testConnection() async {
        isVerifying = true
        verifyMessage = ""
        let config = ServerConfig(localURL: localURL, remoteURL: remoteURL, username: username)
        await SubsonicClient.shared.configure(config: config, password: password)
        do {
            try await SubsonicClient.shared.ping()
            verifyMessage = "Connected"
            verifySuccess = true
        } catch {
            verifyMessage = error.localizedDescription
            verifySuccess = false
        }
        isVerifying = false
    }

    private func startLastFMAuth() async {
        lastfmIsAuthenticating = true
        do {
            lastfmToken = try await LastFMClient.shared.getToken(apiKey: lastfmAPIKey, apiSecret: lastfmAPISecret)
            LastFMClient.shared.openAuthPage(token: lastfmToken, apiKey: lastfmAPIKey)
            lastfmAuthStep = .authorized
        } catch {
            print("Failed to get Last.fm token: \(error)")
        }
        lastfmIsAuthenticating = false
    }

    private func finishLastFMAuth() async {
        lastfmIsAuthenticating = true
        do {
            try await LastFMClient.shared.getSession(token: lastfmToken, apiKey: lastfmAPIKey, apiSecret: lastfmAPISecret)
            UserDefaults.standard.set(lastfmAPIKey, forKey: "lastfmAPIKey")
            UserDefaults.standard.set(lastfmAPISecret, forKey: "lastfmAPISecret")
            UserDefaults.standard.set(true, forKey: "lastfmEnabled")
            prefillLastFM()
        } catch {
            print("Failed to get Last.fm session: \(error)")
        }
        lastfmIsAuthenticating = false
    }
}

enum LastFMAuthStep {
    case idle
    case authorized
}
