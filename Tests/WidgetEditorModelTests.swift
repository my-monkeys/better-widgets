import XCTest

@MainActor
final class WidgetEditorModelTests: XCTestCase {
    private final class MemSecretStore: SecretBackingStore {
        private var s: [String: String] = [:]
        func setSecret(_ value: String, forKey key: String) { s[key] = value }
        func secret(forKey key: String) -> String? { s[key] }
        func deleteSecret(forKey key: String) { s[key] = nil }
    }

    private func manifest(params: String = "", sources: String = "") -> TemplateManifest {
        let json = """
        { "id": "t", "name": "T", "version": "1.0.0", "sizes": ["small","medium"], "refresh": 60,
          "params": [\(params)], "sources": [\(sources)] }
        """
        return try! TemplateManifest.validated(from: Data(json.utf8))
    }

    func testMergedParamsAppliesDefaultsThenWorkingCopy() {
        let m = manifest(params: ##"{"key":"accent","type":"color","label":"A","default":"#fff"}"##)
        let inst = WidgetInstance(id: UUID(), name: "x", templateId: "t", size: .small, paramValues: [:])
        let model = WidgetEditorModel(instance: inst, manifest: m, secrets: SecretResolver(backing: MemSecretStore()))
        XCTAssertEqual(model.mergedParams()["accent"], "#fff")     // default
        model.paramValues["accent"] = "#000"
        XCTAssertEqual(model.mergedParams()["accent"], "#000")     // working copy wins
    }

    func testPreviewContextUsesPreviewSizeAndTheme() {
        let model = WidgetEditorModel(instance: WidgetInstance(id: UUID(), name: "x", templateId: "t",
                                      size: .small, paramValues: [:]),
                                      manifest: manifest(), secrets: SecretResolver(backing: MemSecretStore()))
        model.previewSize = .medium; model.previewTheme = .dark
        let ctx = model.previewContext(data: [:], stale: false)
        XCTAssertEqual(ctx.size, .medium)
        XCTAssertEqual(ctx.theme, .dark)
    }

    func testUpdatedInstanceCarriesWorkingParams() {
        let inst = WidgetInstance(id: UUID(), name: "x", templateId: "t", size: .small, paramValues: [:])
        let model = WidgetEditorModel(instance: inst, manifest: manifest(), secrets: SecretResolver(backing: MemSecretStore()))
        model.paramValues["accent"] = "#123456"
        let updated = model.updatedInstance()
        XCTAssertEqual(updated.id, inst.id)
        XCTAssertEqual(updated.paramValues["accent"], "#123456")
    }

    func testSecretRequirementsFromJSONSources() {
        let m = manifest(sources: #"{"key":"api","type":"json","config":{"url":"https://x","secret.Authorization":""}}"#)
        let model = WidgetEditorModel(instance: WidgetInstance(id: UUID(), name: "x", templateId: "t",
                                      size: .small, paramValues: [:]),
                                      manifest: m, secrets: SecretResolver(backing: MemSecretStore()))
        XCTAssertEqual(model.secretRequirements.count, 1)
        XCTAssertEqual(model.secretRequirements.first?.header, "Authorization")
        XCTAssertEqual(model.secretRequirements.first?.sourceKey, "api")
    }

    func testPersistSecretsWritesNonEmpty() {
        let mem = MemSecretStore(); let resolver = SecretResolver(backing: mem)
        let m = manifest(sources: #"{"key":"api","type":"json","config":{"secret.Authorization":""}}"#)
        let id = UUID()
        let model = WidgetEditorModel(instance: WidgetInstance(id: id, name: "x", templateId: "t",
                                      size: .small, paramValues: [:]), manifest: m, secrets: resolver)
        model.secretValues["api.Authorization"] = "Bearer Z"
        model.persistSecrets(instanceId: id)
        XCTAssertEqual(resolver.get(instanceId: id, sourceKey: "api", header: "Authorization"), "Bearer Z")
    }
}
