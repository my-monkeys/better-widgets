import Foundation

enum Theme: String, Codable {
    case light, dark
}

struct RenderContext {
    let params: [String: String]
    let data: [String: Any]
    let size: WidgetSize
    let theme: Theme
    let stale: Bool

    /// JSON injected as `window.BW` before the template loads.
    func bwJSON() throws -> String {
        let payload: [String: Any] = [
            "params": params,
            "data": data,
            "size": [
                "w": Int(size.pointSize.width),
                "h": Int(size.pointSize.height),
                "family": size.rawValue,
            ],
            "theme": theme.rawValue,
            "stale": stale,
        ]
        let json = try JSONSerialization.data(withJSONObject: payload)
        return String(data: json, encoding: .utf8)!
    }
}
