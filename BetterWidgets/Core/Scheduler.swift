import Foundation

protocol Refreshing {
    func refresh(_ instance: WidgetInstance) async
}

extension RenderPipeline: Refreshing {}

/// Drives periodic refreshes. All refreshes flow through one serial queue
/// (single offscreen webview — see spec §13 "pool de 1-2 webviews").
@MainActor
final class Scheduler {
    private let refresher: any Refreshing
    private let templates: TemplateStore
    private var timers: [UUID: Timer] = [:]
    private var queueContinuation: AsyncStream<WidgetInstance>.Continuation?
    private var worker: Task<Void, Never>?

    private static let fallbackInterval: TimeInterval = 300

    init(refresher: any Refreshing, templates: TemplateStore) {
        self.refresher = refresher
        self.templates = templates
        let (stream, continuation) = AsyncStream.makeStream(of: WidgetInstance.self)
        queueContinuation = continuation
        worker = Task { [refresher] in
            for await instance in stream {
                await refresher.refresh(instance)
            }
        }
    }

    func start(instances: [WidgetInstance]) {
        stopTimers()
        for instance in instances {
            enqueue(instance)
            let interval = TimeInterval((try? templates.manifest(id: instance.templateId).refresh)
                                        ?? Int(Self.fallbackInterval))
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.enqueue(instance) }
            }
            timer.tolerance = interval * 0.1
            timers[instance.id] = timer
        }
    }

    func refreshAllNow(instances: [WidgetInstance]) {
        instances.forEach(enqueue)
    }

    func stop() {
        stopTimers()
        queueContinuation?.finish()
        worker?.cancel()
    }

    private func enqueue(_ instance: WidgetInstance) {
        queueContinuation?.yield(instance)
    }

    private func stopTimers() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
    }
}
