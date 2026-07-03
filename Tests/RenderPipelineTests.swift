import XCTest
// No module import: Core sources are compiled directly into the test target.

final class RenderPipelineTests: XCTestCase {
    private var tmp: URL!
    private var shared: SharedStore!
    private var templates: TemplateStore!
    private var permissions: PermissionStore!

    final class FakeEngine: Rendering {
        var calls: [(theme: Theme, stale: Bool)] = []
        var shouldThrow = false
        /// 1-based render call to throw on (e.g. 2 = fail on the second theme).
        /// nil preserves the default `shouldThrow`-only behavior.
        var throwOnCallNumber: Int?
        private var callCount = 0
        func render(html: String, baseURL: URL?, context: RenderContext) async throws -> Data {
            callCount += 1
            if shouldThrow || callCount == throwOnCallNumber { throw RenderError.timeout }
            calls.append((context.theme, context.stale))
            return Data("png-\(context.theme.rawValue)".utf8)
        }
    }

    final class FakeReloader: WidgetReloading {
        var kinds: [String] = []
        func reload(kind: String) { kinds.append(kind) }
    }

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        shared = try SharedStore(baseURL: tmp.appendingPathComponent("shared"))
        permissions = try PermissionStore(baseURL: tmp.appendingPathComponent("perms"))
        let tplRoot = tmp.appendingPathComponent("templates")
        try FileManager.default.createDirectory(at: tplRoot.appendingPathComponent("clock"),
                                                withIntermediateDirectories: true)
        try ##"{ "id": "clock", "name": "C", "version": "1.0.0", "sizes": ["small"], "refresh": 60, "params": [{"key":"accent","type":"color","label":"A","default":"#fff"}], "sources": [{"key":"sys","type":"system"}] }"##
            .write(to: tplRoot.appendingPathComponent("clock/manifest.json"), atomically: true, encoding: .utf8)
        try "<html></html>".write(to: tplRoot.appendingPathComponent("clock/index.html"),
                                  atomically: true, encoding: .utf8)
        templates = TemplateStore(rootURL: tplRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeInstance() -> WidgetInstance {
        WidgetInstance(id: UUID(), name: "test", templateId: "clock", size: .small, paramValues: [:])
    }

    func testRefreshWritesBothThemesAndReloads() async throws {
        let engine = FakeEngine()
        let reloader = FakeReloader()
        let pipeline = RenderPipeline(templates: templates, shared: shared, permissions: permissions,
                                      registry: .standard(), engine: engine, reloader: reloader)
        let instance = makeInstance()
        await pipeline.refresh(instance)

        XCTAssertEqual(engine.calls.map(\.theme), [.light, .dark])
        XCTAssertEqual(try Data(contentsOf: shared.renderURL(instanceId: instance.id, theme: .light)),
                       Data("png-light".utf8))
        XCTAssertEqual(reloader.kinds, ["bw.small"])
        let state = shared.loadState(instanceId: instance.id)
        XCTAssertNotNil(state.lastRenderAt)
        XCTAssertFalse(state.stale)
        XCTAssertNil(state.lastError)
    }

    func testRenderFailureRecordsErrorAndSkipsReload() async {
        let engine = FakeEngine()
        engine.shouldThrow = true
        let reloader = FakeReloader()
        let pipeline = RenderPipeline(templates: templates, shared: shared, permissions: permissions,
                                      registry: .standard(), engine: engine, reloader: reloader)
        let instance = makeInstance()
        await pipeline.refresh(instance)

        XCTAssertEqual(reloader.kinds, [])
        XCTAssertNotNil(shared.loadState(instanceId: instance.id).lastError)
    }

    func testSecondThemeRenderFailureLeavesPreviousPNGsIntact() async throws {
        let engine = FakeEngine()
        engine.throwOnCallNumber = 2 // light (1st) succeeds, dark (2nd) throws
        let reloader = FakeReloader()
        let pipeline = RenderPipeline(templates: templates, shared: shared, permissions: permissions,
                                      registry: .standard(), engine: engine, reloader: reloader)
        let instance = makeInstance()

        try shared.writeRender(Data("OLD-light".utf8), instanceId: instance.id, theme: .light)
        try shared.writeRender(Data("OLD-dark".utf8), instanceId: instance.id, theme: .dark)

        await pipeline.refresh(instance)

        XCTAssertEqual(try Data(contentsOf: shared.renderURL(instanceId: instance.id, theme: .light)),
                       Data("OLD-light".utf8))
        XCTAssertEqual(try Data(contentsOf: shared.renderURL(instanceId: instance.id, theme: .dark)),
                       Data("OLD-dark".utf8))
        XCTAssertEqual(reloader.kinds, [])
        XCTAssertNotNil(shared.loadState(instanceId: instance.id).lastError)
    }

    func testFetchFailureStillRendersWithStaleFlagAndReloads() async throws {
        let engine = FakeEngine()
        let reloader = FakeReloader()
        // No provider registered for the "system" source type used by the clock template's
        // manifest, so fetchAll reports it in failedKeys without throwing — this must still
        // produce a full stale render+reload, not an aborted refresh.
        let registry = DataProviderRegistry(providers: [])
        let pipeline = RenderPipeline(templates: templates, shared: shared, permissions: permissions,
                                      registry: registry, engine: engine, reloader: reloader)
        let instance = makeInstance()
        await pipeline.refresh(instance)

        XCTAssertEqual(engine.calls.map(\.stale), [true, true])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: shared.renderURL(instanceId: instance.id, theme: .light).path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: shared.renderURL(instanceId: instance.id, theme: .dark).path))
        XCTAssertEqual(reloader.kinds, ["bw.small"])
        let state = shared.loadState(instanceId: instance.id)
        XCTAssertTrue(state.stale)
        XCTAssertNil(state.lastError)
    }

    func testMissingTemplateRecordsError() async {
        let pipeline = RenderPipeline(templates: templates, shared: shared, permissions: permissions,
                                      registry: .standard(), engine: FakeEngine(), reloader: FakeReloader())
        let instance = WidgetInstance(id: UUID(), name: "x", templateId: "ghost",
                                      size: .small, paramValues: [:])
        await pipeline.refresh(instance)
        XCTAssertNotNil(shared.loadState(instanceId: instance.id).lastError)
    }

    private func writeCalendarTemplate() throws {
        let dir = tmp.appendingPathComponent("templates/calnews")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"{ "id": "calnews", "name": "Cal", "version": "1.0.0", "sizes": ["small"], "refresh": 300, "params": [], "sources": [{"key":"cal","type":"calendar"}] }"#
            .write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "<html></html>".write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }

    /// A consent-requiring source that is NOT granted must be skipped (not fetched)
    /// and injected as a __denied marker — without marking the instance stale.
    func testUngrantedConsentSourceIsDeniedNotFetched() async throws {
        try writeCalendarTemplate()
        final class RecordingEngine: Rendering {
            var lastData: [String: Any] = [:]
            func render(html: String, baseURL: URL?, context: RenderContext) async throws -> Data {
                lastData = context.data
                return Data("png".utf8)
            }
        }
        let engine = RecordingEngine()
        let reloader = FakeReloader()
        // .standard() DOES have a calendar provider; an ungranted source must still never
        // be fetched. If the pipeline tried, it would land in failedKeys → stale. It must not try.
        let pipeline = RenderPipeline(templates: templates, shared: shared, permissions: permissions,
                                      registry: .standard(), engine: engine, reloader: reloader)
        let instance = WidgetInstance(id: UUID(), name: "c", templateId: "calnews",
                                      size: .small, paramValues: [:])
        await pipeline.refresh(instance)

        let cal = engine.lastData["cal"] as? [String: Any]
        XCTAssertEqual(cal?["__denied"] as? Bool, true)
        XCTAssertFalse(shared.loadState(instanceId: instance.id).stale, "denied ≠ stale")
        XCTAssertNil(shared.loadState(instanceId: instance.id).lastError)
        XCTAssertEqual(reloader.kinds, ["bw.small"])
    }

    /// Once granted, the source is passed to the registry. The calendar provider's fetcher
    /// throws here, so the fetch lands in failedKeys → stale, proving it was actually attempted
    /// rather than denied. A throwing fake fetcher keeps EventKit/TCC out of the test suite.
    func testGrantedConsentSourceIsAttempted() async throws {
        try writeCalendarTemplate()
        let instance = WidgetInstance(id: UUID(), name: "c", templateId: "calnews",
                                      size: .small, paramValues: [:])
        try permissions.grant(type: "calendar", instanceId: instance.id)
        struct ThrowingFetcher: EventFetching {
            func upcomingEvents(within days: Int) async throws -> [CalendarEventDTO] {
                throw DataProviderError.missingConfig("no access")
            }
        }
        let registry = DataProviderRegistry(providers: [CalendarDataProvider(fetcher: ThrowingFetcher())])
        let pipeline = RenderPipeline(templates: templates, shared: shared, permissions: permissions,
                                      registry: registry, engine: FakeEngine(), reloader: FakeReloader())
        await pipeline.refresh(instance)
        // Granted → the pipeline attempts the fetch; the fetcher throws → failedKey → stale.
        XCTAssertTrue(shared.loadState(instanceId: instance.id).stale)
    }
}
