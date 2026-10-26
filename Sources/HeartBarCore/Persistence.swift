import Foundation
import Security

@MainActor public protocol PreferencesRepository: AnyObject {
    func load() throws -> Preferences
    func save(_ preferences: Preferences) throws
}

@MainActor public final class UserDefaultsPreferences: PreferencesRepository {
    private let defaults: UserDefaults
    private let key = "HeartBar.preferences.v1"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() throws -> Preferences {
        guard let data = defaults.data(forKey: key) else { return Preferences() }
        var value = try JSONDecoder().decode(Preferences.self, from: data)
        value.sanitize()
        return value
    }

    public func save(_ preferences: Preferences) throws {
        defaults.set(try JSONEncoder().encode(preferences), forKey: key)
    }
}

@MainActor public protocol CredentialRepository: AnyObject {
    func load() throws -> String?
    func save(_ apiKey: String?) throws
}

public struct KeychainError: LocalizedError {
    public let status: OSStatus
    public var errorDescription: String? { "Keychain could not be accessed (\(status)). Unlock your login keychain and try again." }
}

@MainActor public final class KeychainCredentials: CredentialRepository {
    private let service = "com.heartbar.app.hyperate"
    private let account = "api-key"
    public init() {}

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() throws -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ apiKey: String?) throws {
        guard let apiKey, !apiKey.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(apiKey.utf8)]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecItemNotFound {
            var item = query.merging(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if updated != errSecSuccess {
            throw KeychainError(status: updated)
        }
    }
}
