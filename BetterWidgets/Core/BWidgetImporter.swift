import Foundation

enum ImportError: Error, Equatable {
    case badArchive
    case unsafeEntry(String)
    case missingFile(String)
    case invalidManifest
}

/// Installs a `.bwidget` as a user template after validating every entry.
/// The confinement mirrors resolveTemplateAsset (symlink-safe): a decoded entry
/// can never write outside its own template directory.
enum BWidgetImporter {
    private static let whitelistFixed: Set<String> = ["manifest.json", "index.html"]

    static func isSafeEntryPath(_ path: String) -> Bool {
        if path.hasPrefix("/") { return false }
        if path.split(separator: "/").contains("..") { return false }
        if whitelistFixed.contains(path) { return true }
        return path.hasPrefix("assets/") && path.count > "assets/".count
    }

    static func install(archive data: Data, into store: TemplateStore) throws -> String {
        let entries: [(path: String, data: Data)]
        do { entries = try BWidgetArchive.entries(in: data) }
        catch { throw ImportError.badArchive }

        for entry in entries where !isSafeEntryPath(entry.path) {
            throw ImportError.unsafeEntry(entry.path)
        }
        let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.data) })
        guard let manifestData = byPath["manifest.json"] else { throw ImportError.missingFile("manifest.json") }
        guard byPath["index.html"] != nil else { throw ImportError.missingFile("index.html") }

        let manifest: TemplateManifest
        do { manifest = try TemplateManifest.validated(from: manifestData) }
        catch { throw ImportError.invalidManifest }

        // Fresh user id derived from the manifest name; rewrite manifest.id to it.
        let id = store.freshUserID(base: manifest.name)
        let dir = store.templateDirectory(id: id)
        let root = dir.resolvingSymlinksInPath().standardizedFileURL
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for entry in entries {
            let dest = dir.appendingPathComponent(entry.path).standardizedFileURL.resolvingSymlinksInPath()
            guard dest.path == root.path || dest.path.hasPrefix(root.path + "/") else {
                try? FileManager.default.removeItem(at: dir)
                throw ImportError.unsafeEntry(entry.path)
            }
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let payload = entry.path == "manifest.json"
                ? try rewriteManifestID(manifestData, to: id)
                : entry.data
            try payload.write(to: dest, options: .atomic)
        }
        try Data().write(to: dir.appendingPathComponent(".user"))
        return id
    }

    private static func rewriteManifestID(_ data: Data, to id: String) throws -> Data {
        guard var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return data }
        obj["id"] = id
        return try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])
    }
}
