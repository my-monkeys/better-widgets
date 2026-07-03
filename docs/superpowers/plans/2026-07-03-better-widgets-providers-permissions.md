# Better Widgets — Plan 2 : Providers & Permissions

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter les sources de données `rss`, `calendar` (EventKit) et `weather` (WeatherKit), un **modèle de permission par template** (seules les sources déclarées ET accordées sont injectées), et **durcir la WebView de rendu** (pas de `file://`, assets servis via un scheme dédié confiné au dossier du template) — préparant l'exécution sûre de templates tiers avant l'import `.bwidget` du Plan 3.

**Architecture:** On étend le `DataProviderRegistry` existant avec 3 providers, chacun derrière une **abstraction mockable** (protocole injecté) pour être testable sans réseau/TCC/portail. Un `PermissionStore` (App Group) mémorise les types de sources accordés par instance ; le `RenderPipeline` partitionne les sources du manifest en *autorisées* (fetchées) vs *refusées* (marqueur `__denied` injecté) avant le fetch. Le `RenderEngine` sert les assets du template via un `WKURLSchemeHandler` `bwasset://` confiné au dossier du template et refuse toute navigation `file://`/`http://`.

**Tech Stack:** Swift 5.9, WebKit (`WKURLSchemeHandler`, `WKNavigationDelegate`), Foundation `XMLParser`, EventKit, WeatherKit, CoreLocation (`CLGeocoder`), XCTest. macOS 14+, Xcode 27, XcodeGen.

## Global Constraints

