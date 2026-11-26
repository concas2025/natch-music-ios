import Foundation
import Security

public enum SecretVaultError: Error, Equatable {
    case encodingFailed
    case keychainStatus(OSStatus)
}

public enum SecretVault {
    public enum Key: String, CaseIterable, Sendable {
        case ytmCookie = "ytm.cookie"
        case ytmVisitorData = "ytm.visitorData"
        case ytmDataSyncId = "ytm.dataSyncId"
        case spotifyToken = "spotify.token"
        case lastFmApiKey = "lastfm.apiKey"
        case lastFmSharedSecret = "lastfm.sharedSecret"
        case lastFmSessionKey = "lastfm.sessionKey"
        case discordToken = "discord.token"
        case aiApiKey = "ai.apiKey"
        case listenBrainzToken = "listenbrainz.token"
        case webDavUrl = "webdav.url"
        case webDavUsername = "webdav.username"
        case webDavPassword = "webdav.password"
    }

    private static let service = "com.natch.music.ios.vault"
    private static let legacyService = "com.mochyy.mochymusic.vault"

    public static func get(_ key: Key) -> String? {
        if let value = readFromKeychain(service: service, account: key.rawValue) {
            return value
        }
        // Transparent migration from v1.0.0 keychain service namespace.
        if let legacy = readFromKeychain(service: legacyService, account: key.rawValue) {
            try? set(legacy, for: key)
            return legacy
        }
        return nil
    }

    public static func set(_ value: String?, for key: Key) throws {
        guard let value, !value.isEmpty else {
            try delete(key)
            return
        }
        guard let data = value.data(using: .utf8) else {
            throw SecretVaultError.encodingFailed
        }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SecretVaultError.keychainStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw SecretVaultError.keychainStatus(updateStatus)
        }
    }

    public static func delete(_ key: Key) throws {
        for svc in [service, legacyService] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: svc,
                kSecAttrAccount as String: key.rawValue,
            ]
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                throw SecretVaultError.keychainStatus(status)
            }
        }
    }

    private static func readFromKeychain(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
