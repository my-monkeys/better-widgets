import Foundation
import Security

/// Abstraction over secret storage so the app uses the Keychain in production
/// while tests inject an in-memory backing (the real Keychain is never touched in tests).
protocol SecretBackingStore {
    func setSecret(_ value: String, forKey key: String)
    func secret(forKey key: String) -> String?
    func deleteSecret(forKey key: String)
}

/// Keychain-backed secret store (generic password items, one service).
struct KeychainStore: SecretBackingStore {
    private let service = "fr.my-monkey.BetterWidgets"

    func setSecret(_ value: String, forKey key: String) {
        deleteSecret(forKey: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func secret(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteSecret(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// In-memory secret store (used for editor preview so working-copy secrets
/// are resolved without writing to the real Keychain until the user saves).
final class InMemorySecretStore: SecretBackingStore {
    private var store: [String: String] = [:]
    func setSecret(_ value: String, forKey key: String) { store[key] = value }
    func secret(forKey key: String) -> String? { store[key] }
    func deleteSecret(forKey key: String) { store[key] = nil }
}