- **Prérequis externe WeatherKit (action Maxim, hors code)** : activer la capability WeatherKit + créer une clé WeatherKit dans le portail Apple Developer (Team `5C67TFSJ2B`) et ajouter l'App ID `fr.my-monkey.BetterWidgets` au service. **Tant que ce n'est pas fait, le provider `weather` build et passe ses tests unitaires (via l'abstraction mockable) mais ne renvoie pas de données réelles.** Aucune tâche de ce plan n'est bloquée par ce prérequis — la vérification en données réelles du provider météo, oui.
- **Pas de dépendance externe** (SPM vide) — uniquement Foundation/AppKit/WebKit/WidgetKit/EventKit/WeatherKit/CoreLocation. Le RSS se parse avec `XMLParser` de Foundation, pas de lib tierce.
- **Le `.xcodeproj` est généré** depuis `project.yml` (gitignoré) — jamais l'éditer à la main ; `xcodegen generate` après tout changement de `project.yml`.
- **Bundle IDs / App Group** : app `fr.my-monkey.BetterWidgets`, extension `fr.my-monkey.BetterWidgets.WidgetExtension`, App Group `5C67TFSJ2B.betterwidgets`. Team `5C67TFSJ2B`.
- **Le durcissement §7 (Task 1) est un prérequis d'ordre** : il DOIT être en place avant toute fonctionnalité d'import de template (Plan 3). Ne pas inverser.
- **Commande de test canonique** : `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`. Point de départ : **32 tests verts** (Plan 1).
- **Fail-soft préservé** : une source qui échoue au fetch → `failedKeys` (donc `stale=true`), jamais un throw qui casse le rendu. Une source *refusée par permission* n'est PAS un échec (ni `failedKeys`, ni `stale`) : c'est un marqueur `__denied` intentionnel.
- **`SourceSpec.knownTypes`** passe de `["json","system"]` à `["json","system","rss","calendar","weather"]`. La vérification du type inconnu reste **au parsing du manifest uniquement** (jamais dans le registry — il route sur les providers fournis).
- **Types nécessitant un consentement** (`SourceSpec.consentRequiredTypes`) : `["calendar","weather"]`. `json`/`system`/`rss` sont libres (aucune permission).
- Code, commentaires et identifiants en **anglais** ; chaînes UI et contenu de template en **français** (données, pas du code).
- Commits : Conventional Commits, auteur `MaximCosta <maxim@users.noreply.github.com>` (déjà configuré), **aucune mention d'IA**.
- Chaque valeur JSON renvoyée par un provider doit être **JSON-serializable** (`JSONSerialization.isValidJSONObject` vrai) : uniquement String/Number/Bool/Array/Dictionary, dates en ISO8601 String.

---

## Structure des fichiers

```
BetterWidgets/Core/
├── Render/
│   ├── RenderEngine.swift          # MODIF : scheme handler bwasset + nav policy (Task 1)
│   ├── TemplateAssetSchemeHandler.swift  # NOUVEAU : sert bwasset://template/<path> depuis templateDir (Task 1)
│   ├── NavigationPolicy.swift      # NOUVEAU : fonction pure de décision de navigation (Task 1)
│   └── RenderPipeline.swift        # MODIF : consulte PermissionStore, partitionne les sources (Task 2)
├── PermissionStore.swift           # NOUVEAU : grants par instance dans l'App Group (Task 2)
├── Models/TemplateManifest.swift   # MODIF : knownTypes + consentRequiredTypes (Task 2)
└── Data/
    ├── RSSDataProvider.swift        # NOUVEAU (Task 3) + RSSFeedParser.swift
    ├── RSSFeedParser.swift          # NOUVEAU : XMLParser RSS/Atom → items (Task 3)
    ├── CalendarDataProvider.swift   # NOUVEAU (Task 4) + EventFetching protocol
    ├── WeatherDataProvider.swift    # NOUVEAU (Task 5) + WeatherFetching protocol
    └── DataProviderRegistry.swift   # MODIF : enregistre rss/calendar/weather (Tasks 3-5)
BetterWidgets/App/AppState.swift     # MODIF : construit PermissionStore, le passe au pipeline (Task 2)
BetterWidgets/Info.plist (via project.yml) # MODIF : usage strings calendar/reminders/location (Tasks 4-5)
BetterWidgets/Resources/templates/   # NOUVEAU : templates démo rss/calendar/weather (Task 6)
Tests/                               # NOUVEAUX fichiers de test par tâche
```

---

### Task 1: Durcir la WebView de rendu (§7) — assets confinés + blocage `file://`

**Files:**
- Create: `BetterWidgets/Core/Render/NavigationPolicy.swift`
- Create: `BetterWidgets/Core/Render/TemplateAssetSchemeHandler.swift`
- Modify: `BetterWidgets/Core/Render/RenderEngine.swift`
- Test: `Tests/NavigationPolicyTests.swift`
- Test: `Tests/TemplateAssetSchemeHandlerTests.swift`

**Interfaces:**
- Consumes: `RenderContext`, `RenderEngine.render(html:baseURL:context:)` (baseURL = dossier du template).
- Produces:
  - `enum NavigationPolicy { static func decide(for url: URL?) -> WKNavigationActionPolicy }` — `.allow` pour `about`/`https`/`bwasset`/`data`, `.cancel` sinon (`file`, `http`, `ftp`, nil).
  - `func resolveTemplateAsset(templateDir: URL, requestPath: String) -> URL?` — mappe un chemin de requête `bwasset://template/<path>` vers `templateDir/<path>`, `nil` si le chemin résolu sort de `templateDir` (traversée `..`) ou n'existe pas.
  - `final class TemplateAssetSchemeHandler: NSObject, WKURLSchemeHandler` construit avec `init(templateDir: URL)`.
  - `RenderEngine.render` inchangé en signature : en interne il enregistre le scheme handler `bwasset` (si `baseURL != nil`) et pose la nav policy.

- [ ] **Step 1: Écrire `Tests/NavigationPolicyTests.swift` (échoue)**

```swift
import XCTest
import WebKit

final class NavigationPolicyTests: XCTestCase {
    func testAllowsHttpsAboutBwassetData() {
        XCTAssertEqual(NavigationPolicy.decide(for: URL(string: "https://api.example.com/x")), .allow)
        XCTAssertEqual(NavigationPolicy.decide(for: URL(string: "about:blank")), .allow)
        XCTAssertEqual(NavigationPolicy.decide(for: URL(string: "bwasset://template/logo.png")), .allow)
        XCTAssertEqual(NavigationPolicy.decide(for: URL(string: "data:image/png;base64,AAAA")), .allow)
    }

    func testBlocksFileHttpAndNil() {
        XCTAssertEqual(NavigationPolicy.decide(for: URL(string: "file:///etc/hosts")), .cancel)
        XCTAssertEqual(NavigationPolicy.decide(for: URL(string: "http://insecure.example.com")), .cancel)
        XCTAssertEqual(NavigationPolicy.decide(for: nil), .cancel)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -only-testing:BetterWidgetsTests/NavigationPolicyTests -quiet`
Expected: FAIL — `cannot find 'NavigationPolicy' in scope`.

- [ ] **Step 3: Implémenter `NavigationPolicy.swift`**

```swift
import WebKit

/// Whitelist of URL schemes the render WebView may navigate to.
/// Everything else (file://, http://, ftp://, nil) is cancelled — a template
/// must not reach the local filesystem or downgrade to cleartext.
enum NavigationPolicy {
    private static let allowedSchemes: Set<String> = ["about", "https", "bwasset", "data"]

    static func decide(for url: URL?) -> WKNavigationActionPolicy {
        guard let scheme = url?.scheme?.lowercased(), allowedSchemes.contains(scheme) else {
            return .cancel
        }
        return .allow
    }
}
```

- [ ] **Step 4: Écrire `Tests/TemplateAssetSchemeHandlerTests.swift` (échoue)**

```swift
import XCTest

final class TemplateAssetSchemeHandlerTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "PNGDATA".write(to: dir.appendingPathComponent("logo.png"), atomically: true, encoding: .utf8)
        let sub = dir.appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "X".write(to: sub.appendingPathComponent("f.css"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testResolvesFileInsideTemplateDir() throws {
        let url = try XCTUnwrap(resolveTemplateAsset(templateDir: dir, requestPath: "/logo.png"))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "PNGDATA")
    }

    func testResolvesNestedAsset() throws {
        XCTAssertNotNil(resolveTemplateAsset(templateDir: dir, requestPath: "/assets/f.css"))
    }

    func testRejectsPathTraversal() {
        XCTAssertNil(resolveTemplateAsset(templateDir: dir, requestPath: "/../../etc/hosts"))
        XCTAssertNil(resolveTemplateAsset(templateDir: dir, requestPath: "/assets/../../../etc/passwd"))
    }

    func testRejectsMissingFile() {
        XCTAssertNil(resolveTemplateAsset(templateDir: dir, requestPath: "/nope.png"))
    }
}
```

- [ ] **Step 5: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/TemplateAssetSchemeHandlerTests -quiet`
Expected: FAIL — `cannot find 'resolveTemplateAsset' in scope`.

- [ ] **Step 6: Implémenter `TemplateAssetSchemeHandler.swift`**

```swift
import WebKit
import UniformTypeIdentifiers

/// Resolves a bwasset://template/<path> request to a real file under templateDir.
/// Returns nil if the resolved path escapes templateDir (traversal) or doesn't exist.
func resolveTemplateAsset(templateDir: URL, requestPath: String) -> URL? {
    let root = templateDir.standardizedFileURL
    let trimmed = requestPath.hasPrefix("/") ? String(requestPath.dropFirst()) : requestPath
    let candidate = root.appendingPathComponent(trimmed).standardizedFileURL
    guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { return nil }
    guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
    return candidate
}

/// Serves template assets over a private bwasset:// scheme so the render WebView
/// never needs file:// access. Only files inside templateDir are reachable.
final class TemplateAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    private let templateDir: URL

    init(templateDir: URL) {
        self.templateDir = templateDir
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let fileURL = resolveTemplateAsset(templateDir: templateDir, requestPath: url.path),
              let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let response = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil)
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
```

- [ ] **Step 7: Câbler dans `RenderEngine.swift`**

Dans `render(html:baseURL:context:)`, après la création de `config` et avant celle du `webView` : si `baseURL != nil`, enregistrer le handler et charger via le scheme confiné ; sinon (aucun asset) charger sans base. Modifier `config` :

```swift
        // Serve the template's own assets over a confined bwasset:// scheme; the
        // WebView gets no file:// access at all (see §7 sandbox hardening).
        let assetBase: URL?
        if let templateDir = baseURL {
            config.setURLSchemeHandler(TemplateAssetSchemeHandler(templateDir: templateDir),
                                       forURLScheme: "bwasset")
            assetBase = URL(string: "bwasset://template/")
        } else {
            assetBase = nil
        }
```

Remplacer la ligne de chargement `webView.loadHTMLString(html, baseURL: baseURL)` par :

```swift
        webView.loadHTMLString(html, baseURL: assetBase)
```

Étendre `NavDelegate` (en bas du fichier) pour appliquer la politique — ajouter cette méthode à `private final class NavDelegate` :

```swift
    nonisolated func webView(_ webView: WKWebView,
                             decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(NavigationPolicy.decide(for: navigationAction.request.url))
    }
```

Note : `about:blank` et le chargement `loadHTMLString`/`bwasset` restent autorisés par `NavigationPolicy`. Le template `hello-clock` (aucun asset externe) passe `baseURL` = son dossier mais ne charge rien via `bwasset` — il doit continuer à rendre identiquement.

- [ ] **Step 8: Vérifier — nouveaux tests + non-régression du rendu**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: PASS. En particulier `RenderEngineTests` (le rendu light/dark @2x de Plan 1) doit rester vert — le changement de base URL ne casse pas le rendu d'un HTML sans asset externe. Si `RenderEngineTests.testMediumSizeDimensions` flake (connu, XPC WKWebView), relancer une fois en isolant ce test.

- [ ] **Step 9: Commit**

```bash
git add -A && git commit -m "feat: sandbox render webview — confined bwasset scheme, block file:// navigation"
```

---

### Task 2: Modèle de permission par template (PermissionStore + gating dans le pipeline)

**Files:**
- Create: `BetterWidgets/Core/PermissionStore.swift`
- Modify: `BetterWidgets/Core/Models/TemplateManifest.swift` (knownTypes + consentRequiredTypes)
- Modify: `BetterWidgets/Core/Render/RenderPipeline.swift` (nouveau param + gating)
- Modify: `BetterWidgets/App/AppState.swift` (construit + injecte le PermissionStore)
- Modify: `Tests/RenderPipelineTests.swift` (nouveau param d'init + 2 nouveaux tests)
- Test: `Tests/PermissionStoreTests.swift`

**Interfaces:**
- Consumes: `SharedStore` (App Group), `DataProviderRegistry`, `WidgetInstance`, `TemplateManifest.sources`.
- Produces:
  - `SourceSpec.knownTypes = ["json","system","rss","calendar","weather"]` ; `SourceSpec.consentRequiredTypes: Set<String> = ["calendar","weather"]` ; `SourceSpec.requiresConsent: Bool { Self.consentRequiredTypes.contains(type) }`.
  - `final class PermissionStore` : `init(baseURL: URL) throws`, `static func appGroup() -> PermissionStore`, `func grantedTypes(instanceId: UUID) -> Set<String>`, `func setGrantedTypes(_ types: Set<String>, instanceId: UUID) throws`, `func grant(type: String, instanceId: UUID) throws`. Fichier `grants.json` = `[uuidString: [type]]`.
  - `RenderPipeline.init` gagne un paramètre `permissions: PermissionStore` (après `shared`). Comportement : une source `requiresConsent` non accordée n'est PAS fetchée ; à la place `data[source.key] = ["__denied": true]` est injecté. Les sources libres et les sources consent-required accordées passent normalement à `fetchAll`. Un refus n'affecte ni `failedKeys` ni `stale`.

- [ ] **Step 1: Écrire `Tests/PermissionStoreTests.swift` (échoue)**

```swift
import XCTest

final class PermissionStoreTests: XCTestCase {
    private var tmp: URL!
    private var store: PermissionStore!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = try PermissionStore(baseURL: tmp)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func testEmptyByDefault() {
        XCTAssertEqual(store.grantedTypes(instanceId: UUID()), [])
    }

    func testGrantAndRead() throws {
        let id = UUID()
        try store.grant(type: "calendar", instanceId: id)
        XCTAssertEqual(store.grantedTypes(instanceId: id), ["calendar"])
    }

    func testSetGrantedTypesRoundTrip() throws {
        let id = UUID()
        try store.setGrantedTypes(["calendar", "weather"], instanceId: id)
        XCTAssertEqual(store.grantedTypes(instanceId: id), ["calendar", "weather"])
        // Isolation between instances.
        XCTAssertEqual(store.grantedTypes(instanceId: UUID()), [])
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/PermissionStoreTests -quiet`
Expected: FAIL — `cannot find 'PermissionStore' in scope`.

- [ ] **Step 3: Implémenter `PermissionStore.swift`**

```swift
import Foundation

/// Per-instance record of which consent-requiring source types the user granted.
/// Lives in the App Group so a future settings UI and the render pipeline share it.
final class PermissionStore {
    static let appGroupID = "5C67TFSJ2B.betterwidgets"

    private let fileURL: URL

    init(baseURL: URL) throws {
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        fileURL = baseURL.appendingPathComponent("grants.json")
    }

    static func appGroup() -> PermissionStore {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            fatalError("App Group \(appGroupID) unavailable — check entitlements")
        }
        return try! PermissionStore(baseURL: container.appendingPathComponent("Store"))
    }

    private func load() -> [String: [String]] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
    }

    private func save(_ grants: [String: [String]]) throws {
        try JSONEncoder().encode(grants).write(to: fileURL, options: .atomic)
    }

    func grantedTypes(instanceId: UUID) -> Set<String> {
        Set(load()[instanceId.uuidString] ?? [])
    }

    func setGrantedTypes(_ types: Set<String>, instanceId: UUID) throws {
        var grants = load()
        grants[instanceId.uuidString] = Array(types).sorted()
        try save(grants)
    }

    func grant(type: String, instanceId: UUID) throws {
        var types = grantedTypes(instanceId: instanceId)
        types.insert(type)
        try setGrantedTypes(types, instanceId: instanceId)
    }
}
```

- [ ] **Step 4: Étendre `TemplateManifest.swift`**

Remplacer la ligne `static let knownTypes: Set<String> = ["json", "system"]` par :

```swift
    static let knownTypes: Set<String> = ["json", "system", "rss", "calendar", "weather"]
    static let consentRequiredTypes: Set<String> = ["calendar", "weather"]
```

Et ajouter dans `struct SourceSpec`, après la déclaration de `config` :

```swift
    var requiresConsent: Bool { Self.consentRequiredTypes.contains(type) }
```

- [ ] **Step 5: Écrire les nouveaux tests de gating dans `Tests/RenderPipelineTests.swift`**

D'abord, mettre à jour le `setUpWithError`/les constructions existantes : chaque `RenderPipeline(templates:shared:registry:engine:reloader:)` devient `RenderPipeline(templates:shared:permissions:registry:engine:reloader:)`. Ajouter une propriété `permissions` au test :

```swift
    private var permissions: PermissionStore!
```

et dans `setUpWithError`, après la création de `shared` :

```swift
        permissions = try PermissionStore(baseURL: tmp.appendingPathComponent("perms"))
```

Mettre à jour les 4 constructions de `RenderPipeline` du fichier pour insérer `permissions: permissions,` juste après `shared: shared,`. (Le template "clock" existant utilise une source `system`, non consent-required → comportement inchangé.)

Ajouter ces deux tests. Ils utilisent un template déclarant une source `calendar` (consent-required) et un moteur/faux provider qui n'a PAS besoin d'être appelé quand refusé :

```swift
    private func writeCalendarTemplate() throws {
        let dir = tmp.appendingPathComponent("templates/calnews")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"{ "id": "calnews", "name": "Cal", "version": "1.0.0", "sizes": ["small"], "refresh": 300, "params": [], "sources": [{"key":"cal","type":"calendar"}] }"#
            .write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "<html></html>".write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }

    /// A consent-requiring source that is NOT granted must be skipped (not fetched)
    /// and injected as a __denied marker — without marking the instance stale.
    func testUngrantedConsentSourceIsDeniedNotFetched() async throws {
        try writeCalendarTemplate()
        final class RecordingEngine: Rendering {
            var lastData: [String: Any] = [:]
            func render(html: String, baseURL: URL?, context: RenderContext) async throws -> Data {
                lastData = context.data
                return Data("png".utf8)
            }
        }
        let engine = RecordingEngine()
        let reloader = FakeReloader()
        // Registry with NO calendar provider: if the pipeline tried to fetch it,
        // it would land in failedKeys → stale. It must not even try.
        let pipeline = RenderPipeline(templates: templates, shared: shared, permissions: permissions,
                                      registry: .standard(), engine: engine, reloader: reloader)
        let instance = WidgetInstance(id: UUID(), name: "c", templateId: "calnews",
                                      size: .small, paramValues: [:])
        await pipeline.refresh(instance)

        let cal = engine.lastData["cal"] as? [String: Any]
        XCTAssertEqual(cal?["__denied"] as? Bool, true)
        XCTAssertFalse(shared.loadState(instanceId: instance.id).stale, "denied ≠ stale")
        XCTAssertNil(shared.loadState(instanceId: instance.id).lastError)
        XCTAssertEqual(reloader.kinds, ["bw.small"])
    }

    /// Once granted, the source is passed to the registry (here it fails → failedKeys/stale,
    /// which proves it was actually attempted rather than denied).
    func testGrantedConsentSourceIsAttempted() async throws {
        try writeCalendarTemplate()
        let instance = WidgetInstance(id: UUID(), name: "c", templateId: "calnews",
                                      size: .small, paramValues: [:])
        try permissions.grant(type: "calendar", instanceId: instance.id)
        let engine = FakeEngine()
        let pipeline = RenderPipeline(templates: templates, shared: shared, permissions: permissions,
                                      registry: .standard(), engine: engine, reloader: FakeReloader())
        await pipeline.refresh(instance)
        // .standard() has no calendar provider → attempted fetch fails → stale true.
        XCTAssertTrue(shared.loadState(instanceId: instance.id).stale)
    }
```

- [ ] **Step 6: Vérifier l'échec (compile)**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/RenderPipelineTests -quiet`
Expected: FAIL — `RenderPipeline` n'a pas de paramètre `permissions` (erreur de compilation).

- [ ] **Step 7: Modifier `RenderPipeline.swift`**

Ajouter la propriété + le paramètre d'init et le gating. Dans la classe, ajouter `private let permissions: PermissionStore` ; dans l'init, insérer `permissions: PermissionStore` après `shared: SharedStore` et `self.permissions = permissions`. Puis, dans `refresh`, remplacer le bloc fetch existant

```swift
            let fetch = await registry.fetchAll(sources: manifest.sources, paramValues: params)
            state.lastFetchAt = Date()
            state.stale = !fetch.failedKeys.isEmpty
```

par :

```swift
            // Partition sources by permission: consent-requiring types that the
            // user hasn't granted are never fetched — they're injected as a
            // __denied marker (which is intentional, not a fetch failure).
            let granted = permissions.grantedTypes(instanceId: instance.id)
            let allowed = manifest.sources.filter { !$0.requiresConsent || granted.contains($0.type) }
            let denied = manifest.sources.filter { $0.requiresConsent && !granted.contains($0.type) }

            let fetch = await registry.fetchAll(sources: allowed, paramValues: params)
            var data = fetch.data
            for source in denied { data[source.key] = ["__denied": true] }

            state.lastFetchAt = Date()
            state.stale = !fetch.failedKeys.isEmpty
```

Puis, dans la boucle de rendu, remplacer `data: fetch.data` par `data: data` dans la construction de `RenderContext`.

- [ ] **Step 8: Modifier `AppState.swift`**

Ajouter la propriété et l'injecter dans le pipeline. Après `let templates = TemplateStore.applicationSupport()`, ajouter :

```swift
    let permissions = PermissionStore.appGroup()
```

et dans la construction de `pipeline`, insérer `permissions: permissions,` après `shared: shared,` :

```swift
    private lazy var pipeline = RenderPipeline(
        templates: templates, shared: shared, permissions: permissions,
        registry: .standard(), engine: RenderEngine(), reloader: WidgetCenterReloader())
```

- [ ] **Step 9: Vérifier — suite complète**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: PASS (les tests existants + PermissionStoreTests + les 2 nouveaux tests de gating).

- [ ] **Step 10: Commit**

```bash
git add -A && git commit -m "feat: per-template permission model — gate consent-requiring sources in the pipeline"
```

---

### Task 3: Provider `rss` (Foundation XMLParser, RSS 2.0 + Atom)

**Files:**
- Create: `BetterWidgets/Core/Data/RSSFeedParser.swift`
- Create: `BetterWidgets/Core/Data/RSSDataProvider.swift`
- Modify: `BetterWidgets/Core/Data/DataProviderRegistry.swift` (enregistrer le provider)
- Test: `Tests/RSSFeedParserTests.swift`
- Test: `Tests/RSSDataProviderTests.swift`

**Interfaces:**
- Consumes: `DataProvider` protocol, `SourceSpec`, `substituteParams`, `DataProviderError`.
- Produces:
  - `struct RSSItem: Equatable { let title: String; let link: String; let published: String?; let summary: String? }`
  - `enum RSSFeedParser { static func parse(_ data: Data) -> (title: String?, items: [RSSItem]) }` — supporte RSS 2.0 (`<item><title><link><description><pubDate>`) et Atom (`<entry><title><link href><summary><updated>`).
  - `struct RSSDataProvider: DataProvider` : `static let type = "rss"`, `minimumInterval = 900`, `init(urlSession:)`. `config.url` requis (https). Renvoie `["title": String?, "items": [[String: Any]]]` (chaque item = dict title/link/published/summary, valeurs manquantes omises).
  - Enregistré dans `DataProviderRegistry.standard()`.

- [ ] **Step 1: Écrire `Tests/RSSFeedParserTests.swift` (échoue)**

```swift
import XCTest

final class RSSFeedParserTests: XCTestCase {
    func testParsesRSS2() {
        let xml = """
        <?xml version="1.0"?><rss version="2.0"><channel>
        <title>My Feed</title>
        <item><title>First</title><link>https://ex.com/1</link>
          <description>Hello</description><pubDate>Mon, 01 Jul 2026 10:00:00 GMT</pubDate></item>
        <item><title>Second</title><link>https://ex.com/2</link></item>
        </channel></rss>
        """
        let result = RSSFeedParser.parse(Data(xml.utf8))
        XCTAssertEqual(result.title, "My Feed")
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items[0], RSSItem(title: "First", link: "https://ex.com/1",
                                                published: "Mon, 01 Jul 2026 10:00:00 GMT", summary: "Hello"))
        XCTAssertEqual(result.items[1].title, "Second")
        XCTAssertNil(result.items[1].summary)
    }

    func testParsesAtom() {
        let xml = """
        <?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom">
        <title>Atom Feed</title>
        <entry><title>Post</title><link href="https://ex.com/a"/>
          <summary>Sum</summary><updated>2026-07-01T10:00:00Z</updated></entry>
        </feed>
        """
        let result = RSSFeedParser.parse(Data(xml.utf8))
        XCTAssertEqual(result.title, "Atom Feed")
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].title, "Post")
        XCTAssertEqual(result.items[0].link, "https://ex.com/a")
        XCTAssertEqual(result.items[0].summary, "Sum")
        XCTAssertEqual(result.items[0].published, "2026-07-01T10:00:00Z")
    }

    func testEmptyOnGarbage() {
        let result = RSSFeedParser.parse(Data("not xml".utf8))
        XCTAssertTrue(result.items.isEmpty)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/RSSFeedParserTests -quiet`
Expected: FAIL — `cannot find 'RSSFeedParser' in scope`.

- [ ] **Step 3: Implémenter `RSSFeedParser.swift`**

```swift
import Foundation

struct RSSItem: Equatable {
    let title: String
    let link: String
    let published: String?
    let summary: String?
}

/// Minimal RSS 2.0 + Atom parser over Foundation's XMLParser (no third-party dep).
enum RSSFeedParser {
    static func parse(_ data: Data) -> (title: String?, items: [RSSItem]) {
        let delegate = FeedDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return (delegate.feedTitle, delegate.items)
    }
}

private final class FeedDelegate: NSObject, XMLParserDelegate {
    private(set) var feedTitle: String?
    private(set) var items: [RSSItem] = []

    private var inItem = false
    private var seenFeedTitle = false
    private var text = ""
    private var curTitle = "", curLink = "", curSummary = "", curPublished = ""
    private var hasSummary = false, hasPublished = false

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes attrs: [String: String]) {
        text = ""
        if name == "item" || name == "entry" {
            inItem = true
            curTitle = ""; curLink = ""; curSummary = ""; curPublished = ""
            hasSummary = false; hasPublished = false
        } else if inItem, name == "link", let href = attrs["href"] {
            curLink = href // Atom link is an attribute
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "item" || name == "entry" {
            items.append(RSSItem(title: curTitle, link: curLink,
                                 published: hasPublished ? curPublished : nil,
                                 summary: hasSummary ? curSummary : nil))
            inItem = false
            return
        }
        if inItem {
            switch name {
            case "title": curTitle = value
            case "link" where !value.isEmpty: curLink = value // RSS link is text
            case "description", "summary", "content": curSummary = value; hasSummary = true
            case "pubDate", "updated", "published": curPublished = value; hasPublished = true
            default: break
            }
        } else if name == "title", !seenFeedTitle {
            feedTitle = value
            seenFeedTitle = true
        }
    }
}
```

- [ ] **Step 4: Écrire `Tests/RSSDataProviderTests.swift` (échoue)**

```swift
import XCTest

final class RSSDataProviderTests: XCTestCase {
    func testTypeAndInterval() {
        XCTAssertEqual(RSSDataProvider.type, "rss")
        XCTAssertGreaterThanOrEqual(RSSDataProvider(urlSession: .shared).minimumInterval, 900)
    }

    func testMissingURLThrows() async {
        do {
            _ = try await RSSDataProvider(urlSession: .shared)
                .fetch(spec: SourceSpec(key: "f", type: "rss", config: nil), paramValues: [:])
            XCTFail("expected throw")
        } catch { /* expected */ }
    }

    func testNonHttpsRejected() async {
        do {
            _ = try await RSSDataProvider(urlSession: .shared)
                .fetch(spec: SourceSpec(key: "f", type: "rss", config: ["url": "http://ex.com/feed"]),
                       paramValues: [:])
            XCTFail("expected throw")
        } catch { /* expected */ }
    }

    func testRegistryIncludesRSS() {
        // .standard() must route "rss" to a provider (otherwise every rss source fails).
        let registry = DataProviderRegistry.standard()
        // Indirect check: an rss source with a bad URL should FAIL (routed, then errors),
        // not be an unknown-type no-op. We assert it lands in failedKeys, meaning it was routed.
        let exp = expectation(description: "fetch")
        Task {
            let r = await registry.fetchAll(
                sources: [SourceSpec(key: "f", type: "rss", config: ["url": "https://0.0.0.0/nope"])],
                paramValues: [:])
            XCTAssertEqual(r.failedKeys, ["f"])
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)
    }
}
```

- [ ] **Step 5: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/RSSDataProviderTests -quiet`
Expected: FAIL — `cannot find 'RSSDataProvider' in scope`.

- [ ] **Step 6: Implémenter `RSSDataProvider.swift`**

```swift
import Foundation

struct RSSDataProvider: DataProvider {
    static let type = "rss"
    let minimumInterval: TimeInterval = 900
    let urlSession: URLSession

    func fetch(spec: SourceSpec, paramValues: [String: String]) async throws -> Any {
        guard let rawURL = spec.config?["url"] else {
            throw DataProviderError.missingConfig("rss source '\(spec.key)' requires config.url")
        }
        let urlString = substituteParams(rawURL, params: paramValues)
        guard let url = URL(string: urlString), url.scheme == "https" else {
            throw DataProviderError.badURL(urlString)
        }
        let (data, response) = try await urlSession.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DataProviderError.httpError(http.statusCode)
        }
        let parsed = RSSFeedParser.parse(data)
        let items: [[String: Any]] = parsed.items.map { item in
            var dict: [String: Any] = ["title": item.title, "link": item.link]
            if let published = item.published { dict["published"] = published }
            if let summary = item.summary { dict["summary"] = summary }
            return dict
        }
        var result: [String: Any] = ["items": items]
        if let title = parsed.title { result["title"] = title }
        return result
    }
}
```

- [ ] **Step 7: Enregistrer dans `DataProviderRegistry.standard()`**

Ajouter `RSSDataProvider(urlSession: urlSession),` à la liste des providers dans `standard()`.

- [ ] **Step 8: Vérifier — suite complète**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: PASS (RSSFeedParserTests + RSSDataProviderTests + suite existante). Le test `testRegistryIncludesRSS` fait un vrai fetch en échec vers une IP non routable — s'il traîne, c'est le timeout réseau ; il doit finir en `failedKeys` bien avant 10 s.

- [ ] **Step 9: Commit**

```bash
git add -A && git commit -m "feat: rss data provider — RSS 2.0 + Atom parsing over XMLParser"
```

---

### Task 4: Provider `calendar` (EventKit derrière une abstraction mockable)

**Files:**
- Create: `BetterWidgets/Core/Data/CalendarDataProvider.swift`
- Modify: `BetterWidgets/Core/Data/DataProviderRegistry.swift`
- Modify: `project.yml` (usage strings EventKit dans l'Info.plist de l'app)
- Test: `Tests/CalendarDataProviderTests.swift`

**Interfaces:**
- Consumes: `DataProvider`, `SourceSpec`, `DataProviderError`.
- Produces:
  - `struct CalendarEventDTO: Equatable { let title: String; let start: Date; let end: Date; let allDay: Bool; let location: String? }`
  - `protocol EventFetching { func upcomingEvents(within days: Int) async throws -> [CalendarEventDTO] }`
  - `struct EventKitFetcher: EventFetching` — vraie implémentation (demande l'accès via `EKEventStore.requestFullAccessToEvents`, requête sur `days` à venir).
  - `struct CalendarDataProvider: DataProvider` : `static let type = "calendar"`, `minimumInterval = 300`, `init(fetcher: EventFetching)`. `config["days"]` optionnel (défaut 7). Renvoie `["events": [[String:Any]]]` (start/end en ISO8601 String).
  - Enregistré dans `DataProviderRegistry.standard()` avec `EventKitFetcher()`.

- [ ] **Step 1: Écrire `Tests/CalendarDataProviderTests.swift` (échoue)**

```swift
import XCTest

