import XCTest

@MainActor
final class PermissionConsentModelTests: XCTestCase {
    private var tmp: URL!
    private var permissions: PermissionStore!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        permissions = try PermissionStore(baseURL: tmp)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func manifest(_ sources: String) -> TemplateManifest {
        try! TemplateManifest.validated(from: Data(#"""
        {"id":"t","name":"T","version":"1.0.0","sizes":["small"],"refresh":900,"params":[],"sources":[\#(sources)]}
        """#.utf8))
    }

    func testListsConsentRequiredTypesOnly() {
        let m = manifest(#"{"key":"cal","type":"calendar"},{"key":"w","type":"weather"},{"key":"s","type":"system"}"#)
        let model = PermissionConsentModel(instanceId: UUID(), manifest: m, permissions: permissions)
        XCTAssertEqual(model.requiredTypes, ["calendar", "weather"])   // system excluded, sorted
    }

    func testToggleWritesToStoreAndIsolatesByInstance() {
        let m = manifest(#"{"key":"cal","type":"calendar"}"#)
        let id = UUID()
        let model = PermissionConsentModel(instanceId: id, manifest: m, permissions: permissions)
        XCTAssertFalse(model.isGranted("calendar"))
        model.setGranted("calendar", true)
        XCTAssertTrue(model.isGranted("calendar"))
        XCTAssertEqual(permissions.grantedTypes(instanceId: id), ["calendar"])
        XCTAssertEqual(permissions.grantedTypes(instanceId: UUID()), [])   // isolated
        model.setGranted("calendar", false)
        XCTAssertEqual(permissions.grantedTypes(instanceId: id), [])
    }

    func testLabels() {
        XCTAssertEqual(PermissionConsentModel.label(for: "calendar"), "Calendrier")
        XCTAssertEqual(PermissionConsentModel.label(for: "weather"), "Météo")
    }
}
