import SwiftUI

struct OnboardingView: View {
    @Environment(LibraryStore.self) private var library
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var error = ""
    @State private var untrustedCertificate: UntrustedCertificate?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "music.note.house.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                Text("Welcome to Lune")
                    .font(.largeTitle.bold())
                Text("Connect to your Navidrome server to get started.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                TextField("Server URL", text: $serverURL, prompt: Text("https://music.example.com"))
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.URL)
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(maxWidth: 360)

            if !error.isEmpty {
                Label(error, systemImage: "xmark.circle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button {
                Task { await connect() }
            } label: {
                Group {
                    if isConnecting {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Text("Connect")
                    }
                }
                .frame(width: 120, height: 36)
            }
            .buttonStyle(.borderedProminent)
            .disabled(serverURL.isEmpty || username.isEmpty || password.isEmpty || isConnecting)

            Spacer()
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .certificateTrustPrompt($untrustedCertificate) {
            Task { await connect() }
        }
    }

    private func connect() async {
        isConnecting = true
        error = ""
        let config = ServerConfig(url: serverURL, username: username)
        await SubsonicClient.shared.configure(config: config, password: password)
        do {
            try await SubsonicClient.shared.ping()
            library.saveServerConfig(config, password: password)
            await library.loadLibrary()
        } catch let e {
            if let cert = e as? UntrustedCertificate {
                untrustedCertificate = cert
            } else {
                error = e.localizedDescription
            }
        }
        isConnecting = false
    }
}
