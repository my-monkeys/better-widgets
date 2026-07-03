import XCTest

final class PermissionStoreTests: XCTestCase {
    private var tmp: URL!
    private var store: PermissionStore!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = try PermissionStore(baseURL: tmp)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func testEmptyByDefault() {
        XCTAssertEqual(store.grantedTypes(instanceId: UUID()), [])
    }

    func testGrantAndRead() throws {
        let id = UUID()
        try store.grant(type: "calendar", instanceId: id)
        XCTAssertEqual(store.grantedTypes(instanceId: id), ["calendar"])
    }

    func testSetGrantedTypesRoundTrip() throws {
        let id = UUID()
        try store.setGrantedTypes(["calendar", "weather"], instanceId: id)
        XCTAssertEqual(store.grantedTypes(instanceId: id), ["calendar", "weather"])
        // Isolation between instances.
        XCTAssertEqual(store.grantedTypes(instanceId: UUID()), [])
    }
}
