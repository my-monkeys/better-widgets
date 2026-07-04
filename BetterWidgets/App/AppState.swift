import Foundation
import SwiftUI

enum InstanceStatus: Equatable {
    case ok, pending, stale, error(String)
}

@MainActor
final class AppState: ObservableObject {
    @Published var instances: [WidgetInstance] = []

    let shared: SharedStore
    let templates: TemplateStore
    let secrets: SecretResolver
    private let scheduler: any InstanceScheduling

    /// Designated init — injectable for tests.
    init(shared: SharedStore, templates: TemplateStore, secrets: SecretResolver,
         scheduler: any InstanceScheduling) {
        self.shared = shared
        self.templates = templates
        self.secrets = secrets
        self.scheduler = scheduler
    }

    /// Real wiring used by the app.
    convenience init() {
        let shared = SharedStore.appGroup()
        let templates = TemplateStore.applicationSupport()
        let permissions = PermissionStore.appGroup()
        let secrets = SecretResolver(backing: KeychainStore())
        let pipeline = RenderPipeline(templates: templates, shared: shared, permissions: permissions,
                                      registry: .standard(), secrets: secrets, engine: RenderEngine(),
                                      reloader: WidgetCenterReloader())
        self.init(shared: shared, templates: templates, secrets: secrets,
                  scheduler: Scheduler(refresher: pipeline, templates: templates))
    }

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
        scheduler.restart(instances: instances)
    }

    func refreshAll() {
        scheduler.refreshAllNow(instances: instances)
    }

    func statusLine(for instance: WidgetInstance) -> String {
        switch status(for: instance.id) {
        case .error(let msg): return "⚠︎ \(instance.name) — \(msg.prefix(40))"
        case .stale: return "◔ \(instance.name) — données périmées"
        case .pending: return "◌ \(instance.name) — en cours"
        case .ok: return "● \(instance.name)"
        }
    }

    // MARK: CRUD

    func createInstance(templateId: String, size: WidgetSize) -> WidgetInstance {
        let name = (try? templates.manifest(id: templateId).name) ?? templateId
        let instance = WidgetInstance(id: UUID(), name: name, templateId: templateId,
                                      size: size, paramValues: [:])
        instances.append(instance)
        persistAndReschedule()
        return instance
    }

    func deleteInstance(_ id: UUID) {
        if let instance = instances.first(where: { $0.id == id }),
           let manifest = try? templates.manifest(id: instance.templateId) {
            secrets.deleteAll(instanceId: id, sources: manifest.sources)
        }
        instances.removeAll { $0.id == id }
        shared.removeInstance(id: id)
        persistAndReschedule()
    }

    @discardableResult
    func duplicateInstance(_ id: UUID) -> WidgetInstance? {
        guard let original = instances.first(where: { $0.id == id }) else { return nil }
        let copy = WidgetInstance(id: UUID(), name: "\(original.name) (copie)",
                                  templateId: original.templateId, size: original.size,
                                  paramValues: original.paramValues)
        instances.append(copy)
        persistAndReschedule()
        return copy
    }

    func updateInstance(_ updated: WidgetInstance) {
        guard let index = instances.firstIndex(where: { $0.id == updated.id }) else { return }
        instances[index] = updated
        persistAndReschedule()
    }

    func status(for id: UUID) -> InstanceStatus {
        let state = shared.loadState(instanceId: id)
        if let error = state.lastError { return .error(error) }
        if state.lastRenderAt == nil { return .pending }
        if state.stale { return .stale }
        return .ok
    }

    private func persistAndReschedule() {
        try? shared.saveInstances(instances)
        scheduler.restart(instances: instances)
    }
}
