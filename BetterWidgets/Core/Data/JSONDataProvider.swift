import Foundation

struct JSONDataProvider: DataProvider {
    static let type = "json"
    let minimumInterval: TimeInterval = 60
    let urlSession: URLSession

    func fetch(spec: SourceSpec, paramValues: [String: String]) async throws -> Any {
        guard let rawURL = spec.config?["url"] else {
            throw DataProviderError.missingConfig("json source '\(spec.key)' requires config.url")
        }
        let urlString = substituteParams(rawURL, params: paramValues)
        guard let url = URL(string: urlString), url.scheme == "https" else {
            throw DataProviderError.badURL(urlString)
        }
        var request = URLRequest(url: url)
        for (header, value) in spec.config ?? [:] where header.hasPrefix("header.") {
            request.setValue(substituteParams(value, params: paramValues),
                             forHTTPHeaderField: String(header.dropFirst("header.".count)))
        }
        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DataProviderError.httpError(http.statusCode)
        }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}
