import Foundation

enum WidgetSize: String, Codable, CaseIterable {
    case small, medium, large

    var pointSize: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        }
    }

    var kind: String { "bw.\(rawValue)" }
}
