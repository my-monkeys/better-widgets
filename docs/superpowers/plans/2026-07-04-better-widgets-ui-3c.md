# Better Widgets — Plan 3c : Import/export `.bwidget` + consentement + météo localisation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permettre d'exporter/importer des templates via un format `.bwidget` (avec import sûr et écran de consentement des permissions), et fetcher la météo par localisation courante — le dernier morceau de la phase UI.

**Architecture:** `.bwidget` est un **conteneur JSON auto-décrit** (`BWidgetArchive`) qui empaquette les fichiers d'un template. L'import (`BWidgetImporter`) valide chaque entrée (whitelist + confinement réutilisant la logique symlink-safe de `resolveTemplateAsset`) puis installe un template **utilisateur** ; les sources consent-required ouvrent un écran de consentement (`PermissionConsentView`) écrivant dans le `PermissionStore`. La météo gagne `config.useCurrentLocation` via un `LocationProvider` mockable.

**Tech Stack:** Swift 5.9, SwiftUI, Foundation (JSON container — PAS de zip/SPM), CoreLocation (`CLLocationManager`), AppKit (`NSOpenPanel`/`NSSavePanel`), XCTest, XcodeGen. macOS 14+, Xcode 27.

## Global Constraints

- **Format `.bwidget` = conteneur JSON auto-décrit, PAS un vrai zip.** Décision technique actée (le spec laissait le mécanisme ouvert, contrat = round-trip + énumération) : une app **sandboxée** ne peut extraire un zip standard ni via `Process`/`ditto` (bloqué par le sandbox) ni via une lib SPM (interdite par le CLAUDE.md « pas de dépendance SPM »). Le conteneur JSON est pur Foundation, sandbox-safe, et **plus sûr** (aucune entrée symlink possible par construction ; seul un `path` malveillant `..`/absolu est un risque, couvert par le confinement). Un `.bwidget` est un fichier interchange privé entre installs Better Widgets, pas un artefact Finder-ouvrable.
- **Import = surface d'attaque principale.** Chaque entrée est validée : whitelist (`manifest.json`, `index.html`, `assets/**`), rejet des chemins absolus / `..` / hors-whitelist ; le manifest passe `TemplateManifest.validated` ; `index.html` requis. Confinement réutilise la logique de `resolveTemplateAsset` (Plan 2, symlink-safe). Tout échec → refus, **rien installé**.
- **Pas de secret exporté** : `BWidgetArchive.export` ne lit que `manifest.json`/`index.html`/`assets` ; les secrets vivent sur l'instance (Keychain), jamais dans un template.
- **Consentement par instance** (cohérent avec `PermissionStore` keyé par `instanceId`) ; l'écran de l'app gère le grant app (« droit de demander »), le **prompt TCC macOS reste l'autorité** (EventKit/localisation), déclenché au 1er accès réel.
- **`weather` reste consent-required** ; `useCurrentLocation` n'est utilisé que si l'instance a accordé `weather`. WeatherKit non provisionné → build+tests OK (fake) mais pas de vraie donnée tant que le portail n'est pas fait (action Maxim).
- **Le `.xcodeproj` est généré** : fichiers `Core/**`/`App/**` auto-inclus dans l'app ; fichiers de **logique testés** ajoutés **individuellement** aux sources `BetterWidgetsTests` de `project.yml` (jamais le dossier `App/`). `xcodegen generate` après tout changement.
- **Commande de test** : `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`. Départ : **106 tests verts**.
- Commits : Conventional Commits, auteur `MaximCosta <maxim@users.noreply.github.com>`, **aucune mention d'IA**. Code/commentaires anglais ; UI/usage strings français.
- Flake connu `RenderEngineTests.testMediumSizeDimensions` (relancer isolé si besoin).

## Périmètre

**Dans 3c** : `BWidgetArchive` (export/entries), `BWidgetImporter` (valider+installer), `LocationProvider`+`WeatherDataProvider.useCurrentLocation`, `PermissionConsentModel`+`PermissionConsentView`, Galerie Import/Export + « Permissions… » sur les cartes. **Hors 3c** : galerie communautaire en ligne ; signature/notarization des `.bwidget` ; distribution (Plan 4) ; nettoyage des instances orphelines ; lecture de l'état TCC sans prompt.

---

## Structure des fichiers

