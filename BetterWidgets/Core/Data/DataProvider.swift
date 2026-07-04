import Foundation

enum DataProviderError: Error {
    case unknownType(String)
    case missingConfig(String)
    case badURL(String)
    case httpError(Int)
    /// A provider that only supports one in-flight request rejected a concurrent call
    /// rather than silently orphaning the earlier one.
    case requestInFlight(String)
}

protocol DataProvider {
    static var type: String { get }
    var minimumInterval: TimeInterval { get }
    /// Returns a JSON-serializable value exposed to the template at BW.data[spec.key].
    func fetch(spec: SourceSpec, paramValues: [String: String]) async throws -> Any
}

/// Replaces {{key}} placeholders with param values.
func substituteParams(_ template: String, params: [String: String]) -> String {
    params.reduce(template) { acc, kv in
        acc.replacingOccurrences(of: "{{\(kv.key)}}", with: kv.value)
    }
}
