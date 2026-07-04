import XCTest

final class BWidgetArchiveTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("assets"),
                                                withIntermediateDirectories: true)
        try #"{"id":"t","name":"T","version":"1.0.0","sizes":["small"],"refresh":900,"params":[],"sources":[]}"#
            .write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "<b>hi</b>".write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try "PNGDATA".write(to: dir.appendingPathComponent("assets/logo.png"), atomically: true, encoding: .utf8)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testExportEntriesRoundTrip() throws {
        let data = try BWidgetArchive.export(templateDir: dir)
        let entries = try BWidgetArchive.entries(in: data)
        let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.data) })
        XCTAssertEqual(String(data: byPath["index.html"] ?? Data(), encoding: .utf8), "<b>hi</b>")
        XCTAssertEqual(String(data: byPath["assets/logo.png"] ?? Data(), encoding: .utf8), "PNGDATA")
        XCTAssertTrue(byPath["manifest.json"].map { String(data: $0, encoding: .utf8)!.contains("\"id\"") } ?? false)
    }

    func testEntriesRejectsGarbage() {
        XCTAssertThrowsError(try BWidgetArchive.entries(in: Data("not json".utf8))) {
            XCTAssertEqual($0 as? BWidgetArchiveError, .malformed)
        }
    }
}
