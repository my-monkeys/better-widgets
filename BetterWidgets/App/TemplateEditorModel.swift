import Foundation
import SwiftUI

/// Working copy of a template's source (index.html + raw manifest.json) being
/// edited in advanced mode. Validation is strict only on save; the preview uses
/// the last parsable manifest.
@MainActor
final class TemplateEditorModel: ObservableObject {
    enum Tab { case html, manifest }

    let templateId: String
    @Published var htmlText: String
    @Published var manifestText: String
    @Published var tab: Tab = .html

    init(templateId: String, store: TemplateStore) {
        self.templateId = templateId
        self.htmlText = (try? store.html(id: templateId)) ?? ""
        let manifestURL = store.templateDirectory(id: templateId).appendingPathComponent("manifest.json")
        self.manifestText = (try? String(contentsOf: manifestURL, encoding: .utf8)) ?? ""
    }

    func validate() -> Result<TemplateManifest, Error> {
        Result { try TemplateManifest.validated(from: Data(manifestText.utf8)) }
    }

    func previewManifest() -> TemplateManifest? { try? validate().get() }

    func previewContext(data: [String: Any], stale: Bool) -> RenderContext {
        let manifest = previewManifest()
        var params: [String: String] = [:]
        for spec in manifest?.params ?? [] { params[spec.key] = spec.default }
        let size = manifest?.sizes.first ?? .small
        return RenderContext(params: params, data: data, size: size, theme: .light, stale: stale)
    }

    func save(into store: TemplateStore) throws {
        try store.saveTemplate(id: templateId, html: htmlText, manifestJSON: manifestText)
    }

    func errorMessage(_ error: Error) -> String {
        guard let e = error as? ManifestError else { return "Manifest invalide." }
        switch e {
        case .invalidJSON: return "JSON invalide (syntaxe)."
        case .emptySizes: return "Le champ « sizes » ne peut pas être vide."
        case .refreshTooSmall: return "« refresh » doit être ≥ 30 secondes."
        case .duplicateParamKey(let k): return "Clé de paramètre en double : \(k)."
        case .duplicateSourceKey(let k): return "Clé de source en double : \(k)."
        case .unknownSourceType(let t): return "Type de source inconnu : \(t)."
        }
    }
}
