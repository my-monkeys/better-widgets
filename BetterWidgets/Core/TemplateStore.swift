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

    // MARK: - User template writes

    private var userMarkerName: String { ".user" }

    /// A template is user-owned (editable/forkable/deletable) when its directory carries the `.user` marker.
    /// Bundled templates never have this marker and are read-only.
    func isUserTemplate(id: String) -> Bool {
        FileManager.default.fileExists(atPath:
            templateDirectory(id: id).appendingPathComponent(userMarkerName).path)
    }

    private func existingIds() -> Set<String> {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)) ?? []
        return Set(dirs.map { $0.lastPathComponent })
    }

    private func slug(for name: String) -> String {
        name.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { acc, ch in
                if ch == "-" && acc.last == "-" { return }
                acc.append(ch)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func uniqueID(base: String) -> String {
        let base = slug(for: base)
        let root = base.isEmpty ? "widget" : base
        let taken = existingIds()
        if !taken.contains(root) { return root }
        var n = 2
        while taken.contains("\(root)-\(n)") { n += 1 }
        return "\(root)-\(n)"
    }

    /// Scaffolds a new user template (valid default manifest + minimal HTML + `.user` marker) and returns its id.
    @discardableResult
    func createUserTemplate(name: String) -> String {
        let id = uniqueID(base: name)
        let dir = templateDirectory(id: id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifest = """
        {
          "id": "\(id)", "name": "\(name)", "version": "1.0.0",
          "sizes": ["small"], "refresh": 900, "params": [], "sources": []
        }
        """
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><style>
          html,body{margin:0;width:100%;height:100%;display:flex;align-items:center;justify-content:center;
            font-family:-apple-system,sans-serif;background:#f5f2ec;color:#1a1a1a}
          @media (prefers-color-scheme:dark){body{background:#16130e;color:#f0ece4}}
        </style></head><body><div>Hello</div></body></html>
        """
        try? manifest.write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try? html.write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try? Data().write(to: dir.appendingPathComponent(userMarkerName))
        return id
    }

    /// Copies a template's `index.html` + `manifest.json` (id rewritten, name suffixed) as a new user template.
    @discardableResult
    func forkTemplate(from sourceId: String) throws -> String {
        let srcDir = templateDirectory(id: sourceId)
        guard let manifestData = try? Data(contentsOf: srcDir.appendingPathComponent("manifest.json")),
              var obj = (try? JSONSerialization.jsonObject(with: manifestData)) as? [String: Any] else {
            throw TemplateStoreError.notFound(sourceId)
        }
        let id = uniqueID(base: "\(sourceId)-copie")
        let dir = templateDirectory(id: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        obj["id"] = id
        if let name = obj["name"] as? String { obj["name"] = "\(name) (copie)" }
        let newManifest = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])
        try newManifest.write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)
        let html = (try? String(contentsOf: srcDir.appendingPathComponent("index.html"), encoding: .utf8)) ?? "<html></html>"
        try html.write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try Data().write(to: dir.appendingPathComponent(userMarkerName))
        return id
    }

    /// Validates `manifestJSON` first; writes nothing if invalid.
    func saveTemplate(id: String, html: String, manifestJSON: String) throws {
        _ = try TemplateManifest.validated(from: Data(manifestJSON.utf8))
        let dir = templateDirectory(id: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try manifestJSON.write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try html.write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }

    /// No-op on a bundled (non-`.user`) template.
    func deleteUserTemplate(id: String) {
        guard isUserTemplate(id: id) else { return }
        try? FileManager.default.removeItem(at: templateDirectory(id: id))
    }
}
