import XCTest

final class TemplateAssetSchemeHandlerTests: XCTestCase {
    private var dir: URL!
    private var outsideDir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "PNGDATA".write(to: dir.appendingPathComponent("logo.png"), atomically: true, encoding: .utf8)
        let sub = dir.appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "X".write(to: sub.appendingPathComponent("f.css"), atomically: true, encoding: .utf8)

        outsideDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        try "SECRET".write(to: outsideDir.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: outsideDir)
    }

    func testResolvesFileInsideTemplateDir() throws {
        let url = try XCTUnwrap(resolveTemplateAsset(templateDir: dir, requestPath: "/logo.png"))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "PNGDATA")
    }

    func testResolvesNestedAsset() throws {
        XCTAssertNotNil(resolveTemplateAsset(templateDir: dir, requestPath: "/assets/f.css"))
    }

    func testRejectsPathTraversal() {
        XCTAssertNil(resolveTemplateAsset(templateDir: dir, requestPath: "/../../etc/hosts"))
        XCTAssertNil(resolveTemplateAsset(templateDir: dir, requestPath: "/assets/../../../etc/passwd"))
    }

    func testRejectsMissingFile() {
        XCTAssertNil(resolveTemplateAsset(templateDir: dir, requestPath: "/nope.png"))
    }

    func testRejectsSymlinkEscapingTemplateDir() throws {
        let secretURL = outsideDir.appendingPathComponent("secret.txt")
        try FileManager.default.createSymbolicLink(
            at: dir.appendingPathComponent("leak.png"),
            withDestinationURL: secretURL
        )

        XCTAssertNil(resolveTemplateAsset(templateDir: dir, requestPath: "/leak.png"))
    }
}
