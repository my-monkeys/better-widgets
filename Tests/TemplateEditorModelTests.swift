import XCTest

@MainActor
final class TemplateEditorModelTests: XCTestCase {
    private var root: URL!
    private var store: TemplateStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = TemplateStore(rootURL: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testLoadsHtmlAndManifest() throws {
        let id = store.createUserTemplate(name: "T")
        let model = TemplateEditorModel(templateId: id, store: store)
        XCTAssertFalse(model.htmlText.isEmpty)
        XCTAssertTrue(model.manifestText.contains("\"id\""))
        XCTAssertEqual(model.tab, .html)
    }

    func testValidateOKAndError() throws {
        let id = store.createUserTemplate(name: "T")
        let model = TemplateEditorModel(templateId: id, store: store)
        if case .failure = model.validate() { XCTFail("scaffold should be valid") }
        model.manifestText = #"{"id":"t","name":"T","version":"1","sizes":[],"refresh":900,"params":[],"sources":[]}"#
        if case .success = model.validate() { XCTFail("emptySizes must fail") }
    }

    func testPreviewContextUsesManifestDefaultsAndFirstSize() throws {
        let id = store.createUserTemplate(name: "T")
        let model = TemplateEditorModel(templateId: id, store: store)
        model.manifestText = ##"{"id":"t","name":"T","version":"1.0.0","sizes":["medium"],"refresh":900,"params":[{"key":"accent","type":"color","label":"A","default":"#abc"}],"sources":[]}"##
        let ctx = model.previewContext(data: [:], stale: false)
        XCTAssertEqual(ctx.size, .medium)
        XCTAssertEqual(ctx.params["accent"], "#abc")
    }

    func testSaveDelegatesToStore() throws {
        let id = store.createUserTemplate(name: "T")
        let model = TemplateEditorModel(templateId: id, store: store)
        model.htmlText = "<i>edited</i>"
        try model.save(into: store)
        XCTAssertEqual(try store.html(id: id), "<i>edited</i>")
    }
}
