import Foundation

struct InstanceState: Codable, Equatable {
    var lastRenderAt: Date?
    var lastFetchAt: Date?
    var stale: Bool = false
    var lastError: String?
}
