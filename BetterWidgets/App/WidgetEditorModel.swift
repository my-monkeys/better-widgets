import Foundation
import SwiftUI

/// Working copy of an instance being edited: params + secrets + preview size/theme,
/// isolated from the real instance until save.
@MainActor
final class WidgetEditorModel: ObservableObject {
    let instance: WidgetInstance
    let manifest: TemplateManifest
    private let secrets: SecretResolver

    @Published var paramValues: [String: String]
    @Published var secretValues: [String: String]   // "<sourceKey>.<header>" -> value
    @Published var previewSize: WidgetSize
    @Published var previewTheme: Theme = .light

    init(instance: WidgetInstance, manifest: TemplateManifest, secrets: SecretResolver) {
        self.instance = instance
        self.manifest = manifest
        self.secrets = secrets
        self.paramValues = instance.paramValues
        self.previewSize = instance.size
        var seeded: [String: String] = [:]
        for req in Self.secretRequirements(from: manifest) {
            seeded["\(req.sourceKey).\(req.header)"] =
                secrets.get(instanceId: instance.id, sourceKey: req.sourceKey, header: req.header) ?? ""
        }
        self.secretValues = seeded
    }

    static func secretRequirements(from manifest: TemplateManifest) -> [(sourceKey: String, header: String)] {
        manifest.sources.filter { $0.type == "json" }.flatMap { source in
            (source.config ?? [:]).keys.filter { $0.hasPrefix("secret.") }
                .map { (source.key, String($0.dropFirst("secret.".count))) }
        }
    }

    var secretRequirements: [(sourceKey: String, header: String)] { Self.secretRequirements(from: manifest) }

    func mergedParams() -> [String: String] {
        var params: [String: String] = [:]
        for spec in manifest.params { params[spec.key] = spec.default }
        params.merge(paramValues) { _, working in working }
        return params
    }

    func previewContext(data: [String: Any], stale: Bool) -> RenderContext {
        RenderContext(params: mergedParams(), data: data, size: previewSize, theme: previewTheme, stale: stale)
    }

    func updatedInstance() -> WidgetInstance {
        var copy = instance
        copy.paramValues = paramValues
        return copy
    }

    func persistSecrets(instanceId: UUID) {
        for (composite, value) in secretValues where !value.isEmpty {
            let parts = composite.split(separator: ".", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            secrets.set(value, instanceId: instanceId, sourceKey: parts[0], header: parts[1])
        }
    }
}
