import Foundation

struct WidgetInstance: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    let templateId: String
    var size: WidgetSize
    var paramValues: [String: String]
}
