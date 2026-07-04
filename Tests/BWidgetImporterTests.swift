import XCTest

final class BWidgetImporterTests: XCTestCase {
    private var root: URL!
    private var store: TemplateStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = TemplateStore(rootURL: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    // Build a .bwidget JSON container by hand for arbitrary (possibly malicious) entries.
    private func archive(_ entries: [(String, String)]) -> Data {
        let items = entries.map { ["path": $0.0, "data": Data($0.1.utf8).base64EncodedString()] }
        return try! JSONSerialization.data(withJSONObject: ["format": "bwidget/1", "entries": items])
    }
    private let validManifest = #"{"id":"orig","name":"Imported","version":"1.0.0","sizes":["small"],"refresh":900,"params":[],"sources":[]}"#

    func testInstallsValidArchiveAsUserTemplate() throws {
        let data = archive([("manifest.json", validManifest), ("index.html", "<b>ok</b>"), ("assets/x.css", "a{}")])
        let id = try BWidgetImporter.install(archive: data, into: store)
        XCTAssertTrue(store.isUserTemplate(id: id))
        XCTAssertEqual(try store.manifest(id: id).id, id)        // id rewritten, not "orig"
        XCTAssertEqual(try store.html(id: id), "<b>ok</b>")
        XCTAssertEqual(try store.manifest(id: id).name, "Imported")
    }

    func testRejectsAbsolutePath() {
        let data = archive([("manifest.json", validManifest), ("index.html", "<b>x</b>"), ("/etc/evil", "x")])
        XCTAssertThrowsError(try BWidgetImporter.install(archive: data, into: store)) {
            guard case ImportError.unsafeEntry = $0 else { return XCTFail("expected unsafeEntry") }
        }
        XCTAssertTrue(store.list().isEmpty)                       // nothing installed
    }

    func testRejectsDotDotPath() {
        let data = archive([("manifest.json", validManifest), ("index.html", "<b>x</b>"), ("assets/../../evil", "x")])
        XCTAssertThrowsError(try BWidgetImporter.install(archive: data, into: store)) {
            guard case ImportError.unsafeEntry = $0 else { return XCTFail("expected unsafeEntry") }
        }
        XCTAssertTrue(store.list().isEmpty)
    }

    func testRejectsNonWhitelistedEntry() {
        let data = archive([("manifest.json", validManifest), ("index.html", "<b>x</b>"), ("evil.sh", "rm -rf")])
        XCTAssertThrowsError(try BWidgetImporter.install(archive: data, into: store)) {
            guard case ImportError.unsafeEntry = $0 else { return XCTFail("expected unsafeEntry") }
        }
    }

    func testRejectsInvalidManifest() {
        let bad = #"{"id":"x","name":"X","version":"1","sizes":[],"refresh":900,"params":[],"sources":[]}"#  // emptySizes
        let data = archive([("manifest.json", bad), ("index.html", "<b>x</b>")])
        XCTAssertThrowsError(try BWidgetImporter.install(archive: data, into: store)) {
            XCTAssertEqual($0 as? ImportError, .invalidManifest)
        }
        XCTAssertTrue(store.list().isEmpty)
    }

    func testRejectsMissingIndex() {
        let data = archive([("manifest.json", validManifest)])
        XCTAssertThrowsError(try BWidgetImporter.install(archive: data, into: store)) {
            XCTAssertEqual($0 as? ImportError, .missingFile("index.html"))
        }
    }

    func testRejectsGarbageArchive() {
        XCTAssertThrowsError(try BWidgetImporter.install(archive: Data("not json".utf8), into: store)) {
            XCTAssertEqual($0 as? ImportError, .badArchive)
        }
    }
}
