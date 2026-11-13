import SwiftUI

extension View {
    /// Asks whether to trust a server certificate macOS rejected. Trusting pins
    /// that exact certificate for its host, then calls `onTrust` so the caller
    /// can retry the connection.
    func certificateTrustPrompt(
        _ pending: Binding<UntrustedCertificate?>,
        onTrust: @escaping () -> Void
    ) -> some View {
        alert(
            pending.wrappedValue?.changed == true ? "Certificate changed" : "Trust this certificate?",
            isPresented: Binding(
                get: { pending.wrappedValue != nil },
                set: { if !$0 { pending.wrappedValue = nil } }
            ),
            presenting: pending.wrappedValue
        ) { cert in
            Button("Trust and Connect") {
                ServerTrust.shared.trust(cert)
                onTrust()
            }
            Button("Cancel", role: .cancel) {}
        } message: { cert in
            Text(message(for: cert))
        }
    }

    private func message(for cert: UntrustedCertificate) -> String {
        let intro = cert.changed
            ? "\(cert.host) is presenting a different certificate from the one you trusted. This is expected if you renewed it, and a warning sign otherwise."
            : "macOS can't verify the certificate for \(cert.host). That is normal for a self-signed certificate on your own server."
        return """
        \(intro)

        Compare this SHA-256 fingerprint with your server's certificate. If it matches, Lune will accept this exact certificate for \(cert.host) and nothing else.

        \(cert.formattedFingerprint)
        """
    }
}
