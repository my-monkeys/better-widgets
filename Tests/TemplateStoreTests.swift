import XCTest

final class TemplateStoreTests: XCTestCase {
    private var root: URL!
    private var store: TemplateStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = TemplateStore(rootURL: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeTemplate(id: String, refresh: Int = 60) throws {
        let dir = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifest = """
        { "id": "\(id)", "name": "T", "version": "1.0.0", "sizes": ["small"],
          "refresh": \(refresh), "params": [], "sources": [] }
        """
        try manifest.write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "<html></html>".write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }

    func testListReturnsValidTemplatesOnly() throws {
        try writeTemplate(id: "good")
        try writeTemplate(id: "bad", refresh: 1) // refresh < 30 → manifest invalide
        let ids = store.list().map(\.id)
        XCTAssertEqual(ids, ["good"])
    }

    func testHtmlAndManifestLoad() throws {
        try writeTemplate(id: "good")
        XCTAssertEqual(try store.manifest(id: "good").id, "good")
        XCTAssertEqual(try store.html(id: "good"), "<html></html>")
    }

    func testMissingTemplateThrows() {
        XCTAssertThrowsError(try store.manifest(id: "nope"))
    }

    func testInstallBundledDoesNotOverwrite() throws {
        let bundleDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: bundleDir) }
        let src = bundleDir.appendingPathComponent("tpl")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try #"{ "id": "tpl", "name": "T", "version": "1.0.0", "sizes": ["small"], "refresh": 60, "params": [], "sources": [] }"#
            .write(to: src.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "v1".write(to: src.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

        try store.installBundledTemplates(from: bundleDir)
        XCTAssertEqual(try store.html(id: "tpl"), "v1")

        // Local edit then reinstall: must not overwrite.
        try "edited".write(to: root.appendingPathComponent("tpl/index.html"), atomically: true, encoding: .utf8)
        try store.installBundledTemplates(from: bundleDir)
        XCTAssertEqual(try store.html(id: "tpl"), "edited")
    }
}
