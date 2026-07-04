import Foundation

enum BWidgetArchiveError: Error, Equatable {
    case malformed
}

/// A `.bwidget` is a self-describing JSON container packing a template's files
/// (manifest.json + index.html + assets/**). Chosen over a real zip because a
/// sandboxed macOS app can't extract standard zips without a blocked Process or
/// a banned SPM dependency — and a JSON container can't carry symlink entries,
/// which is strictly safer for untrusted import.
enum BWidgetArchive {
    private struct Envelope: Codable {
        let format: String
        let entries: [Entry]
    }
    private struct Entry: Codable {
        let path: String
        let data: Data   // JSONEncoder/Decoder use base64 for Data by default
    }
    private static let format = "bwidget/1"

    static func export(templateDir: URL) throws -> Data {
        var entries: [Entry] = []
        for name in ["manifest.json", "index.html"] {
            let url = templateDir.appendingPathComponent(name)
            if let data = try? Data(contentsOf: url) { entries.append(Entry(path: name, data: data)) }
        }
        // Resolve symlinks before diffing path components: enumerator(at:) can return
        // canonicalized paths (e.g. /private/var/... on macOS) that differ from an
        // unresolved base URL (e.g. NSTemporaryDirectory's /var/... symlink), which would
        // otherwise silently break the relative-path computation below.
        let assetsDir = templateDir.appendingPathComponent("assets").resolvingSymlinksInPath()
        if let files = FileManager.default.enumerator(at: assetsDir, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let fileURL as URL in files where (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                let relComponents = fileURL.resolvingSymlinksInPath().pathComponents.dropFirst(assetsDir.pathComponents.count)
                let rel = "assets/" + relComponents.joined(separator: "/")
                if let data = try? Data(contentsOf: fileURL) { entries.append(Entry(path: rel, data: data)) }
            }
        }
        return try JSONEncoder().encode(Envelope(format: format, entries: entries))
    }

    static func entries(in data: Data) throws -> [(path: String, data: Data)] {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.format == format else {
            throw BWidgetArchiveError.malformed
        }
        return envelope.entries.map { ($0.path, $0.data) }
    }
}
