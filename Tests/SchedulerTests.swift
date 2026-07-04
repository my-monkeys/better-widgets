import XCTest
// No module import: Core sources are compiled directly into the test target.

final class SchedulerTests: XCTestCase {
    final class CountingRefresher: Refreshing, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var count = 0
        func refresh(_ instance: WidgetInstance) async {
            lock.lock(); count += 1; lock.unlock()
        }
        var safeCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    @MainActor
    func testStartTriggersImmediateRefresh() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let templates = TemplateStore(rootURL: tmp)
        let refresher = CountingRefresher()
        let scheduler = Scheduler(refresher: refresher, templates: templates)
        let instance = WidgetInstance(id: UUID(), name: "t", templateId: "ghost",
                                      size: .small, paramValues: [:])
        scheduler.start(instances: [instance])
        try await Task.sleep(for: .milliseconds(300))
        scheduler.stop()
        XCTAssertGreaterThanOrEqual(refresher.safeCount, 1)
    }

    @MainActor
    func testRefreshAllNowRefreshesEveryInstance() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let refresher = CountingRefresher()
        let scheduler = Scheduler(refresher: refresher, templates: TemplateStore(rootURL: tmp))
        let a = WidgetInstance(id: UUID(), name: "a", templateId: "g", size: .small, paramValues: [:])
        let b = WidgetInstance(id: UUID(), name: "b", templateId: "g", size: .medium, paramValues: [:])
        scheduler.refreshAllNow(instances: [a, b])
        try await Task.sleep(for: .milliseconds(300))
        scheduler.stop()
        XCTAssertEqual(refresher.safeCount, 2)
    }

    @MainActor
    func testRestartAfterStopStillRefreshes() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let refresher = CountingRefresher()
        let scheduler = Scheduler(refresher: refresher, templates: TemplateStore(rootURL: tmp))
        scheduler.stop()                          // finish the initial stream/worker
        let a = WidgetInstance(id: UUID(), name: "a", templateId: "g", size: .small, paramValues: [:])
        scheduler.restart(instances: [a])         // must recreate the worker and refresh
        try await Task.sleep(for: .milliseconds(300))
        scheduler.stop()
        XCTAssertGreaterThanOrEqual(refresher.safeCount, 1, "restart must recreate the queue so enqueues run")
    }
}