final class CalendarDataProviderTests: XCTestCase {
    private struct FakeFetcher: EventFetching {
        let events: [CalendarEventDTO]
        var thrown: Error?
        func upcomingEvents(within days: Int) async throws -> [CalendarEventDTO] {
            if let thrown { throw thrown }
            return events
        }
    }

    func testTypeAndInterval() {
        XCTAssertEqual(CalendarDataProvider.type, "calendar")
        XCTAssertGreaterThanOrEqual(CalendarDataProvider(fetcher: FakeFetcher(events: [])).minimumInterval, 60)
    }

    func testMapsEventsToJSON() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let event = CalendarEventDTO(title: "Standup", start: start,
                                     end: start.addingTimeInterval(1800), allDay: false, location: "Zoom")
        let provider = CalendarDataProvider(fetcher: FakeFetcher(events: [event]))
        let result = try await provider.fetch(spec: SourceSpec(key: "cal", type: "calendar", config: nil),
                                              paramValues: [:])
        let dict = try XCTUnwrap(result as? [String: Any])
        let events = try XCTUnwrap(dict["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0]["title"] as? String, "Standup")
        XCTAssertEqual(events[0]["location"] as? String, "Zoom")
        XCTAssertNotNil(events[0]["start"] as? String) // ISO8601
        XCTAssertTrue(JSONSerialization.isValidJSONObject(dict))
    }

    func testPropagatesFetcherError() async {
        let provider = CalendarDataProvider(fetcher: FakeFetcher(events: [], thrown: DataProviderError.missingConfig("no access")))
        do {
            _ = try await provider.fetch(spec: SourceSpec(key: "cal", type: "calendar", config: nil), paramValues: [:])
            XCTFail("expected throw")
        } catch { /* expected — becomes a failedKey upstream */ }
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/CalendarDataProviderTests -quiet`
Expected: FAIL — `cannot find 'CalendarDataProvider' in scope`.

- [ ] **Step 3: Implémenter `CalendarDataProvider.swift`**

```swift
import Foundation
import EventKit

struct CalendarEventDTO: Equatable {
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let location: String?
}

protocol EventFetching {
    func upcomingEvents(within days: Int) async throws -> [CalendarEventDTO]
}

/// Real EventKit-backed fetcher. Requests calendar access, then queries events
/// from now to `days` ahead across all calendars.
struct EventKitFetcher: EventFetching {
    func upcomingEvents(within days: Int) async throws -> [CalendarEventDTO] {
        let store = EKEventStore()
        let granted = try await store.requestFullAccessToEvents()
        guard granted else { throw DataProviderError.missingConfig("calendar access denied") }
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map {
            CalendarEventDTO(title: $0.title ?? "", start: $0.startDate, end: $0.endDate,
                             allDay: $0.isAllDay, location: $0.location)
        }
    }
}

struct CalendarDataProvider: DataProvider {
    static let type = "calendar"
    let minimumInterval: TimeInterval = 300
    let fetcher: EventFetching

    func fetch(spec: SourceSpec, paramValues: [String: String]) async throws -> Any {
        let days = spec.config?["days"].flatMap(Int.init) ?? 7
        let events = try await fetcher.upcomingEvents(within: days)
        let iso = ISO8601DateFormatter()
        let mapped: [[String: Any]] = events.map { event in
            var dict: [String: Any] = [
                "title": event.title,
                "start": iso.string(from: event.start),
                "end": iso.string(from: event.end),
                "allDay": event.allDay,
            ]
            if let location = event.location { dict["location"] = location }
            return dict
        }
        return ["events": mapped]
    }
}
```

- [ ] **Step 4: Enregistrer dans le registry + usage strings**

Ajouter `CalendarDataProvider(fetcher: EventKitFetcher()),` à `DataProviderRegistry.standard()`.

Dans `project.yml`, sous le target `BetterWidgets` → `info` → `properties`, ajouter les usage strings (EventKit crash sans elles au premier accès) :

```yaml
        NSCalendarsFullAccessUsageDescription: "Better Widgets lit vos évènements à venir pour les afficher dans un widget."
        NSRemindersFullAccessUsageDescription: "Better Widgets lit vos rappels à venir pour les afficher dans un widget."
```

- [ ] **Step 5: Vérifier — suite complète**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: PASS. Les tests utilisent `FakeFetcher` — aucune permission TCC réelle n'est déclenchée pendant les tests.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: calendar data provider via EventKit behind a mockable fetcher"
```

---

### Task 5: Provider `weather` (WeatherKit derrière une abstraction mockable)

**⚠️ Prérequis externe** : le path réel WeatherKit nécessite la capability + clé WeatherKit au portail Apple Developer (action Maxim). Cette tâche livre le provider **buildé et testé unitairement via un faux service** ; la vérification en données réelles est reportée à ce provisioning. Ne PAS ajouter d'entitlement WeatherKit à `project.yml` dans cette tâche (ça ferait échouer la signature tant que la capability n'existe pas au portail) — le `WeatherKitService` réel est isolé derrière le protocole et n'est pas exercé par les tests.

**Files:**
- Create: `BetterWidgets/Core/Data/WeatherDataProvider.swift`
- Modify: `BetterWidgets/Core/Data/DataProviderRegistry.swift`
- Test: `Tests/WeatherDataProviderTests.swift`

**Interfaces:**
- Consumes: `DataProvider`, `SourceSpec`, `DataProviderError`, `substituteParams`.
- Produces:
  - `struct WeatherDTO: Equatable { let temperature: Double; let conditionCode: String; let symbolName: String; let humidity: Double }`
  - `protocol WeatherFetching { func currentWeather(latitude: Double, longitude: Double) async throws -> WeatherDTO }`
  - `struct WeatherKitService: WeatherFetching` — vraie implémentation (isolée, non testée ; utilise `import WeatherKit`).
  - `func geocodeCity(_ city: String) async throws -> (lat: Double, lon: Double)` — via `CLGeocoder` (pas d'entitlement).
  - `struct WeatherDataProvider: DataProvider` : `static let type = "weather"`, `minimumInterval = 900`, `init(fetcher: WeatherFetching, geocoder: (String) async throws -> (lat: Double, lon: Double))`. `config`: soit `lat`+`lon`, soit `city` (géocodé). Renvoie `["temperature":Double, "condition":String, "symbol":String, "humidity":Double]`.
  - Enregistré dans `DataProviderRegistry.standard()` avec `WeatherKitService()` + `geocodeCity`.

- [ ] **Step 1: Écrire `Tests/WeatherDataProviderTests.swift` (échoue)**

```swift
import XCTest

final class WeatherDataProviderTests: XCTestCase {
    private struct FakeWeather: WeatherFetching {
        let dto: WeatherDTO
        var lastCoords: (Double, Double)?
        func currentWeather(latitude: Double, longitude: Double) async throws -> WeatherDTO {
            return dto
        }
    }
    private let sample = WeatherDTO(temperature: 21.5, conditionCode: "Clear",
                                    symbolName: "sun.max", humidity: 0.4)

    func testTypeAndInterval() {
        let p = WeatherDataProvider(fetcher: FakeWeather(dto: sample)) { _ in (0, 0) }
        XCTAssertEqual(WeatherDataProvider.type, "weather")
        XCTAssertGreaterThanOrEqual(p.minimumInterval, 900)
    }

    func testUsesExplicitLatLon() async throws {
        let p = WeatherDataProvider(fetcher: FakeWeather(dto: sample)) { _ in
            XCTFail("geocoder must not be called when lat/lon provided"); return (0, 0)
        }
        let result = try await p.fetch(
            spec: SourceSpec(key: "w", type: "weather", config: ["lat": "43.6", "lon": "3.87"]),
            paramValues: [:])
        let dict = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(dict["temperature"] as? Double, 21.5)
        XCTAssertEqual(dict["condition"] as? String, "Clear")
        XCTAssertEqual(dict["symbol"] as? String, "sun.max")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(dict))
    }

    func testGeocodesCityWhenNoLatLon() async throws {
        var geocoded = false
        let p = WeatherDataProvider(fetcher: FakeWeather(dto: sample)) { city in
            geocoded = true
            XCTAssertEqual(city, "Montpellier")
            return (43.6, 3.87)
        }
        _ = try await p.fetch(spec: SourceSpec(key: "w", type: "weather", config: ["city": "Montpellier"]),
                              paramValues: [:])
        XCTAssertTrue(geocoded)
    }

    func testMissingLocationThrows() async {
        let p = WeatherDataProvider(fetcher: FakeWeather(dto: sample)) { _ in (0, 0) }
        do {
            _ = try await p.fetch(spec: SourceSpec(key: "w", type: "weather", config: nil), paramValues: [:])
            XCTFail("expected throw")
        } catch { /* expected */ }
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/WeatherDataProviderTests -quiet`
Expected: FAIL — `cannot find 'WeatherDataProvider' in scope`.

- [ ] **Step 3: Implémenter `WeatherDataProvider.swift`**

```swift
import Foundation
import CoreLocation
import WeatherKit

struct WeatherDTO: Equatable {
    let temperature: Double
    let conditionCode: String
    let symbolName: String
    let humidity: Double
}

protocol WeatherFetching {
    func currentWeather(latitude: Double, longitude: Double) async throws -> WeatherDTO
}

/// Real WeatherKit implementation. Not exercised by unit tests — requires the
/// WeatherKit capability + key provisioned in the Apple Developer portal.
struct WeatherKitService: WeatherFetching {
    func currentWeather(latitude: Double, longitude: Double) async throws -> WeatherDTO {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let current = try await WeatherService.shared.weather(for: location, including: .current)
        return WeatherDTO(temperature: current.temperature.value,
                          conditionCode: "\(current.condition)",
                          symbolName: current.symbolName,
                          humidity: current.humidity)
    }
}

/// Geocodes a city name to coordinates via CoreLocation (no entitlement needed).
func geocodeCity(_ city: String) async throws -> (lat: Double, lon: Double) {
    let placemarks = try await CLGeocoder().geocodeAddressString(city)
    guard let location = placemarks.first?.location else {
        throw DataProviderError.badURL("cannot geocode city '\(city)'")
    }
    return (location.coordinate.latitude, location.coordinate.longitude)
}

struct WeatherDataProvider: DataProvider {
    static let type = "weather"
    let minimumInterval: TimeInterval = 900
    let fetcher: WeatherFetching
    let geocoder: (String) async throws -> (lat: Double, lon: Double)

    init(fetcher: WeatherFetching,
         geocoder: @escaping (String) async throws -> (lat: Double, lon: Double)) {
        self.fetcher = fetcher
        self.geocoder = geocoder
    }

    func fetch(spec: SourceSpec, paramValues: [String: String]) async throws -> Any {
        let coords: (lat: Double, lon: Double)
        if let latStr = spec.config?["lat"], let lonStr = spec.config?["lon"],
           let lat = Double(substituteParams(latStr, params: paramValues)),
           let lon = Double(substituteParams(lonStr, params: paramValues)) {
            coords = (lat, lon)
        } else if let city = spec.config?["city"] {
            coords = try await geocoder(substituteParams(city, params: paramValues))
        } else {
            throw DataProviderError.missingConfig("weather source '\(spec.key)' requires lat+lon or city")
        }
        let weather = try await fetcher.currentWeather(latitude: coords.lat, longitude: coords.lon)
        return [
            "temperature": weather.temperature,
            "condition": weather.conditionCode,
            "symbol": weather.symbolName,
            "humidity": weather.humidity,
        ]
    }
}
```

- [ ] **Step 4: Enregistrer dans le registry**

Ajouter à `DataProviderRegistry.standard()` :

```swift
            WeatherDataProvider(fetcher: WeatherKitService(), geocoder: geocodeCity),
```

- [ ] **Step 5: Vérifier — suite complète (build inclut WeatherKit)**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: PASS. `import WeatherKit` compile sur macOS 14 sans capability (l'appel réel échouerait à l'exécution sans clé, mais aucun test ne l'exerce — ils passent tous par `FakeWeather`). Si le **link** échoue faute d'entitlement WeatherKit, retirer temporairement l'enregistrement `WeatherDataProvider(...)` de `standard()` (garder le fichier + ses tests unitaires) et le noter en `DONE_WITH_CONCERNS` : le provider reste prêt, à réenregistrer après le provisioning portail.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: weather data provider via WeatherKit behind a mockable fetcher (+ city geocoding)"
```

---

### Task 6: Templates démo (rss/calendar/weather) + docs, bout-en-bout

**Files:**
- Create: `BetterWidgets/Resources/templates/feed-list/{manifest.json,index.html}`
- Create: `BetterWidgets/Resources/templates/agenda/{manifest.json,index.html}`
- Create: `BetterWidgets/Resources/templates/weather-now/{manifest.json,index.html}`
- Modify: `CLAUDE.md` (statut plans, nouveaux providers, permission model, sandbox)
- Test: `Tests/Plan2ManifestTests.swift`

**Interfaces:**
- Consumes: `TemplateManifest.validated`, `TemplateStore` (bootstrap des templates bundlés existant).
- Produces: 3 templates bundlés qui déclarent respectivement une source `rss`/`calendar`/`weather` et exploitent `window.BW.data` (dont le marqueur `__denied` pour les sources consent-required).

- [ ] **Step 1: Écrire `Tests/Plan2ManifestTests.swift` (échoue)**

```swift
import XCTest

final class Plan2ManifestTests: XCTestCase {
    private func manifest(type: String) -> Data {
        """
        { "id": "t", "name": "T", "version": "1.0.0", "sizes": ["medium"], "refresh": 900,
          "params": [], "sources": [{ "key": "s", "type": "\(type)" }] }
        """.data(using: .utf8)!
    }

    func testNewSourceTypesValidate() throws {
        for type in ["rss", "calendar", "weather"] {
            XCTAssertNoThrow(try TemplateManifest.validated(from: manifest(type: type)),
                             "\(type) should be a known source type")
        }
    }

    func testConsentFlagOnlyForCalendarAndWeather() {
        XCTAssertTrue(SourceSpec(key: "s", type: "calendar", config: nil).requiresConsent)
        XCTAssertTrue(SourceSpec(key: "s", type: "weather", config: nil).requiresConsent)
        XCTAssertFalse(SourceSpec(key: "s", type: "rss", config: nil).requiresConsent)
        XCTAssertFalse(SourceSpec(key: "s", type: "system", config: nil).requiresConsent)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/Plan2ManifestTests -quiet`
Expected: PASS déjà si Tasks 2-5 sont faites (knownTypes/consentRequiredTypes en place). Si Task 6 est exécutée seule dans l'ordre du plan, ces tests valident la cohérence — ils NE doivent PAS échouer à ce stade (les types sont déjà connus). C'est un test de garde, pas un test RED classique. (S'ils échouent, une tâche précédente a régressé knownTypes.)

- [ ] **Step 3: Créer le template `feed-list` (rss, aucune permission)**

`manifest.json` :

```json
{
  "id": "feed-list",
  "name": "Fil d'actualité",
  "version": "1.0.0",
  "sizes": ["medium", "large"],
  "refresh": 900,
  "params": [
    { "key": "url", "type": "url", "label": "URL du flux RSS", "default": "https://hnrss.org/frontpage" },
    { "key": "accent", "type": "color", "label": "Couleur d'accent", "default": "#e8590c" }
  ],
  "sources": [{ "key": "feed", "type": "rss", "config": { "url": "{{url}}" } }]
}
```

`index.html` :

```html
<!doctype html><html><head><meta charset="utf-8"><style>
  html,body{margin:0;width:100%;height:100%;overflow:hidden;
    font-family:-apple-system,"SF Pro Text",sans-serif;background:#faf8f4;color:#1a1a1a}
  @media (prefers-color-scheme:dark){body{background:#14110c;color:#f0ece4}}
  .h{font-size:12px;text-transform:uppercase;letter-spacing:.08em;opacity:.55;padding:14px 16px 8px}
  ul{list-style:none;margin:0;padding:0 16px}
  li{padding:7px 0;border-top:1px solid rgba(128,128,128,.18);font-size:14px;line-height:1.25;
    overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  li:first-child{border-top:none}
  .dot{display:inline-block;width:6px;height:6px;border-radius:50%;margin-right:8px;vertical-align:middle}
</style></head><body>
<div class="h" id="title">Fil</div><ul id="list"></ul>
<script>
  const feed = window.BW.data.feed || {};
  document.getElementById("title").textContent = feed.title || "Fil d'actualité";
  const list = document.getElementById("list");
  (feed.items || []).slice(0, 6).forEach(it => {
    const li = document.createElement("li");
    const dot = document.createElement("span");
    dot.className = "dot"; dot.style.background = window.BW.params.accent;
    li.appendChild(dot); li.appendChild(document.createTextNode(it.title));
    list.appendChild(li);
  });
</script></body></html>
```

- [ ] **Step 4: Créer le template `agenda` (calendar, consent-required — gère `__denied`)**

`manifest.json` :

```json
{
  "id": "agenda",
  "name": "Agenda",
  "version": "1.0.0",
  "sizes": ["medium", "large"],
  "refresh": 300,
  "params": [{ "key": "accent", "type": "color", "label": "Couleur d'accent", "default": "#1c7ed6" }],
  "sources": [{ "key": "cal", "type": "calendar", "config": { "days": "7" } }]
}
```

`index.html` (affiche un état « autoriser » si `__denied`) :

```html
<!doctype html><html><head><meta charset="utf-8"><style>
  html,body{margin:0;width:100%;height:100%;overflow:hidden;
    font-family:-apple-system,"SF Pro Text",sans-serif;background:#f7f9fc;color:#152238}
  @media (prefers-color-scheme:dark){body{background:#0d1420;color:#e7edf6}}
  .wrap{padding:14px 16px}.h{font-size:12px;text-transform:uppercase;letter-spacing:.08em;opacity:.55}
  .row{display:flex;gap:10px;padding:8px 0;border-top:1px solid rgba(128,128,128,.18);font-size:14px}
  .row:first-of-type{border-top:none}.t{font-variant-numeric:tabular-nums;opacity:.7;min-width:44px}
  .empty{opacity:.5;font-size:13px;margin-top:20px;text-align:center}
</style></head><body><div class="wrap">
<div class="h">Agenda</div><div id="body"></div></div>
<script>
  const cal = window.BW.data.cal || {};
  const body = document.getElementById("body");
  if (cal.__denied) {
    body.innerHTML = '<div class="empty">Autorise l\\'accès au calendrier dans Better Widgets</div>';
  } else {
    const events = (cal.events || []).slice(0, 5);
    if (!events.length) { body.innerHTML = '<div class="empty">Rien à venir</div>'; }
    events.forEach(ev => {
      const d = new Date(ev.start);
      const row = document.createElement("div"); row.className = "row";
      const t = document.createElement("span"); t.className = "t";
      t.style.color = window.BW.params.accent;
      t.textContent = ev.allDay ? "—" : d.toLocaleTimeString("fr-FR",{hour:"2-digit",minute:"2-digit"});
      const title = document.createElement("span"); title.textContent = ev.title;
      row.appendChild(t); row.appendChild(title); body.appendChild(row);
    });
  }
</script></body></html>
```

- [ ] **Step 5: Créer le template `weather-now` (weather, consent-required — gère `__denied`)**

`manifest.json` :

```json
{
  "id": "weather-now",
  "name": "Météo",
  "version": "1.0.0",
  "sizes": ["small", "medium"],
  "refresh": 900,
  "params": [{ "key": "city", "type": "string", "label": "Ville", "default": "Montpellier" }],
  "sources": [{ "key": "w", "type": "weather", "config": { "city": "{{city}}" } }]
}
```

`index.html` :

```html
<!doctype html><html><head><meta charset="utf-8"><style>
  html,body{margin:0;width:100%;height:100%;overflow:hidden;
    display:flex;flex-direction:column;justify-content:center;align-items:center;
    font-family:-apple-system,"SF Pro Display",sans-serif;background:#eaf3fb;color:#0d2033}
  @media (prefers-color-scheme:dark){body{background:#0b1622;color:#e7f0fa}}
  .temp{font-size:46px;font-weight:700;letter-spacing:-.03em}
  .city{font-size:13px;opacity:.6;margin-top:2px}.cond{font-size:12px;opacity:.5;margin-top:6px}
  .empty{opacity:.5;font-size:12px;text-align:center;padding:0 16px}
</style></head><body>
<div id="root"></div>
<script>
  const w = window.BW.data.w || {};
  const root = document.getElementById("root");
  if (w.__denied) {
    root.innerHTML = '<div class="empty">Autorise la météo dans Better Widgets</div>';
  } else if (w.temperature === undefined) {
    root.innerHTML = '<div class="empty">Météo indisponible</div>';
  } else {
    root.innerHTML =
      '<div class="temp">' + Math.round(w.temperature) + '°</div>' +
      '<div class="city">' + window.BW.params.city + '</div>' +
      '<div class="cond">' + (w.condition || '') + '</div>';
  }
</script></body></html>
```

- [ ] **Step 6: Mettre à jour `CLAUDE.md`**

Dans la section « État d'avancement des plans », passer **Plan 2** de la description prévisionnelle à « **fait** » avec : providers `rss`/`calendar`/`weather` (les 2 derniers derrière une abstraction mockable, `weather` en attente du provisioning WeatherKit portail pour les données réelles), `PermissionStore` (App Group, grants par instance) + gating dans le pipeline (`__denied`), durcissement WebView (`bwasset://` confiné + blocage `file://`). Ajouter à l'archi Core : `PermissionStore.swift`, `Render/NavigationPolicy.swift`, `Render/TemplateAssetSchemeHandler.swift`, `Data/{RSS,Calendar,Weather}DataProvider.swift` + `RSSFeedParser.swift`. Mettre à jour le compte de tests (32 → nouveau total).

- [ ] **Step 7: Vérifier — suite + smoke bout-en-bout**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: PASS.

Run: `./scripts/smoke.sh`
Expected: `✅ smoke OK` — l'app boot toujours, rend le widget démo (`hello-clock`), et les 3 nouveaux templates apparaissent dans le bootstrap sans casser le rendu. (Le smoke ne vérifie que `hello-clock` ; les templates rss/calendar/weather sont exercés par leurs providers en tests unitaires + validés à l'import de manifest.)

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat: demo templates for rss/calendar/weather + Plan 2 docs"
```

---

## Self-review (fait à l'écriture)

- **Couverture spec** : §6 providers `rss`→Task 3, `calendar`→Task 4, `weather`→Task 5 (`json`/`system` déjà Plan 1) ; §7 WebView sandbox (file:// + https-only + assets confinés)→Task 1, modèle permission par template→Task 2, secrets Keychain→**hors Plan 2** (lié à l'instance/éditeur = Plan 3, noté ci-dessous) ; §8-9 (UI/erreurs) déjà Plan 1 pour le pipeline, l'écran de permission = Plan 3 ; §12 les 5 providers v1 sont désormais tous présents.
- **Écart de périmètre assumé** : les **secrets `json` dans le Keychain** (§7) sont reportés au Plan 3 (ils se saisissent dans l'éditeur d'instance, qui est construit en Plan 3) — le provider `json` de Plan 1 lit déjà `config` sans secret pour l'instant. Le **path météo « localisation courante »** (CLLocationManager + consent localisation) est reporté ; Plan 2 fait `city`/`lat`+`lon` uniquement. Ces deux reports sont notés au CLAUDE.md par la Task 6.
- **Cohérence des types** : `RenderPipeline.init(templates:shared:permissions:registry:engine:reloader:)` — l'ordre `permissions` après `shared` est appliqué à l'identique dans AppState (Task 2 Step 8) ET dans tous les tests existants (Task 2 Step 5). `SourceSpec.requiresConsent` (Task 2) consommé par le pipeline (Task 2) et testé (Task 6). `DataProvider.fetch(spec:paramValues:) -> Any`, `static var type`, `minimumInterval` respectés par les 3 nouveaux providers. `DataProviderRegistry.standard()` accumule json/system (Plan 1) + rss (Task 3) + calendar (Task 4) + weather (Task 5).
- **Placeholders** : aucun TODO/TBD ; tout le code des steps est complet. Le seul « conditionnel » est le fallback de link WeatherKit (Task 5 Step 5), avec instruction explicite et vérifiable.
- **Fail-soft & permission** : un refus de permission injecte `__denied` et n'affecte pas `stale` (testé Task 2) ; un échec de fetch reste un `failedKey`/`stale` (inchangé). Les deux chemins sont distincts et testés.
