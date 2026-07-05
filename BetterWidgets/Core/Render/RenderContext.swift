import Foundation

struct RenderContext {
    let params: [String: String]
    let data: [String: Any]
    let size: WidgetSize
    let theme: Theme
    let stale: Bool
    /// The slide index a rotating template should render (see RotationSpec). `nil` for
    /// non-rotating templates, which then fall back to their own time-based slide logic.
    let slide: Int?

    init(params: [String: String], data: [String: Any], size: WidgetSize,
         theme: Theme, stale: Bool, slide: Int? = nil) {
        self.params = params
        self.data = data
        self.size = size
        self.theme = theme
        self.stale = stale
        self.slide = slide
    }

    /// JSON injected as `window.BW` before the template loads.
    func bwJSON() throws -> String {
        var payload: [String: Any] = [
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
        if let slide { payload["slide"] = slide }
        let json = try JSONSerialization.data(withJSONObject: payload)
        return String(data: json, encoding: .utf8)!
    }
}
