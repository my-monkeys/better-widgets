import XCTest

final class SharedStoreTests: XCTestCase {
    private var store: SharedStore!
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = try SharedStore(baseURL: tmp)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testInstancesRoundTrip() throws {
        let a = WidgetInstance(id: UUID(), name: "Horloge", templateId: "hello-clock",
                               size: .small, paramValues: ["accent": "#e8590c"])
        try store.saveInstances([a])
        XCTAssertEqual(store.loadInstances(), [a])
    }

    func testLoadInstancesEmptyWhenMissing() {
        XCTAssertEqual(store.loadInstances(), [])
    }

    func testRenderWriteAndURL() throws {
        let id = UUID()
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        try store.writeRender(png, instanceId: id, theme: .dark)
        let url = store.renderURL(instanceId: id, theme: .dark)
        XCTAssertEqual(try Data(contentsOf: url), png)
        XCTAssertTrue(url.lastPathComponent.hasSuffix("-dark.png"))
    }

    func testStateRoundTripAndDefault() throws {
        let id = UUID()
        XCTAssertEqual(store.loadState(instanceId: id), InstanceState())
        var s = InstanceState()
        s.stale = true
        s.lastError = "boom"
        try store.saveState(s, instanceId: id)
        XCTAssertEqual(store.loadState(instanceId: id), s)
    }
}
