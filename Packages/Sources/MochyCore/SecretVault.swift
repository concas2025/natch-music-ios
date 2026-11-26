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
        case lastFmSessionKey = "lastfm.sessionKey"
        case discordToken = "discord.token"
        case aiApiKey = "ai.apiKey"
        case listenBrainzToken = "listenbrainz.token"
    }

    private static let service = "com.mochyy.mochymusic.vault"

    public static func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
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

    public static func set(_ value: String?, for key: Key) throws {
        guard let value else {
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw SecretVaultError.keychainStatus(status)
        }
    }
}
