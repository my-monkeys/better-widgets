import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var instances: [WidgetInstance] = []

    let shared = SharedStore.appGroup()
    let templates = TemplateStore.applicationSupport()
    let permissions = PermissionStore.appGroup()
    private lazy var pipeline = RenderPipeline(
        templates: templates, shared: shared, permissions: permissions,
        registry: .standard(), engine: RenderEngine(), reloader: WidgetCenterReloader())
    private lazy var scheduler = Scheduler(refresher: pipeline, templates: templates)

    func bootstrap() {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("templates") {
            try? templates.installBundledTemplates(from: bundled)
        }
        instances = shared.loadInstances()
        if instances.isEmpty {
            let demo = WidgetInstance(id: UUID(), name: "Horloge", templateId: "hello-clock",
                                      size: .small, paramValues: [:])
            instances = [demo]
            try? shared.saveInstances(instances)
        }
        scheduler.start(instances: instances)
    }

    func refreshAll() {
        scheduler.refreshAllNow(instances: instances)
    }

    func statusLine(for instance: WidgetInstance) -> String {
        let state = shared.loadState(instanceId: instance.id)
        if let error = state.lastError { return "⚠︎ \(instance.name) — \(error.prefix(40))" }
        if state.stale { return "◔ \(instance.name) — données périmées" }
        return "● \(instance.name)"
    }
}
