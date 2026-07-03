import Foundation

struct RSSDataProvider: DataProvider {
    static let type = "rss"
    let minimumInterval: TimeInterval = 900
    let urlSession: URLSession

    func fetch(spec: SourceSpec, paramValues: [String: String]) async throws -> Any {
        guard let rawURL = spec.config?["url"] else {
            throw DataProviderError.missingConfig("rss source '\(spec.key)' requires config.url")
        }
        let urlString = substituteParams(rawURL, params: paramValues)
        guard let url = URL(string: urlString), url.scheme == "https" else {
            throw DataProviderError.badURL(urlString)
        }
        let (data, response) = try await urlSession.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DataProviderError.httpError(http.statusCode)
        }
        let parsed = RSSFeedParser.parse(data)
        let items: [[String: Any]] = parsed.items.map { item in
            var dict: [String: Any] = ["title": item.title, "link": item.link]
            if let published = item.published { dict["published"] = published }
            if let summary = item.summary { dict["summary"] = summary }
            return dict
        }
        var result: [String: Any] = ["items": items]
        if let title = parsed.title { result["title"] = title }
        return result
    }
}
