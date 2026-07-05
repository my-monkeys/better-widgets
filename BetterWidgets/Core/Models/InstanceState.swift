import Foundation

struct InstanceState: Codable, Equatable {
    var lastRenderAt: Date?
    var lastFetchAt: Date?
    var stale: Bool = false
    var lastError: String?
    /// Set when the rendered template rotates: the widget extension reads these to build a
    /// multi-entry rotating timeline. Both nil for a non-rotating (single-frame) instance.
    var slideCount: Int?
    var slideInterval: Int?
}
