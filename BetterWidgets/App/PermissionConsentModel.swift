import Foundation
import SwiftUI

/// Drives the per-instance consent screen: which consent-requiring source types
/// a template declares, and whether the user granted them (PermissionStore).
@MainActor
final class PermissionConsentModel: ObservableObject {
    let instanceId: UUID
    let requiredTypes: [String]
    private let permissions: PermissionStore
    @Published var granted: Set<String>

    init(instanceId: UUID, manifest: TemplateManifest, permissions: PermissionStore) {
        self.instanceId = instanceId
        self.permissions = permissions
        self.requiredTypes = Array(Set(manifest.sources.filter { $0.requiresConsent }.map { $0.type })).sorted()
        self.granted = permissions.grantedTypes(instanceId: instanceId)
    }

    func isGranted(_ type: String) -> Bool { granted.contains(type) }

    func setGranted(_ type: String, _ on: Bool) {
        if on { granted.insert(type) } else { granted.remove(type) }
        try? permissions.setGrantedTypes(granted, instanceId: instanceId)
    }

    static func label(for type: String) -> String {
        switch type {
        case "calendar": return "Calendrier"
        case "weather": return "Météo"
        default: return type
        }
    }
}
