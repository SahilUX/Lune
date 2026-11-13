import Foundation
import CryptoKit
import Security

/// A server certificate that macOS does not trust, which the user may choose
/// to pin. Thrown by `SubsonicClient` so the UI can ask before connecting.
struct UntrustedCertificate: LocalizedError, Sendable, Equatable {
    let host: String
    /// SHA-256 of the leaf certificate (DER), lowercase hex.
    let fingerprint: String
    /// True when the host already has a pinned certificate and this is a different one.
    let changed: Bool

    var formattedFingerprint: String { ServerTrust.format(fingerprint) }

    var errorDescription: String? {
        if changed {
            return "The certificate for \(host) has changed since you trusted it. Open Settings > Server and choose Test Connection to review it."
        }
        return "The certificate for \(host) isn't trusted by macOS. Open Settings > Server and choose Test Connection to review it."
    }
}

/// Certificates the user chose to trust, pinned per host by SHA-256
/// fingerprint of the leaf certificate. Only an exact match is accepted, and
/// only when normal system validation fails. This is not a switch that turns
/// TLS checks off.
final class ServerTrust: @unchecked Sendable {
    static let shared = ServerTrust()

    private static let defaultsKey = "trustedCertificates"

    private let lock = NSLock()
    private let defaults: UserDefaults
    private var pins: [String: Set<String>]
    private var rejected: [String: String] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.defaultsKey) as? [String: [String]] ?? [:]
        pins = stored.mapValues(Set.init)
    }

    // MARK: - Pins

    func hasPins(for host: String) -> Bool {
        lock.withLock { !(pins[host.lowercased()]?.isEmpty ?? true) }
    }

    func isPinned(host: String, fingerprint: String) -> Bool {
        lock.withLock { pins[host.lowercased()]?.contains(fingerprint) ?? false }
    }

    var trustedHosts: [String] {
        lock.withLock { pins.filter { !$0.value.isEmpty }.keys.sorted() }
    }

    func trust(_ cert: UntrustedCertificate) {
        lock.withLock {
            // One pin per host: trusting a new certificate replaces the old one.
            pins[cert.host.lowercased()] = [cert.fingerprint]
            rejected[cert.host.lowercased()] = nil
            persist()
        }
    }

    func forget(host: String) {
        lock.withLock {
            pins[host.lowercased()] = nil
            persist()
        }
    }

    private func persist() {
        defaults.set(pins.mapValues { Array($0).sorted() }, forKey: Self.defaultsKey)
    }

    // MARK: - Rejections (what the delegate saw, so callers can offer to trust it)

    fileprivate func recordRejected(host: String, fingerprint: String) {
        lock.withLock { rejected[host.lowercased()] = fingerprint }
    }

    fileprivate func clearRejected(host: String) {
        lock.withLock { rejected[host.lowercased()] = nil }
    }

    /// Turns a failed request into `UntrustedCertificate` when the failure was
    /// our delegate refusing the server's certificate.
    func mapError(_ error: Error, host: String?) -> Error {
        guard let host, let urlError = error as? URLError else { return error }
        let certificateCodes: Set<URLError.Code> = [
            .cancelled, .secureConnectionFailed, .serverCertificateUntrusted,
            .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
            .serverCertificateNotYetValid,
        ]
        guard certificateCodes.contains(urlError.code) else { return error }
        guard let fingerprint = lock.withLock({ rejected[host.lowercased()] }) else { return error }
        return UntrustedCertificate(host: host, fingerprint: fingerprint, changed: hasPins(for: host))
    }

    // MARK: - Formatting

    static func fingerprint(of certificate: SecCertificate) -> String {
        let der = SecCertificateCopyData(certificate) as Data
        return SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }

    static func format(_ hex: String) -> String {
        var parts: [String] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            parts.append(hex[index..<next].uppercased())
            index = next
        }
        return parts.joined(separator: ":")
    }
}

/// Accepts a server certificate only if the system trusts it, or its
/// fingerprint was pinned by the user for that host.
final class PinningSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let store: ServerTrust

    init(store: ServerTrust = .shared) {
        self.store = store
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = space.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        var evaluationError: CFError?
        if SecTrustEvaluateWithError(trust, &evaluationError) {
            store.clearRejected(host: space.host)
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let fingerprint = ServerTrust.fingerprint(of: leaf)
        if store.isPinned(host: space.host, fingerprint: fingerprint) {
            store.clearRejected(host: space.host)
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            store.recordRejected(host: space.host, fingerprint: fingerprint)
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

enum TrustedSession {
    /// Use this for every request to the user's server instead of `URLSession.shared`.
    static let shared = URLSession(
        configuration: .default,
        delegate: PinningSessionDelegate(),
        delegateQueue: nil
    )
}
