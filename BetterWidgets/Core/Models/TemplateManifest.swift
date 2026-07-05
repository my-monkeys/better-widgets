import Foundation

enum ManifestError: Error, Equatable {
    case invalidJSON(String)
    case emptySizes
    case refreshTooSmall
    case duplicateParamKey(String)
    case duplicateSourceKey(String)
    case unknownSourceType(String)
    case invalidRotation
}

/// Opt-in slide rotation. A template with `rotation` renders `slides` pre-rendered frames
/// (indexed via `window.BW.slide`); the widget extension advances through them every
/// `interval` seconds via a multi-entry timeline, so the desktop widget rotates on its own
/// without spending WidgetKit's throttled reload budget on every slide change.
struct RotationSpec: Codable, Equatable {
    let slides: Int
    let interval: Int   // seconds each slide is shown
}

enum ParamType: String, Codable, Equatable {
    case string, color, number, url
}

struct ParamSpec: Codable, Equatable {
    let key: String
    let type: ParamType
    let label: String
    let `default`: String?
}

struct SourceSpec: Codable, Equatable {
    static let knownTypes: Set<String> = ["json", "system", "rss", "calendar", "weather"]
    static let consentRequiredTypes: Set<String> = ["calendar", "weather"]
    let key: String
    let type: String
    let config: [String: String]?

    var requiresConsent: Bool { Self.consentRequiredTypes.contains(type) }
}

struct LinkSpec: Codable, Equatable {
    let rect: String
    let url: String
}

struct TemplateManifest: Codable, Equatable {
    static let minimumRefresh = 30

    let id: String
    let name: String
    let version: String
    let sizes: [WidgetSize]
    let refresh: Int
    let params: [ParamSpec]
    let sources: [SourceSpec]
    let links: [LinkSpec]?
    let rotation: RotationSpec?

    static func validated(from data: Data) throws -> TemplateManifest {
        let manifest: TemplateManifest
        do {
            manifest = try JSONDecoder().decode(TemplateManifest.self, from: data)
        } catch {
            throw ManifestError.invalidJSON(String(describing: error))
        }
        guard !manifest.sizes.isEmpty else { throw ManifestError.emptySizes }
        guard manifest.refresh >= minimumRefresh else { throw ManifestError.refreshTooSmall }
        var paramKeys = Set<String>()
        for p in manifest.params where !paramKeys.insert(p.key).inserted {
            throw ManifestError.duplicateParamKey(p.key)
        }
        var sourceKeys = Set<String>()
        for s in manifest.sources {
            guard sourceKeys.insert(s.key).inserted else { throw ManifestError.duplicateSourceKey(s.key) }
            guard SourceSpec.knownTypes.contains(s.type) else { throw ManifestError.unknownSourceType(s.type) }
        }
        if let rotation = manifest.rotation {
            guard rotation.slides >= 1, rotation.interval >= 1 else { throw ManifestError.invalidRotation }
        }
        return manifest
    }
}
