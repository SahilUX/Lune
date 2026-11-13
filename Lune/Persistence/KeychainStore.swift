import Foundation
import Security
import os

/// Secrets Lune keeps in the Keychain. The raw value is the Keychain account
/// name and also the legacy UserDefaults key the secret used to live under.
enum StoredSecret: String, CaseIterable, Sendable {
    case serverPassword
    case lastfmSessionKey
}

enum KeychainError: Error, CustomStringConvertible {
    case unexpectedStatus(OSStatus)
    case readBackMismatch

    var description: String {
        switch self {
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
            return "Keychain error \(status): \(message)"
        case .readBackMismatch:
            return "Keychain read-back did not match the written value"
        }
    }
}

/// Generic-password items in the login keychain, service `com.sahil.lune`,
/// one account per secret.
///
/// Lune is a non-sandboxed Developer ID app, so it uses the file-based login
/// keychain, which needs no `keychain-access-groups` entitlement. Access is
/// tied to the app's code signature through the item's ACL.
enum KeychainStore {
    static let service = "com.sahil.lune"
    private static let log = Logger(subsystem: "com.sahil.lune", category: "Keychain")

    private static func baseQuery(_ secret: StoredSecret) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: secret.rawValue,
        ]
    }

    /// Returns nil when the item is missing or can't be read.
    static func get(_ secret: StoredSecret) -> String? {
        var query = baseQuery(secret)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            log.error("Read of \(secret.rawValue, privacy: .public) failed: \(status)")
            return nil
        }
    }

    static func set(_ value: String, for secret: StoredSecret) throws {
        let data = Data(value.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(baseQuery(secret) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(secret)
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "Lune (\(secret.rawValue))"
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    static func delete(_ secret: StoredSecret) throws {
        let status = SecItemDelete(baseQuery(secret) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Moves any secret still in UserDefaults into the Keychain. The
    /// UserDefaults copy is removed only after the Keychain write succeeds and
    /// reads back the same value, so a failed write leaves the login intact.
    /// Safe to run on every launch: it does nothing once the defaults are clean.
    static func migrateFromUserDefaults(_ defaults: UserDefaults = .standard) {
        for secret in StoredSecret.allCases {
            guard let legacy = defaults.string(forKey: secret.rawValue) else { continue }
            if legacy.isEmpty {
                defaults.removeObject(forKey: secret.rawValue)
                continue
            }
            do {
                // A defaults value can only be newer than the Keychain one
                // (an older build wrote it), so it wins.
                if get(secret) != legacy {
                    try set(legacy, for: secret)
                }
                guard get(secret) == legacy else { throw KeychainError.readBackMismatch }
                defaults.removeObject(forKey: secret.rawValue)
                log.info("Migrated \(secret.rawValue, privacy: .public) to the Keychain")
            } catch {
                log.error("Keeping \(secret.rawValue, privacy: .public) in UserDefaults: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Keychain value, falling back to a UserDefaults copy that migration
    /// couldn't move yet.
    static func value(for secret: StoredSecret, defaults: UserDefaults = .standard) -> String? {
        get(secret) ?? defaults.string(forKey: secret.rawValue)
    }

    /// Stores a new value (or removes it when nil) and clears any legacy
    /// UserDefaults copy once the Keychain holds it.
    static func store(_ value: String?, for secret: StoredSecret, defaults: UserDefaults = .standard) {
        do {
            if let value, !value.isEmpty {
                try set(value, for: secret)
            } else {
                try delete(secret)
            }
            defaults.removeObject(forKey: secret.rawValue)
        } catch {
            log.error("Couldn't save \(secret.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
