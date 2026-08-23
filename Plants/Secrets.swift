import CryptoKit
import Foundation
import Security

struct KeychainCredentialStore: @unchecked Sendable {
    let service: String
    let account: String
    let legacyDefaultsKey: String
    let defaults: UserDefaults

    init(
        service: String,
        account: String,
        legacyDefaultsKey: String,
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.account = account
        self.legacyDefaultsKey = legacyDefaultsKey
        self.defaults = defaults
    }

    func value() -> String? {
        if let stored = read() { return stored }
        return migrateLegacyValueIfNeeded()
    }

    func set(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try clear()
            return
        }

        let attributes: [String: Any] = [
            kSecValueData as String: Data(trimmed.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery
            attributes.forEach { query[$0.key] = $0.value }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.status(addStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }

        defaults.removeObject(forKey: legacyDefaultsKey)
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
        defaults.removeObject(forKey: legacyDefaultsKey)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }

    private func migrateLegacyValueIfNeeded() -> String? {
        guard let legacy = defaults.string(forKey: legacyDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !legacy.isEmpty
        else {
            return nil
        }

        do {
            try set(legacy)
            return legacy
        } catch {
            return nil
        }
    }
}

enum Secrets {
    static let legacyUserDefaultsKey = "openRouterAPIKey"

    private static let store = KeychainCredentialStore(
        service: Bundle.main.bundleIdentifier ?? "me.bn4t.plants",
        account: "openrouter-api-key",
        legacyDefaultsKey: legacyUserDefaultsKey
    )

    static var openRouterAPIKey: String? { store.value() }
    static var hasOpenRouterAPIKey: Bool { openRouterAPIKey != nil }

    static func setOpenRouterAPIKey(_ value: String) throws {
        try store.set(value)
    }

    static func clearOpenRouterAPIKey() throws {
        try store.clear()
    }

    static var openRouterKeySettingsURL: URL? {
        guard let key = openRouterAPIKey else {
            return URL(string: "https://openrouter.ai/settings/keys")
        }
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return URL(string: "https://openrouter.ai/keys/\(digest)")
    }
}

enum KeychainError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .status(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
            return "Could not securely store the OpenRouter key: \(message)"
        }
    }
}
