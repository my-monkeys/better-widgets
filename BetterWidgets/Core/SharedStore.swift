import Foundation

/// Contract between the app (writer) and the widget extension (reader).
/// Layout: instances.json / renders/<uuid>-<theme>.png / state/<uuid>.json
final class SharedStore {
    static let appGroupID = "5C67TFSJ2B.betterwidgets"

    private let baseURL: URL
    private var rendersURL: URL { baseURL.appendingPathComponent("renders") }
    private var stateURL: URL { baseURL.appendingPathComponent("state") }
    private var instancesURL: URL { baseURL.appendingPathComponent("instances.json") }

    init(baseURL: URL) throws {
        self.baseURL = baseURL
        for dir in [baseURL, rendersURL, stateURL] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static func appGroup() -> SharedStore {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            fatalError("App Group \(appGroupID) unavailable — check entitlements")
        }
        return try! SharedStore(baseURL: container.appendingPathComponent("Store"))
    }

    // MARK: Instances

    func loadInstances() -> [WidgetInstance] {
        guard let data = try? Data(contentsOf: instancesURL) else { return [] }
        return (try? JSONDecoder().decode([WidgetInstance].self, from: data)) ?? []
    }

    func saveInstances(_ instances: [WidgetInstance]) throws {
        try JSONEncoder().encode(instances).write(to: instancesURL, options: .atomic)
    }

    // MARK: Renders

    func renderURL(instanceId: UUID, theme: Theme) -> URL {
        rendersURL.appendingPathComponent("\(instanceId.uuidString)-\(theme.rawValue).png")
    }

    func writeRender(_ png: Data, instanceId: UUID, theme: Theme) throws {
        try png.write(to: renderURL(instanceId: instanceId, theme: theme), options: .atomic)
    }

    // MARK: State

    func loadState(instanceId: UUID) -> InstanceState {
        let url = stateURL.appendingPathComponent("\(instanceId.uuidString).json")
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(InstanceState.self, from: data) else {
            return InstanceState()
        }
        return state
    }

    func saveState(_ state: InstanceState, instanceId: UUID) throws {
        let url = stateURL.appendingPathComponent("\(instanceId.uuidString).json")
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }

    // MARK: Removal

    /// Deletes the two render PNGs and the state file for an instance. No-op if absent.
    func removeInstance(id: UUID) {
        let urls = [
            renderURL(instanceId: id, theme: .light),
            renderURL(instanceId: id, theme: .dark),
            stateURL.appendingPathComponent("\(id.uuidString).json"),
        ]
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
