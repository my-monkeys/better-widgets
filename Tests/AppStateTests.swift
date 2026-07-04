import XCTest

@MainActor
final class AppStateTests: XCTestCase {
    private var tmp: URL!
    private var shared: SharedStore!
    private var templates: TemplateStore!

    final class SpyScheduler: InstanceScheduling {
        var restarted: [[WidgetInstance]] = []
        var refreshed: [[WidgetInstance]] = []
        func restart(instances: [WidgetInstance]) { restarted.append(instances) }
        func refreshAllNow(instances: [WidgetInstance]) { refreshed.append(instances) }
    }

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        shared = try SharedStore(baseURL: tmp.appendingPathComponent("shared"))
        let tplRoot = tmp.appendingPathComponent("templates")
        try FileManager.default.createDirectory(at: tplRoot.appendingPathComponent("hello-clock"),
                                                withIntermediateDirectories: true)
        try #"{ "id": "hello-clock", "name": "Horloge", "version": "1.0.0", "sizes": ["small","medium"], "refresh": 60, "params": [], "sources": [] }"#
            .write(to: tplRoot.appendingPathComponent("hello-clock/manifest.json"), atomically: true, encoding: .utf8)
        try "<html></html>".write(to: tplRoot.appendingPathComponent("hello-clock/index.html"),
                                  atomically: true, encoding: .utf8)
        templates = TemplateStore(rootURL: tplRoot)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func makeState() -> (AppState, SpyScheduler) {
        let spy = SpyScheduler()
        return (AppState(shared: shared, templates: templates, scheduler: spy), spy)
    }

    func testCreateInstanceUsesTemplateNameAndPersists() {
        let (state, spy) = makeState()
        let created = state.createInstance(templateId: "hello-clock", size: .medium)
        XCTAssertEqual(created.name, "Horloge")
        XCTAssertEqual(created.size, .medium)
        XCTAssertTrue(state.instances.contains(created))
        XCTAssertEqual(shared.loadInstances(), state.instances)  // persisted
        XCTAssertEqual(spy.restarted.last, state.instances)      // scheduler restarted with new list
    }

    func testDeleteInstanceRemovesAndCleansStore() throws {
        let (state, spy) = makeState()
        let a = state.createInstance(templateId: "hello-clock", size: .small)
        try shared.writeRender(Data("x".utf8), instanceId: a.id, theme: .light)
        state.deleteInstance(a.id)
        XCTAssertFalse(state.instances.contains(a))
        XCTAssertEqual(shared.loadInstances(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: shared.renderURL(instanceId: a.id, theme: .light).path))
        XCTAssertEqual(spy.restarted.last, [])
    }

    func testDuplicateInstance() {
        let (state, _) = makeState()
        let a = state.createInstance(templateId: "hello-clock", size: .small)
        let dup = state.duplicateInstance(a.id)
        XCTAssertNotNil(dup)
        XCTAssertNotEqual(dup!.id, a.id)
        XCTAssertEqual(dup!.name, "Horloge (copie)")
        XCTAssertEqual(dup!.size, a.size)
        XCTAssertEqual(state.instances.count, 2)
    }

    func testStatusMapping() throws {
        let (state, _) = makeState()
        let a = state.createInstance(templateId: "hello-clock", size: .small)
        // Never rendered (no state file → lastRenderAt nil): pending, not ok.
        XCTAssertEqual(state.status(for: a.id), .pending)
        var rendered = InstanceState(); rendered.lastRenderAt = Date()
        try shared.saveState(rendered, instanceId: a.id)
        XCTAssertEqual(state.status(for: a.id), .ok)
        var s = InstanceState(); s.lastRenderAt = Date(); s.stale = true
        try shared.saveState(s, instanceId: a.id)
        XCTAssertEqual(state.status(for: a.id), .stale)
        var e = InstanceState(); e.lastError = "boom"
        try shared.saveState(e, instanceId: a.id)
        XCTAssertEqual(state.status(for: a.id), .error("boom"))
    }
}
