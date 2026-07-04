import XCTest

final class TemplateStoreWriteTests: XCTestCase {
    private var root: URL!
    private var store: TemplateStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = TemplateStore(rootURL: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testCreateUserTemplateScaffoldIsValidAndMarked() throws {
        let id = store.createUserTemplate(name: "Mon Widget")
        XCTAssertTrue(store.isUserTemplate(id: id))
        let m = try store.manifest(id: id)          // scaffold parses & validates
        XCTAssertEqual(m.id, id)
        XCTAssertFalse(m.sizes.isEmpty)
        XCTAssertFalse(try store.html(id: id).isEmpty)
    }

    func testCreateUserTemplateUniqueIds() {
        let a = store.createUserTemplate(name: "Dup")
        let b = store.createUserTemplate(name: "Dup")
        XCTAssertNotEqual(a, b)                       // collision → suffix
    }

    func testForkCopiesAndReid() throws {
        let src = store.createUserTemplate(name: "Source")
        try store.saveTemplate(id: src, html: "<p>hi</p>",
            manifestJSON: ##"{"id":"\##(src)","name":"Source","version":"1.0.0","sizes":["small"],"refresh":900,"params":[],"sources":[]}"##)
        let fork = try store.forkTemplate(from: src)
        XCTAssertNotEqual(fork, src)
        XCTAssertTrue(store.isUserTemplate(id: fork))
        XCTAssertEqual(try store.manifest(id: fork).id, fork)   // manifest id rewritten
        XCTAssertEqual(try store.html(id: fork), "<p>hi</p>")   // html copied
    }

    func testSaveRejectsInvalidManifest() {
        let id = store.createUserTemplate(name: "T")
        let before = try? store.html(id: id)
        XCTAssertThrowsError(try store.saveTemplate(id: id, html: "<b>x</b>",
            manifestJSON: ##"{"id":"\##(id)","name":"T","version":"1","sizes":[],"refresh":900,"params":[],"sources":[]}"##))  // emptySizes
        XCTAssertEqual(try? store.html(id: id), before)  // nothing written on invalid
    }

    func testSaveWritesWhenValid() throws {
        let id = store.createUserTemplate(name: "T")
        try store.saveTemplate(id: id, html: "<b>ok</b>",
            manifestJSON: ##"{"id":"\##(id)","name":"T","version":"1.0.0","sizes":["medium"],"refresh":600,"params":[],"sources":[]}"##)
        XCTAssertEqual(try store.html(id: id), "<b>ok</b>")
        XCTAssertEqual(try store.manifest(id: id).refresh, 600)
    }

    func testCreateUserTemplateWithQuotesInNameProducesValidManifest() throws {
        let id = store.createUserTemplate(name: #"Weird "Name" \back"#)
        XCTAssertNoThrow(try store.manifest(id: id))
        XCTAssertTrue(store.list().map(\.id).contains(id))
    }

    func testSaveTemplateRefusesBundledId() throws {
        let bundledDir = root.appendingPathComponent("bundled")
        try FileManager.default.createDirectory(at: bundledDir, withIntermediateDirectories: true)
        let bundledManifest = #"{"id":"bundled","name":"B","version":"1.0.0","sizes":["small"],"refresh":900,"params":[],"sources":[]}"#
        try bundledManifest.write(to: bundledDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "<p>bundled</p>".write(to: bundledDir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try store.saveTemplate(id: "bundled", html: "<p>hacked</p>",
            manifestJSON: #"{"id":"bundled","name":"B2","version":"1.0.0","sizes":["medium"],"refresh":600,"params":[],"sources":[]}"#))

        XCTAssertEqual(try store.html(id: "bundled"), "<p>bundled</p>")
        XCTAssertEqual(try store.manifest(id: "bundled").refresh, 900)
        XCTAssertFalse(store.isUserTemplate(id: "bundled"))
    }

    func testDeleteUserTemplateRemovesUserButNotBundled() throws {
        let user = store.createUserTemplate(name: "U")
        store.deleteUserTemplate(id: user)
        XCTAssertThrowsError(try store.manifest(id: user))     // gone

        // simulate a bundled (no .user marker) template
        let bundledDir = root.appendingPathComponent("bundled")
        try FileManager.default.createDirectory(at: bundledDir, withIntermediateDirectories: true)
        try #"{"id":"bundled","name":"B","version":"1.0.0","sizes":["small"],"refresh":900,"params":[],"sources":[]}"#
            .write(to: bundledDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        XCTAssertFalse(store.isUserTemplate(id: "bundled"))
        store.deleteUserTemplate(id: "bundled")                 // no-op
        XCTAssertNoThrow(try store.manifest(id: "bundled"))     // still there
    }
}
