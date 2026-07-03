import AppIntents

struct WidgetInstanceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Widget"
    static let defaultQuery = WidgetInstanceQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct WidgetInstanceQuery: EntityQuery {
    /// Family this query filters on; set per-kind via the intents below.
    var family: WidgetSize?

    init() {}
    init(family: WidgetSize) { self.family = family }

    private func all() -> [WidgetInstanceEntity] {
        SharedStore.appGroup().loadInstances()
            .filter { family == nil || $0.size == family }
            .map { WidgetInstanceEntity(id: $0.id.uuidString, name: $0.name) }
    }

    func entities(for identifiers: [String]) async throws -> [WidgetInstanceEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetInstanceEntity] { all() }
    func defaultResult() async -> WidgetInstanceEntity? { all().first }
}
