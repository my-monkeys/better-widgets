import Foundation

struct FetchResult {
    let data: [String: Any]
    let failedKeys: [String]
}

final class DataProviderRegistry {
    private let providersByType: [String: any DataProvider]

    init(providers: [any DataProvider]) {
        providersByType = Dictionary(uniqueKeysWithValues: providers.map { (Swift.type(of: $0).type, $0) })
    }

    static func standard(urlSession: URLSession = .shared) -> DataProviderRegistry {
        DataProviderRegistry(providers: [
            JSONDataProvider(urlSession: urlSession),
            SystemDataProvider(),
        ])
    }

    /// Fetches every source; failures land in failedKeys instead of throwing (stale rendering downstream).
    func fetchAll(sources: [SourceSpec], paramValues: [String: String]) async -> FetchResult {
        var data: [String: Any] = [:]
        var failed: [String] = []
        for source in sources {
            guard let provider = providersByType[source.type] else {
                failed.append(source.key)
                continue
            }
            do {
                data[source.key] = try await provider.fetch(spec: source, paramValues: paramValues)
            } catch {
                failed.append(source.key)
            }
        }
        return FetchResult(data: data, failedKeys: failed)
    }
}
