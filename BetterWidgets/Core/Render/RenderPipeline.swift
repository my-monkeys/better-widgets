import Foundation
import WidgetKit

protocol Rendering {
    @MainActor func render(html: String, baseURL: URL?, context: RenderContext) async throws -> Data
}

extension RenderEngine: Rendering {}

protocol WidgetReloading {
    func reload(kind: String)
}

struct WidgetCenterReloader: WidgetReloading {
    func reload(kind: String) {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}

/// Orchestrates one refresh: fetch data → render light+dark → write to shared store → reload widgets.
/// Never throws: failures are recorded in InstanceState.lastError.
final class RenderPipeline {
    private let templates: TemplateStore
    private let shared: SharedStore
    private let permissions: PermissionStore
    private let registry: DataProviderRegistry
    private let engine: any Rendering
    private let reloader: any WidgetReloading

    init(templates: TemplateStore, shared: SharedStore, permissions: PermissionStore,
         registry: DataProviderRegistry, engine: any Rendering, reloader: any WidgetReloading) {
        self.templates = templates
        self.shared = shared
        self.permissions = permissions
        self.registry = registry
        self.engine = engine
        self.reloader = reloader
    }

    func refresh(_ instance: WidgetInstance) async {
        var state = shared.loadState(instanceId: instance.id)
        do {
            let manifest = try templates.manifest(id: instance.templateId)
            let html = try templates.html(id: instance.templateId)
            let baseURL = templates.templateDirectory(id: instance.templateId)

            // Defaults from manifest, overridden by instance values.
            var params: [String: String] = [:]
            for spec in manifest.params { params[spec.key] = spec.default }
            params.merge(instance.paramValues) { _, instanceValue in instanceValue }

            // Partition sources by permission: consent-requiring types that the
            // user hasn't granted are never fetched — they're injected as a
            // __denied marker (which is intentional, not a fetch failure).
            let granted = permissions.grantedTypes(instanceId: instance.id)
            let allowed = manifest.sources.filter { !$0.requiresConsent || granted.contains($0.type) }
            let denied = manifest.sources.filter { $0.requiresConsent && !granted.contains($0.type) }

            let fetch = await registry.fetchAll(sources: allowed, paramValues: params)
            var data = fetch.data
            for source in denied { data[source.key] = ["__denied": true] }

            state.lastFetchAt = Date()
            state.stale = !fetch.failedKeys.isEmpty

            // Render both themes before writing anything: if dark fails after light
            // succeeded, we must not leave a half-updated pair — the previous PNGs
            // (both themes) stay untouched on any render failure.
            var renders: [(theme: Theme, png: Data)] = []
            for theme in [Theme.light, Theme.dark] {
                let context = RenderContext(params: params, data: data,
                                            size: instance.size, theme: theme, stale: state.stale)
                let png = try await engine.render(html: html, baseURL: baseURL, context: context)
                renders.append((theme, png))
            }
            for render in renders {
                try shared.writeRender(render.png, instanceId: instance.id, theme: render.theme)
            }
            state.lastRenderAt = Date()
            state.lastError = nil
            try shared.saveState(state, instanceId: instance.id)
            reloader.reload(kind: instance.size.kind)
        } catch {
            state.lastError = String(describing: error)
            try? shared.saveState(state, instanceId: instance.id)
        }
    }
}
