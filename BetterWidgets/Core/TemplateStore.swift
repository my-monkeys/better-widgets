import Foundation

enum TemplateStoreError: Error {
    case notFound(String)
}

final class TemplateStore {
    private let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    static func applicationSupport() -> TemplateStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return TemplateStore(rootURL: base.appendingPathComponent("BetterWidgets/templates"))
    }

    func templateDirectory(id: String) -> URL {
        rootURL.appendingPathComponent(id)
    }

    func list() -> [TemplateManifest] {
        let dirs = (try? FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")) else { return nil }
            return try? TemplateManifest.validated(from: data)
        }.sorted { $0.id < $1.id }
    }

    func manifest(id: String) throws -> TemplateManifest {
        let url = templateDirectory(id: id).appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else { throw TemplateStoreError.notFound(id) }
        return try TemplateManifest.validated(from: data)
    }

    func html(id: String) throws -> String {
        let url = templateDirectory(id: id).appendingPathComponent("index.html")
        guard let html = try? String(contentsOf: url, encoding: .utf8) else {
            throw TemplateStoreError.notFound(id)
        }
        return html
    }

    /// Copies each bundled template unless a local copy already exists (never overwrites).
    func installBundledTemplates(from bundleDir: URL) throws {
        let sources = (try? FileManager.default.contentsOfDirectory(
            at: bundleDir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for src in sources {
            let dest = templateDirectory(id: src.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: dest.path) else { continue }
            try FileManager.default.copyItem(at: src, to: dest)
        }
    }
}
