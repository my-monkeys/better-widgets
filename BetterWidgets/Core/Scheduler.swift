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
        spawnWorker()
    }

    private func spawnWorker() {
        let (stream, continuation) = AsyncStream.makeStream(of: WidgetInstance.self)
        queueContinuation = continuation
        worker = Task { [refresher] in
            for await instance in stream {
                await refresher.refresh(instance)
            }
        }
    }

    /// Tears down and recreates the serial queue, then starts timers/refreshes.
    /// Needed because `stop()` finishes the stream — a plain `start()` afterwards
    /// would enqueue into a dead continuation (no-op). Called on every instance-list change.
    func restart(instances: [WidgetInstance]) {
        stopTimers()
        queueContinuation?.finish()
        worker?.cancel()
        spawnWorker()
        start(instances: instances)
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

@MainActor
protocol InstanceScheduling {
    func restart(instances: [WidgetInstance])
    func refreshAllNow(instances: [WidgetInstance])
}

extension Scheduler: InstanceScheduling {}
