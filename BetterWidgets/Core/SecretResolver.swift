import Foundation

/// What RenderPipeline needs from secret handling: turn a source's `secret.<H>`
/// config entries into resolved `header.<H>` entries (reading stored secret values).
protocol SecretResolving {
    func resolvedConfig(for source: SourceSpec, instanceId: UUID) -> [String: String]?
}

/// Stores per-instance API secrets and resolves them into request headers at fetch time.
/// Keeps secrets out of instances.json — they live only in the backing store (Keychain in prod).
struct SecretResolver: SecretResolving {
    private let backing: SecretBackingStore

    init(backing: SecretBackingStore) { self.backing = backing }

    private func key(_ instanceId: UUID, _ sourceKey: String, _ header: String) -> String {
        "\(instanceId.uuidString).\(sourceKey).\(header)"
    }

    func set(_ value: String, instanceId: UUID, sourceKey: String, header: String) {
        backing.setSecret(value, forKey: key(instanceId, sourceKey, header))
    }

    func get(instanceId: UUID, sourceKey: String, header: String) -> String? {
        backing.secret(forKey: key(instanceId, sourceKey, header))
    }

    func delete(instanceId: UUID, sourceKey: String, header: String) {
        backing.deleteSecret(forKey: key(instanceId, sourceKey, header))
    }

    /// Purge every declared secret of an instance (called when the instance is deleted).
    func deleteAll(instanceId: UUID, sources: [SourceSpec]) {
        for source in sources where source.type == "json" {
            for (k, _) in source.config ?? [:] where k.hasPrefix("secret.") {
                delete(instanceId: instanceId, sourceKey: source.key,
                       header: String(k.dropFirst("secret.".count)))
            }
        }
    }

    func resolvedConfig(for source: SourceSpec, instanceId: UUID) -> [String: String]? {
        guard source.type == "json", let config = source.config else { return source.config }
        var result = config
        for (k, _) in config where k.hasPrefix("secret.") {
            result.removeValue(forKey: k)
            let header = String(k.dropFirst("secret.".count))
            if let value = get(instanceId: instanceId, sourceKey: source.key, header: header) {
                result["header.\(header)"] = value
            }
        }
        return result
    }
}

/// Null object: no secret resolution (default for RenderPipeline and pre-3b-1 tests).
struct NoopSecretResolver: SecretResolving {
    func resolvedConfig(for source: SourceSpec, instanceId: UUID) -> [String: String]? { source.config }
}
