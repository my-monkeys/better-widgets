import Foundation

/// Per-instance record of which consent-requiring source types the user granted.
/// Lives in the App Group so a future settings UI and the render pipeline share it.
final class PermissionStore {
    static let appGroupID = "5C67TFSJ2B.betterwidgets"

    private let fileURL: URL

    init(baseURL: URL) throws {
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        fileURL = baseURL.appendingPathComponent("grants.json")
    }

    static func appGroup() -> PermissionStore {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            fatalError("App Group \(appGroupID) unavailable — check entitlements")
        }
        return try! PermissionStore(baseURL: container.appendingPathComponent("Store"))
    }

    private func load() -> [String: [String]] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
    }

    private func save(_ grants: [String: [String]]) throws {
        try JSONEncoder().encode(grants).write(to: fileURL, options: .atomic)
    }

    func grantedTypes(instanceId: UUID) -> Set<String> {
        Set(load()[instanceId.uuidString] ?? [])
    }

    func setGrantedTypes(_ types: Set<String>, instanceId: UUID) throws {
        var grants = load()
        grants[instanceId.uuidString] = Array(types).sorted()
        try save(grants)
    }

    func grant(type: String, instanceId: UUID) throws {
        var types = grantedTypes(instanceId: instanceId)
        types.insert(type)
        try setGrantedTypes(types, instanceId: instanceId)
    }
}