```
BetterWidgets/
├── Core/
│   ├── BWidgetArchive.swift     # NOUVEAU : conteneur JSON export/entries
│   ├── BWidgetImporter.swift    # NOUVEAU : valider (sandbox) → installer user template
│   ├── LocationProvider.swift   # NOUVEAU : protocol + CoreLocationProvider
│   └── Data/WeatherDataProvider.swift  # MODIF : useCurrentLocation + LocationProvider
├── App/
│   ├── PermissionConsentModel.swift  # NOUVEAU : grants d'une instance
│   ├── PermissionConsentView.swift   # NOUVEAU : feuille de consentement
│   ├── GalleryView.swift        # MODIF : Importer/Exporter
│   ├── WidgetCard.swift         # MODIF : « Permissions… » si consent-required
│   └── MyWidgetsView.swift      # MODIF : présenter PermissionConsentView
├── BetterWidgets.entitlements   # MODIF : user-selected files RW + location
├── project.yml                  # MODIF : Info.plist location usage string + tests
└── Tests/
    ├── BWidgetArchiveTests.swift        # NOUVEAU
    ├── BWidgetImporterTests.swift       # NOUVEAU
    ├── WeatherDataProviderTests.swift   # MODIF : useCurrentLocation + call sites
    └── PermissionConsentModelTests.swift# NOUVEAU
```

---

### Task 1: `BWidgetArchive` — conteneur JSON export/entries

**Files:**
- Create: `BetterWidgets/Core/BWidgetArchive.swift`
- Test: `Tests/BWidgetArchiveTests.swift`

**Interfaces:**
- Produces:
  - `enum BWidgetArchive` :
    - `static func export(templateDir: URL) throws -> Data` — lit `manifest.json` + `index.html` + tout fichier sous `assets/` de `templateDir`, empaquette en `[(path, data)]` (chemins relatifs au template), encode l'enveloppe JSON, retourne les octets.
    - `static func entries(in data: Data) throws -> [(path: String, data: Data)]` — décode l'enveloppe, retourne les entrées ; throw `BWidgetArchiveError.malformed` si non décodable ou mauvais format.
  - `enum BWidgetArchiveError: Error, Equatable { case malformed }`
  - Enveloppe interne `Codable` : `{ "format": "bwidget/1", "entries": [{ "path": String, "data": Data }] }` (JSONEncoder encode `Data` en base64 par défaut).

- [ ] **Step 1: Écrire `Tests/BWidgetArchiveTests.swift` (échoue)**

```swift
import XCTest

final class BWidgetArchiveTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("assets"),
                                                withIntermediateDirectories: true)
        try #"{"id":"t","name":"T","version":"1.0.0","sizes":["small"],"refresh":900,"params":[],"sources":[]}"#
            .write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "<b>hi</b>".write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try "PNGDATA".write(to: dir.appendingPathComponent("assets/logo.png"), atomically: true, encoding: .utf8)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testExportEntriesRoundTrip() throws {
        let data = try BWidgetArchive.export(templateDir: dir)
        let entries = try BWidgetArchive.entries(in: data)
        let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.data) })
        XCTAssertEqual(String(data: byPath["index.html"] ?? Data(), encoding: .utf8), "<b>hi</b>")
        XCTAssertEqual(String(data: byPath["assets/logo.png"] ?? Data(), encoding: .utf8), "PNGDATA")
        XCTAssertTrue(byPath["manifest.json"].map { String(data: $0, encoding: .utf8)!.contains("\"id\"") } ?? false)
    }

    func testEntriesRejectsGarbage() {
        XCTAssertThrowsError(try BWidgetArchive.entries(in: Data("not json".utf8))) {
            XCTAssertEqual($0 as? BWidgetArchiveError, .malformed)
        }
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -only-testing:BetterWidgetsTests/BWidgetArchiveTests -quiet`
Expected: FAIL — `cannot find 'BWidgetArchive' in scope`.

- [ ] **Step 3: Implémenter `BWidgetArchive.swift`**

```swift
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
        let assetsDir = templateDir.appendingPathComponent("assets")
        if let files = FileManager.default.enumerator(at: assetsDir, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let fileURL as URL in files where (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                let rel = "assets/" + fileURL.path.replacingOccurrences(of: assetsDir.path + "/", with: "")
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
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/BWidgetArchiveTests -quiet`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: BWidgetArchive — JSON container for template export/import"
```

---

### Task 2: `BWidgetImporter` — validation sandbox + installation

**Files:**
- Create: `BetterWidgets/Core/BWidgetImporter.swift`
- Test: `Tests/BWidgetImporterTests.swift`

**Interfaces:**
- Consumes: `BWidgetArchive.entries` (Task 1), `TemplateManifest.validated`/`ManifestError`, `TemplateStore` (`templateDirectory`, `list`), la logique de confinement de `resolveTemplateAsset` (Plan 2).
- Produces:
  - `enum BWidgetImporter` :
    - `static func install(archive data: Data, into store: TemplateStore) throws -> String` — décode ; valide ; installe un template utilisateur (marqueur `.user`, id unique, manifest réécrit avec le nouvel id) ; retourne l'id. Rien écrit si une validation échoue.
  - `enum ImportError: Error, Equatable { case badArchive, unsafeEntry(String), missingFile(String), invalidManifest }`
  - `static func isSafeEntryPath(_ path: String) -> Bool` (interne, testable via install) — rejette chemin absolu, composant `..`, ou hors whitelist (`manifest.json`, `index.html`, `assets/…`).

Validation (ordre) : (1) décoder → `badArchive` si `BWidgetArchiveError` ; (2) chaque `path` : `isSafeEntryPath` sinon `unsafeEntry(path)` ; (3) `manifest.json` présent sinon `missingFile("manifest.json")`, `index.html` présent sinon `missingFile("index.html")` ; (4) `TemplateManifest.validated(manifest)` sinon `invalidManifest`. Puis installer : id = `uniqueID(base: manifest.name)` via une petite dérivation (réutiliser la logique de slug du `TemplateStore` — exposer `TemplateStore.freshUserID(base:) -> String` si besoin, sinon dériver dans l'importer) ; créer le dossier ; réécrire `manifest["id"] = id` ; écrire chaque entrée sous le dossier en **re-vérifiant le confinement** (le chemin d'écriture résolu reste dans le dossier, via la même logique que `resolveTemplateAsset`) ; poser le marqueur `.user`.

- [ ] **Step 1: Écrire `Tests/BWidgetImporterTests.swift` (échoue)**

```swift
import XCTest

