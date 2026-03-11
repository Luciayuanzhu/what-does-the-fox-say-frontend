import Foundation
import Security

/// Wraps the minimal Keychain calls used to persist device-scoped identifiers across reinstalls.
enum KeychainHelper {
    /// Reads a single generic-password entry from the Keychain.
    static func read(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    /// Replaces a generic-password entry with new data for the same service and account pair.
    static func save(_ data: Data, service: String, account: String) {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}

/// Generates and persists the anonymous device identifier used to bind local installs to backend history.
final class DeviceIdManager {
    static let shared = DeviceIdManager()

    private let service = "eggtart.device"
    private let account = "deviceId"
    private let legacyService = "eggtart.installation"
    private let legacyAccount = "installationId"

    private init() {}

    /// Returns the stored device ID, migrates the legacy value if needed, or creates a new UUID.
    func loadOrCreateDeviceId() -> String {
        if let data = KeychainHelper.read(service: service, account: account),
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            return value
        }

        if let data = KeychainHelper.read(service: legacyService, account: legacyAccount),
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            if let migrated = value.data(using: .utf8) {
                KeychainHelper.save(migrated, service: service, account: account)
            }
            return value
        }

        let newId = UUID().uuidString
        if let data = newId.data(using: .utf8) {
            KeychainHelper.save(data, service: service, account: account)
        }
        return newId
    }
}
