import XCTest

final class SecretResolverTests: XCTestCase {
    private final class MemStore: SecretBackingStore {
        var store: [String: String] = [:]
        func setSecret(_ value: String, forKey key: String) { store[key] = value }
        func secret(forKey key: String) -> String? { store[key] }
        func deleteSecret(forKey key: String) { store[key] = nil }
    }

    func testSetGetDelete() {
        let mem = MemStore(); let r = SecretResolver(backing: mem)
        let id = UUID()
        r.set("tok", instanceId: id, sourceKey: "api", header: "Authorization")
        XCTAssertEqual(r.get(instanceId: id, sourceKey: "api", header: "Authorization"), "tok")
        r.delete(instanceId: id, sourceKey: "api", header: "Authorization")
        XCTAssertNil(r.get(instanceId: id, sourceKey: "api", header: "Authorization"))
    }

    func testResolvedConfigMapsSecretToHeader() {
        let mem = MemStore(); let r = SecretResolver(backing: mem)
        let id = UUID()
        r.set("Bearer xyz", instanceId: id, sourceKey: "api", header: "Authorization")
        let source = SourceSpec(key: "api", type: "json",
                                config: ["url": "https://x", "secret.Authorization": "", "header.Accept": "json"])
        let resolved = r.resolvedConfig(for: source, instanceId: id)
        XCTAssertEqual(resolved?["header.Authorization"], "Bearer xyz")  // secret → header
        XCTAssertNil(resolved?["secret.Authorization"])                  // secret key removed
        XCTAssertEqual(resolved?["header.Accept"], "json")               // existing header untouched
        XCTAssertEqual(resolved?["url"], "https://x")
    }

    func testResolvedConfigOmitsMissingSecret() {
        let mem = MemStore(); let r = SecretResolver(backing: mem)
        let source = SourceSpec(key: "api", type: "json", config: ["secret.Authorization": ""])
        let resolved = r.resolvedConfig(for: source, instanceId: UUID())
        XCTAssertNil(resolved?["header.Authorization"])  // no stored value → omitted
        XCTAssertNil(resolved?["secret.Authorization"])
    }

    func testNonJSONSourceUnchanged() {
        let r = SecretResolver(backing: MemStore())
        let source = SourceSpec(key: "sys", type: "system", config: ["secret.X": ""])
        XCTAssertEqual(r.resolvedConfig(for: source, instanceId: UUID())?["secret.X"], "")  // untouched
    }

    func testDeleteAllPurgesDeclaredSecrets() {
        let mem = MemStore(); let r = SecretResolver(backing: mem)
        let id = UUID()
        r.set("a", instanceId: id, sourceKey: "api", header: "Authorization")
        let sources = [SourceSpec(key: "api", type: "json", config: ["secret.Authorization": ""])]
        r.deleteAll(instanceId: id, sources: sources)
        XCTAssertNil(r.get(instanceId: id, sourceKey: "api", header: "Authorization"))
    }

    func testNoopResolverReturnsConfigUnchanged() {
        let source = SourceSpec(key: "api", type: "json", config: ["secret.Authorization": ""])
        XCTAssertEqual(NoopSecretResolver().resolvedConfig(for: source, instanceId: UUID())?["secret.Authorization"], "")
    }
}