final class BWidgetImporterTests: XCTestCase {
    private var root: URL!
    private var store: TemplateStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = TemplateStore(rootURL: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    // Build a .bwidget JSON container by hand for arbitrary (possibly malicious) entries.
    private func archive(_ entries: [(String, String)]) -> Data {
        let items = entries.map { ["path": $0.0, "data": Data($0.1.utf8).base64EncodedString()] }
        return try! JSONSerialization.data(withJSONObject: ["format": "bwidget/1", "entries": items])
    }
    private let validManifest = #"{"id":"orig","name":"Imported","version":"1.0.0","sizes":["small"],"refresh":900,"params":[],"sources":[]}"#

    func testInstallsValidArchiveAsUserTemplate() throws {
        let data = archive([("manifest.json", validManifest), ("index.html", "<b>ok</b>"), ("assets/x.css", "a{}")])
        let id = try BWidgetImporter.install(archive: data, into: store)
        XCTAssertTrue(store.isUserTemplate(id: id))
        XCTAssertEqual(try store.manifest(id: id).id, id)        // id rewritten, not "orig"
        XCTAssertEqual(try store.html(id: id), "<b>ok</b>")
        XCTAssertEqual(try store.manifest(id: id).name, "Imported")
    }

    func testRejectsAbsolutePath() {
        let data = archive([("manifest.json", validManifest), ("index.html", "<b>x</b>"), ("/etc/evil", "x")])
        XCTAssertThrowsError(try BWidgetImporter.install(archive: data, into: store)) {
            guard case ImportError.unsafeEntry = $0 else { return XCTFail("expected unsafeEntry") }
        }
        XCTAssertTrue(store.list().isEmpty)                       // nothing installed
    }

    func testRejectsDotDotPath() {
        let data = archive([("manifest.json", validManifest), ("index.html", "<b>x</b>"), ("assets/../../evil", "x")])
        XCTAssertThrowsError(try BWidgetImporter.install(archive: data, into: store)) {
            guard case ImportError.unsafeEntry = $0 else { return XCTFail("expected unsafeEntry") }
        }
        XCTAssertTrue(store.list().isEmpty)
    }

    func testRejectsNonWhitelistedEntry() {
        let data = archive([("manifest.json", validManifest), ("index.html", "<b>x</b>"), ("evil.sh", "rm -rf")])
        XCTAssertThrowsError(try BWidgetImporter.install(archive: data, into: store)) {
            guard case ImportError.unsafeEntry = $0 else { return XCTFail("expected unsafeEntry") }
        }
    }

    func testRejectsInvalidManifest() {
        let bad = #"{"id":"x","name":"X","version":"1","sizes":[],"refresh":900,"params":[],"sources":[]}"#  // emptySizes
        let data = archive([("manifest.json", bad), ("index.html", "<b>x</b>")])
        XCTAssertThrowsError(try BWidgetImporter.install(archive: data, into: store)) {
            XCTAssertEqual($0 as? ImportError, .invalidManifest)
        }
        XCTAssertTrue(store.list().isEmpty)
    }

    func testRejectsMissingIndex() {
        let data = archive([("manifest.json", validManifest)])
        XCTAssertThrowsError(try BWidgetImporter.install(archive: data, into: store)) {
            XCTAssertEqual($0 as? ImportError, .missingFile("index.html"))
        }
    }

    func testRejectsGarbageArchive() {
        XCTAssertThrowsError(try BWidgetImporter.install(archive: Data("not json".utf8), into: store)) {
            XCTAssertEqual($0 as? ImportError, .badArchive)
        }
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/BWidgetImporterTests -quiet`
Expected: FAIL — `cannot find 'BWidgetImporter' in scope`.

- [ ] **Step 3: Implémenter `BWidgetImporter.swift`**

```swift
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
```

Note : ce code appelle `store.freshUserID(base:)` — l'exposer à partir de la logique `uniqueID` privée existante de `TemplateStore` (Task 2 de 3b-2). Step 4 l'ajoute.

- [ ] **Step 4: Exposer `TemplateStore.freshUserID(base:)`**

Dans `BetterWidgets/Core/TemplateStore.swift`, renommer/exposer la dérivation d'id : ajouter une méthode publique qui délègue à la logique `uniqueID(base:)` privée existante :
```swift
    /// Public entry to the unique-id derivation (used by the .bwidget importer).
    func freshUserID(base: String) -> String { uniqueID(base: base) }
```
(Si `uniqueID` s'appelle autrement dans le fichier — vérifier — adapter le corps ; le contrat = slug unique non déjà pris.)

- [ ] **Step 5: Vérifier — suite complète**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: PASS (BWidgetImporterTests + suite).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: BWidgetImporter — sandboxed .bwidget import with entry confinement"
```

---

### Task 3: `LocationProvider` + `WeatherDataProvider.useCurrentLocation`

**Files:**
- Create: `BetterWidgets/Core/LocationProvider.swift`
- Modify: `BetterWidgets/Core/Data/WeatherDataProvider.swift`
- Modify: `Tests/WeatherDataProviderTests.swift` (call sites + nouveaux tests)
- Modify: `project.yml` (Info.plist location usage string) + `BetterWidgets.entitlements` (location)

**Interfaces:**
- Consumes: `DataProviderError`, `substituteParams`, `SourceSpec`.
- Produces:
  - `protocol LocationProvider { func currentCoordinates() async throws -> (lat: Double, lon: Double) }`
  - `struct CoreLocationProvider: LocationProvider` — vraie implémentation `CLLocationManager` (non testée unitairement, comme `WeatherKitService`).
  - `WeatherDataProvider.init` gagne `location: LocationProvider = CoreLocationProvider()` (dernier paramètre, défaut). Résolution dans `fetch` : `useCurrentLocation == "true"` → `location.currentCoordinates()` ; sinon lat/lon ; sinon city ; sinon throw.

- [ ] **Step 1: Modifier `Tests/WeatherDataProviderTests.swift`** — d'abord convertir les 4 call sites en label `geocoder:` (pour que l'ajout d'un `location:` défaut ne casse pas la syntaxe trailing-closure), puis ajouter les tests de localisation.

Remplacer chaque `WeatherDataProvider(fetcher: FakeWeather(dto: sample)) { <closure> }` par `WeatherDataProvider(fetcher: FakeWeather(dto: sample), geocoder: { <closure> })`. Ajouter en haut de la classe un fake location + les tests :

```swift
    private struct FakeLocation: LocationProvider {
        var coords: (lat: Double, lon: Double) = (48.85, 2.35)
        var thrown: Error?
        func currentCoordinates() async throws -> (lat: Double, lon: Double) {
            if let thrown { throw thrown }
            return coords
        }
    }

    func testUsesCurrentLocationWhenConfigured() async throws {
        let loc = FakeLocation(coords: (10, 20))
        var calledGeocoder = false
        let p = WeatherDataProvider(fetcher: FakeWeather(dto: sample),
                                    geocoder: { _ in calledGeocoder = true; return (0, 0) },
                                    location: loc)
        let result = try await p.fetch(
            spec: SourceSpec(key: "w", type: "weather", config: ["useCurrentLocation": "true", "city": "Paris"]),
            paramValues: [:])
        XCTAssertNotNil(result as? [String: Any])       // succeeded via current location
        XCTAssertFalse(calledGeocoder)                  // city/geocoder ignored when useCurrentLocation
    }

    func testCurrentLocationFailurePropagates() async {
        let loc = FakeLocation(thrown: DataProviderError.badURL("no location"))
        let p = WeatherDataProvider(fetcher: FakeWeather(dto: sample),
                                    geocoder: { _ in (0, 0) }, location: loc)
        do {
            _ = try await p.fetch(spec: SourceSpec(key: "w", type: "weather", config: ["useCurrentLocation": "true"]),
                                  paramValues: [:])
            XCTFail("expected throw")
        } catch { /* expected */ }
    }
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/WeatherDataProviderTests -quiet`
Expected: FAIL — `cannot find type 'LocationProvider'` / `WeatherDataProvider` n'a pas de param `location`.

- [ ] **Step 3: Implémenter `LocationProvider.swift`**

```swift
import Foundation
import CoreLocation

protocol LocationProvider {
    func currentCoordinates() async throws -> (lat: Double, lon: Double)
}

/// Real CoreLocation-backed provider. Requests one location fix; the system TCC
/// prompt is the authority. Not exercised by unit tests.
final class CoreLocationProvider: NSObject, LocationProvider, CLLocationManagerDelegate {
    private var continuation: CheckedContinuation<(lat: Double, lon: Double), Error>?
    private let manager = CLLocationManager()

    func currentCoordinates() async throws -> (lat: Double, lon: Double) {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            manager.delegate = self
            manager.requestWhenInUseAuthorization()
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        continuation?.resume(returning: (loc.coordinate.latitude, loc.coordinate.longitude))
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
```

- [ ] **Step 4: Modifier `WeatherDataProvider.swift`** — ajouter `location` + la branche

Modifier l'init et `fetch` :
```swift
    let location: LocationProvider

    init(fetcher: WeatherFetching,
         geocoder: @escaping (String) async throws -> (lat: Double, lon: Double),
         location: LocationProvider = CoreLocationProvider()) {
        self.fetcher = fetcher
        self.geocoder = geocoder
        self.location = location
    }

    func fetch(spec: SourceSpec, paramValues: [String: String]) async throws -> Any {
        let coords: (lat: Double, lon: Double)
        if spec.config?["useCurrentLocation"] == "true" {
            coords = try await location.currentCoordinates()
        } else if let latStr = spec.config?["lat"], let lonStr = spec.config?["lon"],
                  let lat = Double(substituteParams(latStr, params: paramValues)),
                  let lon = Double(substituteParams(lonStr, params: paramValues)) {
            coords = (lat, lon)
        } else if let city = spec.config?["city"] {
            coords = try await geocoder(substituteParams(city, params: paramValues))
        } else {
            throw DataProviderError.missingConfig("weather source '\(spec.key)' requires lat+lon, city, or useCurrentLocation")
        }
        let weather = try await fetcher.currentWeather(latitude: coords.lat, longitude: coords.lon)
        return [
            "temperature": weather.temperature,
            "condition": weather.conditionCode,
            "symbol": weather.symbolName,
            "humidity": weather.humidity,
        ]
    }
```
(La construction du registry `WeatherDataProvider(fetcher: WeatherKitService(), geocoder: geocodeCity)` reste valide grâce au défaut `location`.)

- [ ] **Step 5: Ajouter l'usage string + l'entitlement localisation**

Dans `project.yml`, sous le target `BetterWidgets` → `info` → `properties`, ajouter :
```yaml
        NSLocationWhenInUseUsageDescription: "Better Widgets utilise votre position pour afficher la météo locale dans un widget."
```
Dans `BetterWidgets/BetterWidgets.entitlements`, ajouter la clé sandbox localisation :
```xml
	<key>com.apple.security.personal-information.location</key>
	<true/>
```

- [ ] **Step 6: Vérifier — suite complète (build inclut CoreLocation)**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: PASS (WeatherDataProviderTests étendus + suite). `CoreLocationProvider` compile ; aucun test ne l'exerce (fake injecté).

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: weather by current location via a mockable LocationProvider"
```

---

### Task 4: `PermissionConsentModel`

**Files:**
- Create: `BetterWidgets/App/PermissionConsentModel.swift`
- Modify: `project.yml` (ajouter `BetterWidgets/App/PermissionConsentModel.swift` aux sources `BetterWidgetsTests`)
- Test: `Tests/PermissionConsentModelTests.swift`

**Interfaces:**
- Consumes: `PermissionStore` (`grantedTypes`, `setGrantedTypes`), `TemplateManifest` (`sources`, `SourceSpec.requiresConsent`/`.type`), `WidgetInstance`.
- Produces: `@MainActor final class PermissionConsentModel: ObservableObject`
  - `init(instanceId: UUID, manifest: TemplateManifest, permissions: PermissionStore)`
  - `let requiredTypes: [String]` — types consent-required distincts du manifest (`sources.filter(\.requiresConsent).map(\.type)`, dédupliqués, triés).
  - `@Published var granted: Set<String>` — seedé depuis `permissions.grantedTypes(instanceId:)`.
  - `func isGranted(_ type: String) -> Bool` ; `func setGranted(_ type: String, _ on: Bool)` — met à jour `granted` + `permissions.setGrantedTypes(granted, instanceId:)`.
  - `static func label(for type: String) -> String` — « Calendrier » / « Météo » / fallback le type.

- [ ] **Step 1: Ajouter le fichier aux sources de test dans `project.yml`** (`- path: BetterWidgets/App/PermissionConsentModel.swift`, `optional: true`, sous `BetterWidgetsTests.sources`).

- [ ] **Step 2: Écrire `Tests/PermissionConsentModelTests.swift` (échoue)**

```swift
import XCTest

@MainActor
final class PermissionConsentModelTests: XCTestCase {
    private var tmp: URL!
    private var permissions: PermissionStore!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        permissions = try PermissionStore(baseURL: tmp)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func manifest(_ sources: String) -> TemplateManifest {
        try! TemplateManifest.validated(from: Data(#"""
        {"id":"t","name":"T","version":"1.0.0","sizes":["small"],"refresh":900,"params":[],"sources":[\#(sources)]}
        """#.utf8))
    }

    func testListsConsentRequiredTypesOnly() {
        let m = manifest(#"{"key":"cal","type":"calendar"},{"key":"w","type":"weather"},{"key":"s","type":"system"}"#)
        let model = PermissionConsentModel(instanceId: UUID(), manifest: m, permissions: permissions)
        XCTAssertEqual(model.requiredTypes, ["calendar", "weather"])   // system excluded, sorted
    }

    func testToggleWritesToStoreAndIsolatesByInstance() {
        let m = manifest(#"{"key":"cal","type":"calendar"}"#)
        let id = UUID()
        let model = PermissionConsentModel(instanceId: id, manifest: m, permissions: permissions)
        XCTAssertFalse(model.isGranted("calendar"))
        model.setGranted("calendar", true)
        XCTAssertTrue(model.isGranted("calendar"))
        XCTAssertEqual(permissions.grantedTypes(instanceId: id), ["calendar"])
        XCTAssertEqual(permissions.grantedTypes(instanceId: UUID()), [])   // isolated
        model.setGranted("calendar", false)
        XCTAssertEqual(permissions.grantedTypes(instanceId: id), [])
    }

    func testLabels() {
        XCTAssertEqual(PermissionConsentModel.label(for: "calendar"), "Calendrier")
        XCTAssertEqual(PermissionConsentModel.label(for: "weather"), "Météo")
    }
}
```

- [ ] **Step 3: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/PermissionConsentModelTests -quiet`
Expected: FAIL — `cannot find 'PermissionConsentModel' in scope`.

- [ ] **Step 4: Implémenter `PermissionConsentModel.swift`**

```swift
import Foundation
import SwiftUI

/// Drives the per-instance consent screen: which consent-requiring source types
/// a template declares, and whether the user granted them (PermissionStore).
@MainActor
final class PermissionConsentModel: ObservableObject {
    let instanceId: UUID
    let requiredTypes: [String]
    private let permissions: PermissionStore
    @Published var granted: Set<String>

    init(instanceId: UUID, manifest: TemplateManifest, permissions: PermissionStore) {
        self.instanceId = instanceId
        self.permissions = permissions
        self.requiredTypes = Array(Set(manifest.sources.filter { $0.requiresConsent }.map { $0.type })).sorted()
        self.granted = permissions.grantedTypes(instanceId: instanceId)
    }

    func isGranted(_ type: String) -> Bool { granted.contains(type) }

    func setGranted(_ type: String, _ on: Bool) {
        if on { granted.insert(type) } else { granted.remove(type) }
        try? permissions.setGrantedTypes(granted, instanceId: instanceId)
    }

    static func label(for type: String) -> String {
        switch type {
        case "calendar": return "Calendrier"
        case "weather": return "Météo"
        default: return type
        }
    }
}
```

- [ ] **Step 5: Vérifier que les tests passent**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: PermissionConsentModel — per-instance grant management"
```

---

### Task 5: `PermissionConsentView` + « Permissions… » sur les cartes

**Files:**
- Create: `BetterWidgets/App/PermissionConsentView.swift`
- Modify: `BetterWidgets/App/WidgetCard.swift` (menu « Permissions… » si le template exige un consentement)
- Modify: `BetterWidgets/App/MyWidgetsView.swift` (présenter `PermissionConsentView` en `.sheet`)

**Interfaces:**
- Consumes: `PermissionConsentModel` (Task 4), `AppState` (`templates`, `permissions`), `TemplateManifest`, `DesignTokens`, `WidgetInstance`.
- Produces:
  - `struct PermissionConsentView: View` — `init(model: PermissionConsentModel, onClose: () -> Void)` ; un `Toggle` par `model.requiredTypes` (label FR via `PermissionConsentModel.label`), une phrase d'explication, bouton Terminé.
  - `WidgetCard` : un paramètre `onPermissions: (() -> Void)?` (nil si le template n'exige aucun consentement) ; item de menu « Permissions… » affiché seulement si non-nil.
  - `MyWidgetsView` : `@State private var permissionInstance: WidgetInstance?` ; calcule si l'instance requiert un consentement (`state.templates.manifest(id:)?.sources.contains(where: \.requiresConsent)`) pour décider de passer `onPermissions` ; `.sheet(item:)` présentant `PermissionConsentView(model: PermissionConsentModel(instanceId:manifest:permissions:))`.
- Vues SwiftUI → build-gated ; la logique (model) est déjà testée (Task 4).

- [ ] **Step 1: Invoquer `minimalist-ui`** avant le SwiftUI.

- [ ] **Step 2: Implémenter `PermissionConsentView.swift`**

```swift
import SwiftUI

struct PermissionConsentView: View {
    @ObservedObject var model: PermissionConsentModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.lg) {
            Text("Permissions du widget")
                .font(.system(size: DesignTokens.FontSize.titleXL, weight: .bold))
                .foregroundStyle(DesignTokens.textPrimary)
            Text("Ce widget peut accéder à ces données. Tu peux l'autoriser ou non ; macOS te demandera aussi confirmation au premier accès.")
                .font(.system(size: DesignTokens.FontSize.label))
                .foregroundStyle(DesignTokens.textSecondary)
            ForEach(model.requiredTypes, id: \.self) { type in
                Toggle(PermissionConsentModel.label(for: type), isOn: Binding(
                    get: { model.isGranted(type) },
                    set: { model.setGranted(type, $0) }))
                .tint(DesignTokens.accent)
            }
            HStack {
                Spacer()
                Button("Terminé", action: onClose).buttonStyle(.borderedProminent).tint(DesignTokens.accent)
            }
        }
        .padding(DesignTokens.Space.xxl)
        .frame(width: 420)
        .background(DesignTokens.background)
    }
}
```

- [ ] **Step 3: Ajouter `onPermissions` à `WidgetCard.swift`**

Ajouter un paramètre `let onPermissions: (() -> Void)?` (défaut `nil` acceptable ou explicite selon le style du fichier). Dans le menu d'actions, avant « Supprimer », insérer :
```swift
            if let onPermissions {
                Button("Permissions…", action: onPermissions)
            }
```

- [ ] **Step 4: Câbler dans `MyWidgetsView.swift`**

Ajouter `@State private var permissionInstance: WidgetInstance?`. Dans la construction de chaque `WidgetCard`, passer :
```swift
                onPermissions: templateRequiresConsent(instance) ? { permissionInstance = instance } : nil
```
avec un helper :
```swift
    private func templateRequiresConsent(_ instance: WidgetInstance) -> Bool {
        (try? state.templates.manifest(id: instance.templateId))?.sources.contains { $0.requiresConsent } ?? false
    }
```
et le modifier :
```swift
        .sheet(item: $permissionInstance) { instance in
            if let manifest = try? state.templates.manifest(id: instance.templateId) {
                PermissionConsentView(
                    model: PermissionConsentModel(instanceId: instance.id, manifest: manifest,
                                                  permissions: state.permissions)) {
                    permissionInstance = nil
                }
            }
        }
```

- [ ] **Step 5: Build + suite**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet` + `xcodebuild build ... -quiet`.
Expected: suite verte (106) + `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: permission consent sheet reachable from Mes widgets"
```

---

### Task 6: Galerie Import/Export + entitlement fichiers + vérif réelle

**Files:**
- Modify: `BetterWidgets/App/GalleryView.swift` (Importer/Exporter)
- Modify: `BetterWidgets/BetterWidgets.entitlements` (user-selected files RW)

**Interfaces:**
- Consumes: `BWidgetArchive.export` (Task 1), `BWidgetImporter.install` (Task 2), `AppState` (`templates`), `TemplateStore` (`templateDirectory`, `list`), `DesignTokens`, `NSOpenPanel`/`NSSavePanel`.
- Produces sur `GalleryView` :
  - un bouton **« Importer »** (en tête) → `NSOpenPanel` filtré sur l'extension `bwidget` → `try BWidgetImporter.install(archive: Data(contentsOf: url), into: state.templates)` → la liste se rafraîchit ; erreur → alerte avec le message.
  - une action **« Exporter »** par carte de template → `NSSavePanel` (nom `<id>.bwidget`) → `try BWidgetArchive.export(templateDir: state.templates.templateDirectory(id:)).write(to: url)`.
- Vues → build-gated + vérif réelle.

- [ ] **Step 1: Invoquer `minimalist-ui`** pour les boutons/menu.

- [ ] **Step 2: Ajouter l'entitlement fichiers user-selected**

Dans `BetterWidgets/BetterWidgets.entitlements` :
```xml
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
```
(Nécessaire pour lire/écrire les fichiers choisis via NSOpenPanel/NSSavePanel dans une app sandboxée.)

- [ ] **Step 3: Ajouter Importer + Exporter à `GalleryView.swift`**

Bouton « Importer » (à côté de « Nouveau template » de 3b-2) :
```swift
            Button("Importer…") { importBWidget() }
                .buttonStyle(.bordered).tint(DesignTokens.accent)
```
Action Exporter dans le menu de chaque carte :
```swift
                Button("Exporter…") { exportBWidget(manifest.id) }
```
Les fonctions (avec `@State private var importError: String?` + un `.alert`) :
```swift
    private func importBWidget() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []           // filter by extension below
        panel.allowsOtherFileTypes = true
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, url.pathExtension == "bwidget",
              let data = try? Data(contentsOf: url) else { return }
        do { _ = try BWidgetImporter.install(archive: data, into: state.templates) }
        catch { importError = "Import impossible : \(error)" }
    }

    private func exportBWidget(_ id: String) {
        guard let data = try? BWidgetArchive.export(templateDir: state.templates.templateDirectory(id: id)) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(id).bwidget"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }
```
Ajouter `.alert("Import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) { Button("OK") { importError = nil } } message: { Text(importError ?? "") }` sur le conteneur. (Pour forcer le refresh de la liste après import, réutiliser le pattern de refresh de `GalleryView` de 3b-2 — un `@State refreshTick` incrémenté après un import réussi et référencé dans `body`.)

- [ ] **Step 4: Build + suite**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet` + `xcodebuild build ... -quiet`.
Expected: suite verte (106) + `BUILD SUCCEEDED`.

- [ ] **Step 5: Vérification réelle bout-en-bout**

```bash
xcodegen generate && xcodebuild build -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet
APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/BetterWidgets-*/Build/Products/Debug/*.app | head -1)
pkill -x BetterWidgets 2>/dev/null || true; sleep 1
open "$APP"; sleep 8
osascript -e 'tell application "System Events" to tell process "BetterWidgets" to set frontmost to true' 2>/dev/null || true
screencapture -x /tmp/bw-3c-gallery.png 2>/dev/null || true
ls -la /tmp/bw-3c-gallery.png 2>/dev/null || echo "screenshot not captured (screen may be locked)"
```
À vérifier (œil/capture ; si le focus est volé par d'autres agents, piloter via `AXPress`/`CGEventPostToPid` comme en 3b-2) : la Galerie a « Importer… » ; **Exporter** un template (ex. hello-clock) écrit un `.bwidget` (choisir `/tmp/hc.bwidget`) ; **Importer** ce `.bwidget` → apparaît comme template utilisateur, instanciable ; importer un `.bwidget` malformé fabriqué à la main (`echo 'not json' > /tmp/bad.bwidget`) → alerte de refus, rien installé ; sur une carte « Mes widgets » d'une instance météo/agenda, « Permissions… » ouvre la feuille et le toggle persiste. Vérifier aussi qu'un template importé se rend bien dans la même WebView confinée. Rapport honnête si la capture échoue. Sauver `/tmp/bw-3c-gallery.png`.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: gallery import/export of .bwidget files (user-selected file entitlement)"
```

---

## Self-review (fait à l'écriture)

- **Couverture spec** : §3 format/export → Task 1 ; §4 import/validation sandbox → Task 2 ; §5 consentement (model+view, accès Mes widgets) → Tasks 4,5 ; §6 météo localisation → Task 3 ; §7 archi → toutes ; §8 erreurs (ImportError FR, export alerte, localisation stale) → Tasks 2,3,6 ; §9 sécurité (confinement entrées, pas de secret exporté, WebView confinée) → Tasks 1,2 ; §10 tests → Tasks 1-4 (unit) + 5,6 (build+réel) ; §11 zip risque → **résolu par le choix conteneur JSON** (Global Constraints), CLLocation mockable→Task 3, consentement app vs TCC→Tasks 5 (documenté).
- **Décision actée & documentée** : `.bwidget` = conteneur JSON (pas zip) — justifié dans Global Constraints (sandbox + pas de SPM), le spec laissait le mécanisme ouvert. Sécurité *renforcée* (pas d'entrée symlink possible ; le test « symlink » du spec devient « chemin `..`/absolu rejeté », plus pertinent pour ce format).
- **Cohérence des types** : `BWidgetArchive.export/entries` (T1) consommés par `BWidgetImporter` (T2) + Galerie (T6) ; `BWidgetImporter.install(archive:into:)` (T2) consommé par la Galerie (T6) ; `TemplateStore.freshUserID(base:)` exposé (T2) et utilisé par l'importer ; `LocationProvider` (T3) = param `location` de `WeatherDataProvider` ; `PermissionConsentModel(instanceId:manifest:permissions:)` (T4) consommé par `PermissionConsentView`/`MyWidgetsView` (T5) ; `WidgetCard.onPermissions` (T5). `WeatherDataProvider` : `location` défaut → registry + tests existants OK après conversion des call-sites en `geocoder:` labellisé (T3 Step 1).
- **Placeholders** : aucun TODO/TBD ; code complet pour la logique (T1-4, TDD) ; vues (T5,6) build-gated + vérif réelle. Entitlements (localisation, user-selected files) explicités avec le XML exact.
- **Sécurité** : confinement des entrées d'import réutilise `resolvingSymlinksInPath` + prefix (comme `resolveTemplateAsset`), testé (absolu/`..`/hors-whitelist/rien installé) ; pas de secret dans l'export ; HTML importé confiné dans la WebView.
