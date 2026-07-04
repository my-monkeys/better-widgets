import XCTest

final class KeychainStoreTests: XCTestCase {
    // In-memory backing so tests never touch the real Keychain.
    final class InMemorySecretStore: SecretBackingStore {
        private var store: [String: String] = [:]
        func setSecret(_ value: String, forKey key: String) { store[key] = value }
        func secret(forKey key: String) -> String? { store[key] }
        func deleteSecret(forKey key: String) { store[key] = nil }
    }

    func testRoundTrip() {
        let s: SecretBackingStore = InMemorySecretStore()
        XCTAssertNil(s.secret(forKey: "k"))
        s.setSecret("v", forKey: "k")
        XCTAssertEqual(s.secret(forKey: "k"), "v")
        s.setSecret("v2", forKey: "k")   // overwrite
        XCTAssertEqual(s.secret(forKey: "k"), "v2")
        s.deleteSecret(forKey: "k")
        XCTAssertNil(s.secret(forKey: "k"))
    }
}
