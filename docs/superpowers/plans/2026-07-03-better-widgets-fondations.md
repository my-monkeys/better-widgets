# Better Widgets — Plan 1 : Fondations

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** À la fin de ce plan, un vrai widget système macOS affiche sur le bureau un widget défini en HTML (template `hello-clock`), rendu localement en PNG clair/sombre, rafraîchi automatiquement par une app barre de menus.

**Architecture:** App macOS SwiftUI (login item barre de menus) qui rend les templates HTML en PNG via WKWebView offscreen, écrit les images dans un App Group, et pilote `WidgetCenter.reloadTimelines`. Extension WidgetKit passive (3 kinds S/M/L, configurables par AppIntent) qui affiche le PNG. Voir le spec : `docs/superpowers/specs/2026-07-03-better-widgets-design.md`.

**Tech Stack:** Swift 5.9+, SwiftUI, WidgetKit (AppIntentConfiguration), WKWebView, XCTest, XcodeGen (génération du .xcodeproj), macOS 14+.

## Global Constraints

- **Team ID** : `5C67TFSJ2B` (compte Apple Developer de Maxim, même chaîne qu'OpenSuperWhisper).
- **Bundle IDs** : app `fr.my-monkey.BetterWidgets`, extension `fr.my-monkey.BetterWidgets.WidgetExtension`.
- **App Group** : `5C67TFSJ2B.betterwidgets` (macOS exige le préfixe Team ID).
- **Deployment target** : macOS 14.0 (AppIntentConfiguration + widgets bureau).
- **Sandbox ON pour l'app ET l'extension** dès la v1 (App Store-ready, évite le prompt Group Container de Sequoia). Entitlements app : app group + `com.apple.security.network.client`.
- **Widget kinds** : `bw.small`, `bw.medium`, `bw.large` — ne jamais renommer (les widgets posés par l'utilisateur y sont liés).
- **Tailles de rendu (points)** : small 170×170, medium 364×170, large 364×382. Rendu @2x (PNG = 2× ces valeurs en pixels).
- **Commits** : Conventional Commits, auteur `MaximCosta <maxim@users.noreply.github.com>` (déjà configuré dans le repo), **aucune mention IA**.
- **Le .xcodeproj est généré** : ne jamais l'éditer à la main ; modifier `project.yml` puis `xcodegen generate`. Le `.xcodeproj` est gitignoré.
- Tout le code, les commentaires et identifiants en anglais ; UI de l'app en français.
- Commande de test : `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`.

**Déviation actée vs spec §3** : les **instances** vivent dans le `SharedStore` (App Group), pas dans le `TemplateStore` — l'EntityQuery de l'extension doit pouvoir les lister. Le `TemplateStore` ne gère que les templates.

**Roadmap des plans suivants (hors de ce document)** — Plan 2 : providers weather/calendar/rss + modèle de permissions par template. Plan 3 : UI complète (Mes widgets / Galerie / Éditeur + mode avancé, import/export `.bwidget`). Plan 4 : templates maison, direction artistique, distribution (notarize, DMG, cask).

---

## Structure des fichiers

```
better-widgets/
├── project.yml                          # définition XcodeGen (3 targets)
├── .gitignore
├── BetterWidgets/                       # target app
│   ├── App/BetterWidgetsApp.swift       # @main MenuBarExtra
│   ├── App/AppState.swift               # bootstrap + composition root
│   ├── Core/Models/WidgetSize.swift     # (partagé avec l'extension)
│   ├── Core/Models/TemplateManifest.swift
│   ├── Core/Models/WidgetInstance.swift # (partagé avec l'extension)
│   ├── Core/Models/InstanceState.swift  # (partagé avec l'extension)
│   ├── Core/TemplateStore.swift
│   ├── Core/SharedStore.swift           # (partagé avec l'extension)
│   ├── Core/Render/RenderContext.swift
│   ├── Core/Render/RenderEngine.swift
│   ├── Core/Render/RenderPipeline.swift
│   ├── Core/Data/DataProvider.swift
│   ├── Core/Data/JSONDataProvider.swift
│   ├── Core/Data/SystemDataProvider.swift
│   ├── Core/Data/DataProviderRegistry.swift
│   ├── Core/Scheduler.swift
│   ├── Resources/templates/hello-clock/ # template bundlé
│   │   ├── manifest.json
│   │   └── index.html
│   └── BetterWidgets.entitlements
├── WidgetExtension/
│   ├── WidgetBundle.swift               # 3 kinds
│   ├── WidgetInstanceEntity.swift       # AppEntity + EntityQuery
│   ├── SelectWidgetIntent.swift
│   ├── WidgetRenderView.swift
│   └── WidgetExtension.entitlements
├── Tests/                               # target BetterWidgetsTests
│   ├── ManifestTests.swift
│   ├── SharedStoreTests.swift
│   ├── TemplateStoreTests.swift
│   ├── RenderEngineTests.swift
│   ├── DataProviderTests.swift
│   └── RenderPipelineTests.swift
├── scripts/smoke.sh
└── docs/superpowers/...
```

Fichiers marqués « partagé » : compilés dans les **deux** targets (app + extension) via XcodeGen — pas de framework, YAGNI.

---

### Task 1: Bootstrap du projet XcodeGen (app + extension + tests buildables)

**Files:**
- Create: `project.yml`
- Create: `.gitignore`
- Create: `BetterWidgets/App/BetterWidgetsApp.swift` (stub)
- Create: `BetterWidgets/BetterWidgets.entitlements`
- Create: `WidgetExtension/WidgetBundle.swift` (stub statique)
- Create: `WidgetExtension/WidgetExtension.entitlements`
- Create: `Tests/SmokeTests.swift` (test trivial)

**Interfaces:**
- Consumes: —
- Produces: projet buildable ; les tâches suivantes ajoutent des fichiers dans `BetterWidgets/Core/**` (auto-inclus par XcodeGen, pas de modification de `project.yml` nécessaire sauf mention explicite).

- [ ] **Step 1: Écrire `.gitignore`**

```gitignore
*.xcodeproj
DerivedData/
build/
.DS_Store
*.xcresult
```

- [ ] **Step 2: Écrire `project.yml`**

```yaml
name: BetterWidgets
options:
  bundleIdPrefix: fr.my-monkey
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true
settings:
  base:
    DEVELOPMENT_TEAM: 5C67TFSJ2B
    SWIFT_VERSION: "5.9"
    CODE_SIGN_STYLE: Automatic
targets:
  BetterWidgets:
    type: application
    platform: macOS
    sources:
      - BetterWidgets
    dependencies:
      - target: WidgetExtension
        embed: true
    entitlements:
      path: BetterWidgets/BetterWidgets.entitlements
    info:
      path: BetterWidgets/Info.plist
      properties:
        LSUIElement: true
        CFBundleDisplayName: Better Widgets
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: fr.my-monkey.BetterWidgets
        ENABLE_HARDENED_RUNTIME: true
  WidgetExtension:
    type: app-extension
    platform: macOS
    sources:
      - WidgetExtension
      - BetterWidgets/Core/Models
      - BetterWidgets/Core/SharedStore.swift
    entitlements:
      path: WidgetExtension/WidgetExtension.entitlements
    info:
      path: WidgetExtension/Info.plist
      properties:
        CFBundleDisplayName: Better Widgets
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: fr.my-monkey.BetterWidgets.WidgetExtension
        ENABLE_HARDENED_RUNTIME: true
  BetterWidgetsTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests
      - BetterWidgets/Core
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: fr.my-monkey.BetterWidgetsTests
schemes:
  BetterWidgets:
    build:
      targets:
        BetterWidgets: all
    test:
      targets:
        - BetterWidgetsTests
```

Note : le target de tests compile `BetterWidgets/Core` directement (pas de `@testable import` d'un module app — évite les problèmes de signing d'un test hosted). `SmokeTests` ne teste que la toolchain pour l'instant.

- [ ] **Step 3: Écrire les entitlements**

`BetterWidgets/BetterWidgets.entitlements` :

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>5C67TFSJ2B.betterwidgets</string>
	</array>
</dict>
</plist>
```

`WidgetExtension/WidgetExtension.entitlements` : identique **sans** la clé `network.client` (l'extension ne fait aucun réseau).

- [ ] **Step 4: Écrire les stubs Swift**

`BetterWidgets/App/BetterWidgetsApp.swift` :

```swift
import SwiftUI

@main
struct BetterWidgetsApp: App {
    var body: some Scene {
        MenuBarExtra("Better Widgets", systemImage: "square.grid.2x2") {
            Text("Better Widgets")
            Divider()
            Button("Quitter") { NSApp.terminate(nil) }
        }
    }
}
```

`WidgetExtension/WidgetBundle.swift` (stub — remplacé en Task 9) :

```swift
import WidgetKit
import SwiftUI

@main
struct BetterWidgetsWidgets: WidgetBundle {
    var body: some Widget {
        StubWidget()
    }
}

struct StubWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "bw.stub", provider: StubProvider()) { _ in
            Text("Better Widgets")
                .containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName("Better Widgets (stub)")
    }
}

struct StubProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry { SimpleEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [SimpleEntry(date: .now)], policy: .never))
    }
}

struct SimpleEntry: TimelineEntry { let date: Date }
```

`Tests/SmokeTests.swift` :

```swift
import XCTest

final class SmokeTests: XCTestCase {
    func testToolchainWorks() {
        XCTAssertEqual(1 + 1, 2)
    }
}
```

- [ ] **Step 5: Générer et builder**

Run: `cd /Users/maxim/Documents/my-monkey/better-widgets && xcodegen generate && xcodebuild build -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: `BUILD SUCCEEDED` (warnings de signing OK tant que le build passe).

Run: `xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: `TEST SUCCEEDED` (1 test).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "chore: bootstrap XcodeGen project (app + widget extension + tests)"
```

---

### Task 2: Spike RenderEngine — HTML → PNG offscreen (LE risque n°1 du projet)

**But** : prouver que `WKWebView` offscreen rend un HTML en PNG @2x fiable, en clair ET en sombre. Si ce spike échoue, on s'arrête et on révise le design — ne pas continuer les tâches suivantes.

**Files:**
- Create: `BetterWidgets/Core/Models/WidgetSize.swift`
- Create: `BetterWidgets/Core/Render/RenderContext.swift`
- Create: `BetterWidgets/Core/Render/RenderEngine.swift`
- Test: `Tests/RenderEngineTests.swift`

**Interfaces:**
- Consumes: —
- Produces:
  - `enum WidgetSize: String, Codable, CaseIterable { case small, medium, large }` avec `var pointSize: CGSize` et `var kind: String` (ex. `"bw.small"`)
  - `struct RenderContext { let params: [String: String]; let data: [String: Any]; let size: WidgetSize; let theme: Theme; let stale: Bool }` avec `enum Theme: String { case light, dark }` et `func bwJSON() throws -> String`
  - `@MainActor final class RenderEngine { func render(html: String, baseURL: URL?, context: RenderContext) async throws -> Data }` — retourne un PNG de `pointSize × 2` pixels. `enum RenderError: Error { case timeout, snapshotFailed }`

- [ ] **Step 1: Écrire `WidgetSize.swift`**

```swift
import Foundation

enum WidgetSize: String, Codable, CaseIterable {
    case small, medium, large

    var pointSize: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        }
    }

    var kind: String { "bw.\(rawValue)" }
}
```

- [ ] **Step 2: Écrire `RenderContext.swift`**

```swift
import Foundation

enum Theme: String, Codable {
    case light, dark
}

struct RenderContext {
    let params: [String: String]
    let data: [String: Any]
    let size: WidgetSize
    let theme: Theme
    let stale: Bool

    /// JSON injected as `window.BW` before the template loads.
    func bwJSON() throws -> String {
        let payload: [String: Any] = [
            "params": params,
            "data": data,
            "size": [
                "w": Int(size.pointSize.width),
                "h": Int(size.pointSize.height),
                "family": size.rawValue,
            ],
            "theme": theme.rawValue,
            "stale": stale,
        ]
        let json = try JSONSerialization.data(withJSONObject: payload)
        return String(data: json, encoding: .utf8)!
    }
}
```

- [ ] **Step 3: Écrire le test spike (échoue : RenderEngine n'existe pas)**

`Tests/RenderEngineTests.swift` :

```swift
import XCTest
// Pas d'import de module : les sources Core sont compilées directement dans le target de test.

final class RenderEngineTests: XCTestCase {
    // HTML : fond rouge en clair, bleu en sombre, affiche BW.params.label.
    private let html = """
    <!doctype html><html><head><meta charset="utf-8"><style>
      html, body { margin: 0; width: 100%; height: 100%; }
      body { background: #ff0000; }
      @media (prefers-color-scheme: dark) { body { background: #0000ff; } }
    </style></head><body><script>
      document.body.textContent = window.BW.params.label;
    </script></body></html>
    """

    @MainActor
    func testRendersLightPNGAtExactSize() async throws {
        let engine = RenderEngine()
        let ctx = RenderContext(params: ["label": "hello"], data: [:], size: .small, theme: .light, stale: false)
        let png = try await engine.render(html: html, baseURL: nil, context: ctx)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(rep.pixelsWide, 340)  // 170pt @2x
        XCTAssertEqual(rep.pixelsHigh, 340)
        let center = try XCTUnwrap(rep.colorAt(x: 170, y: 170)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(center.redComponent, 0.8, "light theme must render the red background")
        XCTAssertLessThan(center.blueComponent, 0.2)
    }

    @MainActor
    func testRendersDarkVariant() async throws {
        let engine = RenderEngine()
        let ctx = RenderContext(params: ["label": "hello"], data: [:], size: .small, theme: .dark, stale: false)
        let png = try await engine.render(html: html, baseURL: nil, context: ctx)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: png))
        let center = try XCTUnwrap(rep.colorAt(x: 170, y: 170)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(center.blueComponent, 0.8, "dark theme must render the blue background")
    }

    @MainActor
    func testMediumSizeDimensions() async throws {
        let engine = RenderEngine()
        let ctx = RenderContext(params: [:], data: [:], size: .medium, theme: .light, stale: false)
        let png = try await engine.render(html: html, baseURL: nil, context: ctx)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(rep.pixelsWide, 728)
        XCTAssertEqual(rep.pixelsHigh, 340)
    }
}
```

(Si `@testable import` pose problème : les sources Core sont compilées dans le target de test, aucun import de module n'est nécessaire — supprimer la ligne.)

- [ ] **Step 4: Vérifier que le test échoue**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: FAIL — `cannot find 'RenderEngine' in scope`.

- [ ] **Step 5: Implémenter `RenderEngine.swift`**

Points clés : la webview vit hors écran ; `appearance` (NSAppearance) force `prefers-color-scheme` ; `pageZoom = 2` + `snapshotWidth = 2 × width(pt)` produisent le @2x ; on attend `BW.ready()` si le HTML l'appelle, sinon 300 ms après `didFinish` ; timeout dur 5 s.

```swift
import WebKit

enum RenderError: Error {
    case timeout
    case snapshotFailed
}

@MainActor
final class RenderEngine: NSObject {
    private let readyGraceDelay: TimeInterval = 0.3
    private let hardTimeout: TimeInterval = 5.0

    func render(html: String, baseURL: URL?, context: RenderContext) async throws -> Data {
        let size = context.size.pointSize
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()

        let ready = ReadySignal()
        controller.add(ready, name: "bwReady")

        let bwScript = """
        window.BW = \(try context.bwJSON());
        window.BW.ready = function () { window.webkit.messageHandlers.bwReady.postMessage(true); };
        """
        controller.addUserScript(WKUserScript(source: bwScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController = controller

        let webView = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: config)
        webView.appearance = NSAppearance(named: context.theme == .dark ? .darkAqua : .aqua)
        webView.pageZoom = 2
        webView.setValue(false, forKey: "drawsBackground") // transparent by default; template paints its own bg

        let navDelegate = NavDelegate()
        webView.navigationDelegate = navDelegate

        webView.loadHTMLString(html, baseURL: baseURL)

        // Wait: BW.ready() wins immediately; otherwise didFinish + grace delay; hard timeout 5 s.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                await ready.wait(orNavDone: navDelegate, grace: self.readyGraceDelay)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(self.hardTimeout))
                throw RenderError.timeout
            }
            try await group.next()
            group.cancelAll()
        }

        let snapConfig = WKSnapshotConfiguration()
        snapConfig.rect = CGRect(origin: .zero, size: size)
        snapConfig.snapshotWidth = NSNumber(value: Double(size.width) * 2)
        snapConfig.afterScreenUpdates = true

        let image: NSImage = try await withCheckedThrowingContinuation { cont in
            webView.takeSnapshot(with: snapConfig) { image, error in
                if let image { cont.resume(returning: image) } else {
                    cont.resume(throwing: error ?? RenderError.snapshotFailed)
                }
            }
        }

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw RenderError.snapshotFailed
        }
        controller.removeScriptMessageHandler(forName: "bwReady")
        return png
    }
}

/// Resolves when BW.ready() is posted, or navDone + grace delay elapses.
@MainActor
private final class ReadySignal: NSObject, WKScriptMessageHandler {
    private var readyContinuation: CheckedContinuation<Void, Never>?
    private var isReady = false

    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        Task { @MainActor in
            self.isReady = true
            self.readyContinuation?.resume()
            self.readyContinuation = nil
        }
    }

    func wait(orNavDone nav: NavDelegate, grace: TimeInterval) async {
        if isReady { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            readyContinuation = cont
            Task { @MainActor in
                await nav.waitForFinish()
                try? await Task.sleep(for: .seconds(grace))
                self.readyContinuation?.resume()
                self.readyContinuation = nil
            }
        }
    }
}

@MainActor
private final class NavDelegate: NSObject, WKNavigationDelegate {
    private var finished = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.finished = true
            self.continuations.forEach { $0.resume() }
            self.continuations.removeAll()
        }
    }

    func waitForFinish() async {
        if finished { return }
        await withCheckedContinuation { continuations.append($0) }
    }
}
```

⚠️ Si `setValue(false, forKey: "drawsBackground")` casse en sandbox/Xcode 27 (KVC privé), le retirer et exiger que chaque template peigne son propre fond (le stub et hello-clock le font déjà). Noter le résultat du spike dans le commit.

- [ ] **Step 6: Vérifier que les 3 tests passent**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: PASS (3 tests RenderEngine + smoke). Si `takeSnapshot` retourne une image aux mauvaises dimensions ou vide → STOP, investiguer (`pageZoom`/`snapshotWidth`), et si insoluble remonter avant de continuer le plan.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: render engine spike — offscreen WKWebView to PNG, light/dark, @2x"
```

---

### Task 3: Modèles — TemplateManifest + WidgetInstance + InstanceState (validation stricte)

**Files:**
- Create: `BetterWidgets/Core/Models/TemplateManifest.swift`
- Create: `BetterWidgets/Core/Models/WidgetInstance.swift`
- Create: `BetterWidgets/Core/Models/InstanceState.swift`
- Test: `Tests/ManifestTests.swift`

**Interfaces:**
- Consumes: `WidgetSize` (Task 2)
- Produces:
  - `struct TemplateManifest: Codable, Equatable` — champs : `id: String`, `name: String`, `version: String`, `sizes: [WidgetSize]`, `refresh: Int` (secondes), `params: [ParamSpec]`, `sources: [SourceSpec]`, `links: [LinkSpec]?` ; `static func validated(from data: Data) throws -> TemplateManifest` ; `enum ManifestError: Error, Equatable { case invalidJSON(String), emptySizes, refreshTooSmall, duplicateParamKey(String), duplicateSourceKey(String), unknownSourceType(String) }`
  - `struct ParamSpec: Codable, Equatable { let key: String; let type: ParamType; let label: String; let default: String? }` avec `enum ParamType: String, Codable { case string, color, number, url }` (le champ JSON s'appelle `default` → CodingKeys car mot réservé)
  - `struct SourceSpec: Codable, Equatable { let key: String; let type: String; let config: [String: String]? }`
  - `struct LinkSpec: Codable, Equatable { let rect: String; let url: String }` (v1 : `rect` vaut toujours `"full"`)
  - `struct WidgetInstance: Codable, Equatable, Identifiable { let id: UUID; var name: String; let templateId: String; var size: WidgetSize; var paramValues: [String: String] }`
  - `struct InstanceState: Codable, Equatable { var lastRenderAt: Date?; var lastFetchAt: Date?; var stale: Bool; var lastError: String? }`
- Types de sources connus en v1 : `["json", "system"]` (constante `SourceSpec.knownTypes`, étendue au Plan 2).

- [ ] **Step 1: Écrire les tests (échouent)**

`Tests/ManifestTests.swift` :

```swift
import XCTest

final class ManifestTests: XCTestCase {
    private func manifestJSON(refresh: Int = 900, sourceType: String = "system") -> Data {
        """
        {
          "id": "weather-minimal", "name": "Météo minimale", "version": "1.0.0",
          "sizes": ["small", "medium"], "refresh": \(refresh),
          "params": [{ "key": "city", "type": "string", "label": "Ville", "default": "Montpellier" }],
          "sources": [{ "key": "sys", "type": "\(sourceType)" }]
        }
        """.data(using: .utf8)!
    }

    func testValidManifestParses() throws {
        let m = try TemplateManifest.validated(from: manifestJSON())
        XCTAssertEqual(m.id, "weather-minimal")
        XCTAssertEqual(m.sizes, [.small, .medium])
        XCTAssertEqual(m.refresh, 900)
        XCTAssertEqual(m.params.first?.default, "Montpellier")
        XCTAssertNil(m.links)
    }

    func testRefreshUnder30sRejected() {
        XCTAssertThrowsError(try TemplateManifest.validated(from: manifestJSON(refresh: 5))) {
            XCTAssertEqual($0 as? ManifestError, .refreshTooSmall)
        }
    }

    func testUnknownSourceTypeRejected() {
        XCTAssertThrowsError(try TemplateManifest.validated(from: manifestJSON(sourceType: "crypto"))) {
            XCTAssertEqual($0 as? ManifestError, .unknownSourceType("crypto"))
        }
    }

    func testDuplicateParamKeyRejected() {
        let json = """
        { "id": "x", "name": "x", "version": "1", "sizes": ["small"], "refresh": 60,
          "params": [{"key":"a","type":"string","label":"A"},{"key":"a","type":"string","label":"A2"}],
          "sources": [] }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try TemplateManifest.validated(from: json)) {
            XCTAssertEqual($0 as? ManifestError, .duplicateParamKey("a"))
        }
    }

    func testGarbageJSONGivesReadableError() {
        XCTAssertThrowsError(try TemplateManifest.validated(from: Data("not json".utf8)))
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: FAIL — `cannot find 'TemplateManifest' in scope`.

- [ ] **Step 3: Implémenter les modèles**

`BetterWidgets/Core/Models/TemplateManifest.swift` :

```swift
import Foundation

enum ManifestError: Error, Equatable {
    case invalidJSON(String)
    case emptySizes
    case refreshTooSmall
    case duplicateParamKey(String)
    case duplicateSourceKey(String)
    case unknownSourceType(String)
}

enum ParamType: String, Codable, Equatable {
    case string, color, number, url
}

struct ParamSpec: Codable, Equatable {
    let key: String
    let type: ParamType
    let label: String
    let `default`: String?
}

struct SourceSpec: Codable, Equatable {
    static let knownTypes: Set<String> = ["json", "system"]
    let key: String
    let type: String
    let config: [String: String]?
}

struct LinkSpec: Codable, Equatable {
    let rect: String
    let url: String
}

struct TemplateManifest: Codable, Equatable {
    static let minimumRefresh = 30

    let id: String
    let name: String
    let version: String
    let sizes: [WidgetSize]
    let refresh: Int
    let params: [ParamSpec]
    let sources: [SourceSpec]
    let links: [LinkSpec]?

    static func validated(from data: Data) throws -> TemplateManifest {
        let manifest: TemplateManifest
        do {
            manifest = try JSONDecoder().decode(TemplateManifest.self, from: data)
        } catch {
            throw ManifestError.invalidJSON(String(describing: error))
        }
        guard !manifest.sizes.isEmpty else { throw ManifestError.emptySizes }
        guard manifest.refresh >= minimumRefresh else { throw ManifestError.refreshTooSmall }
        var paramKeys = Set<String>()
        for p in manifest.params where !paramKeys.insert(p.key).inserted {
            throw ManifestError.duplicateParamKey(p.key)
        }
        var sourceKeys = Set<String>()
        for s in manifest.sources {
            guard sourceKeys.insert(s.key).inserted else { throw ManifestError.duplicateSourceKey(s.key) }
            guard SourceSpec.knownTypes.contains(s.type) else { throw ManifestError.unknownSourceType(s.type) }
        }
        return manifest
    }
}
```

`BetterWidgets/Core/Models/WidgetInstance.swift` :

```swift
import Foundation

struct WidgetInstance: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    let templateId: String
    var size: WidgetSize
    var paramValues: [String: String]
}
```

`BetterWidgets/Core/Models/InstanceState.swift` :

```swift
import Foundation

struct InstanceState: Codable, Equatable {
    var lastRenderAt: Date?
    var lastFetchAt: Date?
    var stale: Bool = false
    var lastError: String?
}
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: template manifest, widget instance and state models with strict validation"
```

---

### Task 4: SharedStore — contrat App Group (instances, renders, state)

**Files:**
- Create: `BetterWidgets/Core/SharedStore.swift`
- Test: `Tests/SharedStoreTests.swift`

**Interfaces:**
- Consumes: `WidgetInstance`, `InstanceState`, `Theme`, `WidgetSize` (Tasks 2-3)
- Produces:
  - `final class SharedStore` — `init(baseURL: URL)` (tests) + `static func appGroup() -> SharedStore` (résout le container `5C67TFSJ2B.betterwidgets`, crée les dossiers)
  - Instances : `func loadInstances() -> [WidgetInstance]`, `func saveInstances(_ instances: [WidgetInstance]) throws`
  - Renders : `func writeRender(_ png: Data, instanceId: UUID, theme: Theme) throws`, `func renderURL(instanceId: UUID, theme: Theme) -> URL`
  - State : `func loadState(instanceId: UUID) -> InstanceState`, `func saveState(_ state: InstanceState, instanceId: UUID) throws`
- Layout disque : `instances.json`, `renders/<uuid>-light.png`, `renders/<uuid>-dark.png`, `state/<uuid>.json`.

- [ ] **Step 1: Écrire les tests (échouent)**

`Tests/SharedStoreTests.swift` :

```swift
import XCTest

final class SharedStoreTests: XCTestCase {
    private var store: SharedStore!
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = try SharedStore(baseURL: tmp)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testInstancesRoundTrip() throws {
        let a = WidgetInstance(id: UUID(), name: "Horloge", templateId: "hello-clock",
                               size: .small, paramValues: ["accent": "#e8590c"])
        try store.saveInstances([a])
        XCTAssertEqual(store.loadInstances(), [a])
    }

    func testLoadInstancesEmptyWhenMissing() {
        XCTAssertEqual(store.loadInstances(), [])
    }

    func testRenderWriteAndURL() throws {
        let id = UUID()
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        try store.writeRender(png, instanceId: id, theme: .dark)
        let url = store.renderURL(instanceId: id, theme: .dark)
        XCTAssertEqual(try Data(contentsOf: url), png)
        XCTAssertTrue(url.lastPathComponent.hasSuffix("-dark.png"))
    }

    func testStateRoundTripAndDefault() throws {
        let id = UUID()
        XCTAssertEqual(store.loadState(instanceId: id), InstanceState())
        var s = InstanceState()
        s.stale = true
        s.lastError = "boom"
        try store.saveState(s, instanceId: id)
        XCTAssertEqual(store.loadState(instanceId: id), s)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -quiet`
Expected: FAIL — `cannot find 'SharedStore' in scope`.

- [ ] **Step 3: Implémenter `SharedStore.swift`**

```swift
import Foundation

/// Contract between the app (writer) and the widget extension (reader).
/// Layout: instances.json / renders/<uuid>-<theme>.png / state/<uuid>.json
final class SharedStore {
    static let appGroupID = "5C67TFSJ2B.betterwidgets"

    private let baseURL: URL
    private var rendersURL: URL { baseURL.appendingPathComponent("renders") }
    private var stateURL: URL { baseURL.appendingPathComponent("state") }
    private var instancesURL: URL { baseURL.appendingPathComponent("instances.json") }

    init(baseURL: URL) throws {
        self.baseURL = baseURL
        for dir in [baseURL, rendersURL, stateURL] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static func appGroup() -> SharedStore {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            fatalError("App Group \(appGroupID) unavailable — check entitlements")
        }
        return try! SharedStore(baseURL: container.appendingPathComponent("Store"))
    }

    // MARK: Instances

    func loadInstances() -> [WidgetInstance] {
        guard let data = try? Data(contentsOf: instancesURL) else { return [] }
        return (try? JSONDecoder().decode([WidgetInstance].self, from: data)) ?? []
    }

    func saveInstances(_ instances: [WidgetInstance]) throws {
        try JSONEncoder().encode(instances).write(to: instancesURL, options: .atomic)
    }

    // MARK: Renders

    func renderURL(instanceId: UUID, theme: Theme) -> URL {
        rendersURL.appendingPathComponent("\(instanceId.uuidString)-\(theme.rawValue).png")
    }

    func writeRender(_ png: Data, instanceId: UUID, theme: Theme) throws {
        try png.write(to: renderURL(instanceId: instanceId, theme: theme), options: .atomic)
    }

    // MARK: State

    func loadState(instanceId: UUID) -> InstanceState {
        let url = stateURL.appendingPathComponent("\(instanceId.uuidString).json")
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(InstanceState.self, from: data) else {
            return InstanceState()
        }
        return state
    }

    func saveState(_ state: InstanceState, instanceId: UUID) throws {
        let url = stateURL.appendingPathComponent("\(instanceId.uuidString).json")
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `xcodegen generate && xcodebuild test ... -quiet`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: shared app-group store for instances, renders and state"
```

---

### Task 5: TemplateStore — templates sur disque + bootstrap des templates bundlés

**Files:**
- Create: `BetterWidgets/Core/TemplateStore.swift`
- Create: `BetterWidgets/Resources/templates/hello-clock/manifest.json`
- Create: `BetterWidgets/Resources/templates/hello-clock/index.html`
- Test: `Tests/TemplateStoreTests.swift`

**Interfaces:**
- Consumes: `TemplateManifest` (Task 3)
- Produces:
  - `final class TemplateStore` — `init(rootURL: URL)` ; `static func applicationSupport() -> TemplateStore` (`~/Library/.../Application Support/BetterWidgets/templates` dans le container sandbox)
  - `func list() -> [TemplateManifest]` (ignore les dossiers au manifest invalide)
  - `func manifest(id: String) throws -> TemplateManifest`
  - `func html(id: String) throws -> String` + `func templateDirectory(id: String) -> URL` (baseURL de rendu pour les assets)
  - `func installBundledTemplates(from bundleDir: URL) throws` — copie chaque template bundlé s'il est absent (n'écrase jamais une version locale)
  - `enum TemplateStoreError: Error { case notFound(String) }`

**Template `hello-clock`** — `manifest.json` :

```json
{
  "id": "hello-clock",
  "name": "Horloge",
  "version": "1.0.0",
  "sizes": ["small", "medium"],
  "refresh": 60,
  "params": [
    { "key": "accent", "type": "color", "label": "Couleur d'accent", "default": "#e8590c" }
  ],
  "sources": [{ "key": "sys", "type": "system" }]
}
```

`index.html` :

```html
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<style>
  html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; }
  body {
    display: flex; flex-direction: column; justify-content: center; align-items: center;
    background: #f5f2ec; color: #1a1a1a;
    font-family: -apple-system, "SF Pro Display", sans-serif;
  }
  @media (prefers-color-scheme: dark) { body { background: #16130e; color: #f0ece4; } }
  .time { font-size: 44px; font-weight: 700; letter-spacing: -0.03em; }
  .date { font-size: 13px; margin-top: 4px; opacity: 0.6; text-transform: capitalize; }
  .dot { width: 6px; height: 6px; border-radius: 50%; margin-top: 10px; }
</style>
</head>
<body>
<div class="time" id="time"></div>
<div class="date" id="date"></div>
<div class="dot" id="dot"></div>
<script>
  const now = new Date(window.BW.data.sys.datetime);
  document.getElementById("time").textContent =
    now.toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" });
  document.getElementById("date").textContent =
    now.toLocaleDateString("fr-FR", { weekday: "long", day: "numeric", month: "long" });
  document.getElementById("dot").style.background = window.BW.params.accent;
</script>
</body>
</html>
```

- [ ] **Step 1: Écrire les tests (échouent)**

`Tests/TemplateStoreTests.swift` :

```swift
import XCTest

final class TemplateStoreTests: XCTestCase {
    private var root: URL!
    private var store: TemplateStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = TemplateStore(rootURL: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeTemplate(id: String, refresh: Int = 60) throws {
        let dir = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifest = """
        { "id": "\(id)", "name": "T", "version": "1.0.0", "sizes": ["small"],
          "refresh": \(refresh), "params": [], "sources": [] }
        """
        try manifest.write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "<html></html>".write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }

    func testListReturnsValidTemplatesOnly() throws {
        try writeTemplate(id: "good")
        try writeTemplate(id: "bad", refresh: 1) // refresh < 30 → manifest invalide
        let ids = store.list().map(\.id)
        XCTAssertEqual(ids, ["good"])
    }

    func testHtmlAndManifestLoad() throws {
        try writeTemplate(id: "good")
        XCTAssertEqual(try store.manifest(id: "good").id, "good")
        XCTAssertEqual(try store.html(id: "good"), "<html></html>")
    }

    func testMissingTemplateThrows() {
        XCTAssertThrowsError(try store.manifest(id: "nope"))
    }

    func testInstallBundledDoesNotOverwrite() throws {
        let bundleDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: bundleDir) }
        let src = bundleDir.appendingPathComponent("tpl")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try #"{ "id": "tpl", "name": "T", "version": "1.0.0", "sizes": ["small"], "refresh": 60, "params": [], "sources": [] }"#
            .write(to: src.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "v1".write(to: src.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

        try store.installBundledTemplates(from: bundleDir)
        XCTAssertEqual(try store.html(id: "tpl"), "v1")

        // Local edit then reinstall: must not overwrite.
        try "edited".write(to: root.appendingPathComponent("tpl/index.html"), atomically: true, encoding: .utf8)
        try store.installBundledTemplates(from: bundleDir)
        XCTAssertEqual(try store.html(id: "tpl"), "edited")
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -quiet`
Expected: FAIL — `cannot find 'TemplateStore' in scope`.

- [ ] **Step 3: Implémenter `TemplateStore.swift`**

```swift
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
```

- [ ] **Step 4: Vérifier que les tests passent, et que les ressources sont bundlées**

Run: `xcodegen generate && xcodebuild test ... -quiet`
Expected: PASS.

Vérifier que `BetterWidgets/Resources/templates/**` part bien dans le bundle app : XcodeGen inclut `BetterWidgets/Resources` comme resources automatiquement (dossier sous `sources:`). Contrôle : `xcodebuild build ... -quiet && ls ~/Library/Developer/Xcode/DerivedData/BetterWidgets-*/Build/Products/Debug/Better\ Widgets.app/Contents/Resources/templates/hello-clock/` doit lister `manifest.json index.html`. Si absent : ajouter à `project.yml` sous le target app :

```yaml
    sources:
      - BetterWidgets
      - path: BetterWidgets/Resources/templates
        type: folder
        buildPhase: resources
```

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: template store with bundled template bootstrap + hello-clock template"
```

---

### Task 6: DataProviders — protocol, json, system, registry

**Files:**
- Create: `BetterWidgets/Core/Data/DataProvider.swift`
- Create: `BetterWidgets/Core/Data/JSONDataProvider.swift`
- Create: `BetterWidgets/Core/Data/SystemDataProvider.swift`
- Create: `BetterWidgets/Core/Data/DataProviderRegistry.swift`
- Test: `Tests/DataProviderTests.swift`

**Interfaces:**
- Consumes: `SourceSpec` (Task 3)
- Produces:
  - `protocol DataProvider { static var type: String { get }; var minimumInterval: TimeInterval { get }; func fetch(spec: SourceSpec, paramValues: [String: String]) async throws -> Any }` — le retour doit être JSON-serializable
  - `struct FetchResult { let data: [String: Any]; let failedKeys: [String] }` (`stale = !failedKeys.isEmpty` en aval)
  - `final class DataProviderRegistry { init(providers: [any DataProvider]); static func standard(urlSession: URLSession = .shared) -> DataProviderRegistry; func fetchAll(sources: [SourceSpec], paramValues: [String: String]) async -> FetchResult }`
  - `func substituteParams(_ template: String, params: [String: String]) -> String` — remplace `{{key}}` par la valeur
  - `SystemDataProvider` produit sous la clé de la source : `{ datetime (ISO8601), uptime (s), cpuLoad1m, memTotal, memFree, diskTotal, diskFree, battery: { level, charging }? }`
  - `enum DataProviderError: Error { case unknownType(String), missingConfig(String), badURL(String), httpError(Int) }`

- [ ] **Step 1: Écrire les tests (échouent)**

`Tests/DataProviderTests.swift` :

```swift
import XCTest

final class DataProviderTests: XCTestCase {

    func testSubstituteParams() {
        XCTAssertEqual(substituteParams("https://api.x/{{city}}/now?u={{unit}}",
                                        params: ["city": "montpellier", "unit": "c"]),
                       "https://api.x/montpellier/now?u=c")
        XCTAssertEqual(substituteParams("no params", params: [:]), "no params")
    }

    func testSystemProviderShape() async throws {
        let provider = SystemDataProvider()
        let spec = SourceSpec(key: "sys", type: "system", config: nil)
        let result = try await provider.fetch(spec: spec, paramValues: [:])
        let dict = try XCTUnwrap(result as? [String: Any])
        XCTAssertNotNil(dict["datetime"] as? String)
        XCTAssertNotNil(dict["uptime"] as? Double)
        XCTAssertNotNil(dict["memTotal"] as? Double)
        XCTAssertNotNil(dict["diskFree"] as? Double)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(dict), "must be JSON-serializable")
    }

    func testJSONProviderMissingURLConfigThrows() async {
        let provider = JSONDataProvider(urlSession: .shared)
        let spec = SourceSpec(key: "api", type: "json", config: nil)
        do {
            _ = try await provider.fetch(spec: spec, paramValues: [:])
            XCTFail("expected missingConfig")
        } catch { /* expected */ }
    }

    func testRegistryFetchAllCollectsFailuresAsFailedKeys() async {
        struct BoomProvider: DataProvider {
            static let type = "boom"
            let minimumInterval: TimeInterval = 60
            func fetch(spec: SourceSpec, paramValues: [String: String]) async throws -> Any {
                throw DataProviderError.missingConfig("boom")
            }
        }
        let registry = DataProviderRegistry(providers: [SystemDataProvider(), BoomProvider()])
        let sources = [SourceSpec(key: "sys", type: "system", config: nil),
                       SourceSpec(key: "b", type: "boom", config: nil)]
        let result = await registry.fetchAll(sources: sources, paramValues: [:])
        XCTAssertNotNil(result.data["sys"])
        XCTAssertNil(result.data["b"])
        XCTAssertEqual(result.failedKeys, ["b"])
    }

    func testRegistryUnknownTypeIsFailedKey() async {
        let registry = DataProviderRegistry(providers: [SystemDataProvider()])
        let result = await registry.fetchAll(
            sources: [SourceSpec(key: "x", type: "nope", config: nil)], paramValues: [:])
        XCTAssertEqual(result.failedKeys, ["x"])
    }
}
```

Note : pour permettre `BoomProvider` dans le test, `SourceSpec.knownTypes` ne doit être vérifié **qu'au parsing du manifest** (Task 3), pas dans le registry — le registry route sur les providers dont il dispose.

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -quiet`
Expected: FAIL — `cannot find 'substituteParams' in scope`.

- [ ] **Step 3: Implémenter**

`BetterWidgets/Core/Data/DataProvider.swift` :

```swift
import Foundation

enum DataProviderError: Error {
    case unknownType(String)
    case missingConfig(String)
    case badURL(String)
    case httpError(Int)
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
```

`BetterWidgets/Core/Data/JSONDataProvider.swift` :

```swift
import Foundation

struct JSONDataProvider: DataProvider {
    static let type = "json"
    let minimumInterval: TimeInterval = 60
    let urlSession: URLSession

    func fetch(spec: SourceSpec, paramValues: [String: String]) async throws -> Any {
        guard let rawURL = spec.config?["url"] else {
            throw DataProviderError.missingConfig("json source '\(spec.key)' requires config.url")
        }
        let urlString = substituteParams(rawURL, params: paramValues)
        guard let url = URL(string: urlString), url.scheme == "https" else {
            throw DataProviderError.badURL(urlString)
        }
        var request = URLRequest(url: url)
        for (header, value) in spec.config ?? [:] where header.hasPrefix("header.") {
            request.setValue(substituteParams(value, params: paramValues),
                             forHTTPHeaderField: String(header.dropFirst("header.".count)))
        }
        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DataProviderError.httpError(http.statusCode)
        }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}
```

`BetterWidgets/Core/Data/SystemDataProvider.swift` :

```swift
import Foundation
import IOKit.ps

struct SystemDataProvider: DataProvider {
    static let type = "system"
    let minimumInterval: TimeInterval = 30

    func fetch(spec: SourceSpec, paramValues: [String: String]) async throws -> Any {
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)

        var memStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        _ = withUnsafeMutablePointer(to: &memStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        let pageSize = Double(vm_kernel_page_size)
        let memFree = Double(memStats.free_count + memStats.inactive_count) * pageSize

        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                        .volumeAvailableCapacityForImportantUsageKey])

        var result: [String: Any] = [
            "datetime": ISO8601DateFormatter().string(from: Date()),
            "uptime": ProcessInfo.processInfo.systemUptime,
            "cpuLoad1m": loads[0],
            "memTotal": Double(ProcessInfo.processInfo.physicalMemory),
            "memFree": memFree,
            "diskTotal": Double(values?.volumeTotalCapacity ?? 0),
            "diskFree": Double(values?.volumeAvailableCapacityForImportantUsage ?? 0),
        ]
        if let battery = batteryInfo() {
            result["battery"] = battery
        }
        return result
    }

    /// nil on desktops without battery.
    private func batteryInfo() -> [String: Any]? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let info = IOPSGetPowerSourceDescription(snapshot, source)?
                  .takeUnretainedValue() as? [String: Any],
              let capacity = info[kIOPSCurrentCapacityKey] as? Int,
              let max = info[kIOPSMaxCapacityKey] as? Int, max > 0 else { return nil }
        let charging = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        return ["level": Double(capacity) / Double(max), "charging": charging]
    }
}
```

`BetterWidgets/Core/Data/DataProviderRegistry.swift` :

```swift
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
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `xcodegen generate && xcodebuild test ... -quiet`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: data providers (json, system) with fail-soft registry"
```

---

### Task 7: RenderPipeline — orchestration fetch → render → store → reload

**Files:**
- Create: `BetterWidgets/Core/Render/RenderPipeline.swift`
- Test: `Tests/RenderPipelineTests.swift`

**Interfaces:**
- Consumes: `TemplateStore`, `SharedStore`, `DataProviderRegistry`, `RenderEngine`, modèles (Tasks 2-6)
- Produces:
  - `protocol Rendering { @MainActor func render(html: String, baseURL: URL?, context: RenderContext) async throws -> Data }` — `RenderEngine` s'y conforme (ajouter `extension RenderEngine: Rendering {}`)
  - `protocol WidgetReloading { func reload(kind: String) }` + `struct WidgetCenterReloader: WidgetReloading` (appelle `WidgetCenter.shared.reloadTimelines(ofKind:)` — vit dans ce fichier, gated `import WidgetKit`)
  - `final class RenderPipeline { init(templates: TemplateStore, shared: SharedStore, registry: DataProviderRegistry, engine: any Rendering, reloader: any WidgetReloading); func refresh(_ instance: WidgetInstance) async }` — ne throw jamais : toute erreur finit dans `InstanceState.lastError`.
- Comportement : fetch (échecs → `stale`) → merge params (defaults du manifest ⊕ `paramValues`) → render light + dark → `writeRender` ×2 → `saveState` (lastRenderAt/lastFetchAt/stale/lastError=nil) → `reload(kind)`. En cas d'erreur de rendu : conserver les PNG précédents, `saveState` avec `lastError`, pas de reload.

- [ ] **Step 1: Écrire les tests (échouent)**

`Tests/RenderPipelineTests.swift` :

```swift
import XCTest

final class RenderPipelineTests: XCTestCase {
    private var tmp: URL!
    private var shared: SharedStore!
    private var templates: TemplateStore!

    final class FakeEngine: Rendering {
        var calls: [(theme: Theme, stale: Bool)] = []
        var shouldThrow = false
        func render(html: String, baseURL: URL?, context: RenderContext) async throws -> Data {
            if shouldThrow { throw RenderError.timeout }
            calls.append((context.theme, context.stale))
            return Data("png-\(context.theme.rawValue)".utf8)
        }
    }

    final class FakeReloader: WidgetReloading {
        var kinds: [String] = []
        func reload(kind: String) { kinds.append(kind) }
    }

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        shared = try SharedStore(baseURL: tmp.appendingPathComponent("shared"))
        let tplRoot = tmp.appendingPathComponent("templates")
        try FileManager.default.createDirectory(at: tplRoot.appendingPathComponent("clock"),
                                                withIntermediateDirectories: true)
        try #"{ "id": "clock", "name": "C", "version": "1.0.0", "sizes": ["small"], "refresh": 60, "params": [{"key":"accent","type":"color","label":"A","default":"#fff"}], "sources": [{"key":"sys","type":"system"}] }"#
            .write(to: tplRoot.appendingPathComponent("clock/manifest.json"), atomically: true, encoding: .utf8)
        try "<html></html>".write(to: tplRoot.appendingPathComponent("clock/index.html"),
                                  atomically: true, encoding: .utf8)
        templates = TemplateStore(rootURL: tplRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeInstance() -> WidgetInstance {
        WidgetInstance(id: UUID(), name: "test", templateId: "clock", size: .small, paramValues: [:])
    }

    func testRefreshWritesBothThemesAndReloads() async throws {
        let engine = FakeEngine()
        let reloader = FakeReloader()
        let pipeline = RenderPipeline(templates: templates, shared: shared,
                                      registry: .standard(), engine: engine, reloader: reloader)
        let instance = makeInstance()
        await pipeline.refresh(instance)

        XCTAssertEqual(engine.calls.map(\.theme), [.light, .dark])
        XCTAssertEqual(try Data(contentsOf: shared.renderURL(instanceId: instance.id, theme: .light)),
                       Data("png-light".utf8))
        XCTAssertEqual(reloader.kinds, ["bw.small"])
        let state = shared.loadState(instanceId: instance.id)
        XCTAssertNotNil(state.lastRenderAt)
        XCTAssertFalse(state.stale)
        XCTAssertNil(state.lastError)
    }

    func testRenderFailureRecordsErrorAndSkipsReload() async {
        let engine = FakeEngine()
        engine.shouldThrow = true
        let reloader = FakeReloader()
        let pipeline = RenderPipeline(templates: templates, shared: shared,
                                      registry: .standard(), engine: engine, reloader: reloader)
        let instance = makeInstance()
        await pipeline.refresh(instance)

        XCTAssertEqual(reloader.kinds, [])
        XCTAssertNotNil(shared.loadState(instanceId: instance.id).lastError)
    }

    func testMissingTemplateRecordsError() async {
        let pipeline = RenderPipeline(templates: templates, shared: shared,
                                      registry: .standard(), engine: FakeEngine(), reloader: FakeReloader())
        let instance = WidgetInstance(id: UUID(), name: "x", templateId: "ghost",
                                      size: .small, paramValues: [:])
        await pipeline.refresh(instance)
        XCTAssertNotNil(shared.loadState(instanceId: instance.id).lastError)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -quiet`
Expected: FAIL — `cannot find 'RenderPipeline' in scope`.

- [ ] **Step 3: Implémenter `RenderPipeline.swift`**

```swift
import Foundation
import WidgetKit

protocol Rendering {
    @MainActor func render(html: String, baseURL: URL?, context: RenderContext) async throws -> Data
}

extension RenderEngine: Rendering {}

protocol WidgetReloading {
    func reload(kind: String)
}

struct WidgetCenterReloader: WidgetReloading {
    func reload(kind: String) {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}

/// Orchestrates one refresh: fetch data → render light+dark → write to shared store → reload widgets.
/// Never throws: failures are recorded in InstanceState.lastError.
final class RenderPipeline {
    private let templates: TemplateStore
    private let shared: SharedStore
    private let registry: DataProviderRegistry
    private let engine: any Rendering
    private let reloader: any WidgetReloading

    init(templates: TemplateStore, shared: SharedStore, registry: DataProviderRegistry,
         engine: any Rendering, reloader: any WidgetReloading) {
        self.templates = templates
        self.shared = shared
        self.registry = registry
        self.engine = engine
        self.reloader = reloader
    }

    func refresh(_ instance: WidgetInstance) async {
        var state = shared.loadState(instanceId: instance.id)
        do {
            let manifest = try templates.manifest(id: instance.templateId)
            let html = try templates.html(id: instance.templateId)
            let baseURL = templates.templateDirectory(id: instance.templateId)

            // Defaults from manifest, overridden by instance values.
            var params: [String: String] = [:]
            for spec in manifest.params { params[spec.key] = spec.default }
            params.merge(instance.paramValues) { _, instanceValue in instanceValue }

            let fetch = await registry.fetchAll(sources: manifest.sources, paramValues: params)
            state.lastFetchAt = Date()
            state.stale = !fetch.failedKeys.isEmpty

            for theme in [Theme.light, Theme.dark] {
                let context = RenderContext(params: params, data: fetch.data,
                                            size: instance.size, theme: theme, stale: state.stale)
                let png = try await engine.render(html: html, baseURL: baseURL, context: context)
                try shared.writeRender(png, instanceId: instance.id, theme: theme)
            }
            state.lastRenderAt = Date()
            state.lastError = nil
            try shared.saveState(state, instanceId: instance.id)
            reloader.reload(kind: instance.size.kind)
        } catch {
            state.lastError = String(describing: error)
            try? shared.saveState(state, instanceId: instance.id)
        }
    }
}
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `xcodegen generate && xcodebuild test ... -quiet`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: render pipeline orchestrating fetch, dual-theme render, store and reload"
```

---

### Task 8: Scheduler — refresh périodique par instance

**Files:**
- Create: `BetterWidgets/Core/Scheduler.swift`
- Test: `Tests/SchedulerTests.swift` (dans le fichier, renommer le plan de test si besoin)

**Interfaces:**
- Consumes: `RenderPipeline` (via protocol), `TemplateStore`, `WidgetInstance`
- Produces:
  - `protocol Refreshing { func refresh(_ instance: WidgetInstance) async }` — `RenderPipeline` s'y conforme (`extension RenderPipeline: Refreshing {}` dans ce fichier)
  - `@MainActor final class Scheduler { init(refresher: any Refreshing, templates: TemplateStore); func start(instances: [WidgetInstance]); func stop(); func refreshAllNow(instances: [WidgetInstance]) }`
- Comportement : `start` déclenche un refresh immédiat de chaque instance puis un `Timer` répétant à `manifest.refresh` secondes (fallback 300 s si le template est introuvable, tolerance 10 %). Les refreshes passent par une file sérielle (une seule webview, spec §13) : un `AsyncStream` consommé par une Task unique.

- [ ] **Step 1: Écrire le test (échoue)**

`Tests/SchedulerTests.swift` :

```swift
import XCTest

final class SchedulerTests: XCTestCase {
    final class CountingRefresher: Refreshing, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var count = 0
        func refresh(_ instance: WidgetInstance) async {
            lock.lock(); count += 1; lock.unlock()
        }
        var safeCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    @MainActor
    func testStartTriggersImmediateRefresh() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let templates = TemplateStore(rootURL: tmp)
        let refresher = CountingRefresher()
        let scheduler = Scheduler(refresher: refresher, templates: templates)
        let instance = WidgetInstance(id: UUID(), name: "t", templateId: "ghost",
                                      size: .small, paramValues: [:])
        scheduler.start(instances: [instance])
        try await Task.sleep(for: .milliseconds(300))
        scheduler.stop()
        XCTAssertGreaterThanOrEqual(refresher.safeCount, 1)
    }

    @MainActor
    func testRefreshAllNowRefreshesEveryInstance() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let refresher = CountingRefresher()
        let scheduler = Scheduler(refresher: refresher, templates: TemplateStore(rootURL: tmp))
        let a = WidgetInstance(id: UUID(), name: "a", templateId: "g", size: .small, paramValues: [:])
        let b = WidgetInstance(id: UUID(), name: "b", templateId: "g", size: .medium, paramValues: [:])
        scheduler.refreshAllNow(instances: [a, b])
        try await Task.sleep(for: .milliseconds(300))
        scheduler.stop()
        XCTAssertEqual(refresher.safeCount, 2)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -quiet`
Expected: FAIL — `cannot find 'Scheduler' in scope`.

- [ ] **Step 3: Implémenter `Scheduler.swift`**

```swift
import Foundation

protocol Refreshing {
    func refresh(_ instance: WidgetInstance) async
}

extension RenderPipeline: Refreshing {}

/// Drives periodic refreshes. All refreshes flow through one serial queue
/// (single offscreen webview — see spec §13 "pool de 1-2 webviews").
@MainActor
final class Scheduler {
    private let refresher: any Refreshing
    private let templates: TemplateStore
    private var timers: [UUID: Timer] = [:]
    private var queueContinuation: AsyncStream<WidgetInstance>.Continuation?
    private var worker: Task<Void, Never>?

    private static let fallbackInterval: TimeInterval = 300

    init(refresher: any Refreshing, templates: TemplateStore) {
        self.refresher = refresher
        self.templates = templates
        let (stream, continuation) = AsyncStream.makeStream(of: WidgetInstance.self)
        queueContinuation = continuation
        worker = Task { [refresher] in
            for await instance in stream {
                await refresher.refresh(instance)
            }
        }
    }

    func start(instances: [WidgetInstance]) {
        stopTimers()
        for instance in instances {
            enqueue(instance)
            let interval = TimeInterval((try? templates.manifest(id: instance.templateId).refresh)
                                        ?? Int(Self.fallbackInterval))
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.enqueue(instance) }
            }
            timer.tolerance = interval * 0.1
            timers[instance.id] = timer
        }
    }

    func refreshAllNow(instances: [WidgetInstance]) {
        instances.forEach(enqueue)
    }

    func stop() {
        stopTimers()
        queueContinuation?.finish()
        worker?.cancel()
    }

    private func enqueue(_ instance: WidgetInstance) {
        queueContinuation?.yield(instance)
    }

    private func stopTimers() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
    }
}
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `xcodegen generate && xcodebuild test ... -quiet`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: per-instance refresh scheduler with serial render queue"
```

---

### Task 9: Widget Extension — 3 kinds configurables qui affichent le PNG

**Files:**
- Modify: `WidgetExtension/WidgetBundle.swift` (remplace le stub)
- Create: `WidgetExtension/WidgetInstanceEntity.swift`
- Create: `WidgetExtension/SelectWidgetIntent.swift`
- Create: `WidgetExtension/WidgetRenderView.swift`

**Interfaces:**
- Consumes: `SharedStore.appGroup()`, `WidgetInstance`, `Theme`, `WidgetSize`, `InstanceState` (compilés dans le target extension, cf. `project.yml` Task 1)
- Produces: 3 widgets `bw.small` / `bw.medium` / `bw.large` visibles dans la galerie de widgets macOS, chacun configurable (clic droit → Éditer le widget → choisir l'instance).
- Pas de tests unitaires (l'extension est passive) — vérification manuelle en Step 3.

- [ ] **Step 1: Écrire l'entity, l'intent et la vue**

`WidgetExtension/WidgetInstanceEntity.swift` :

```swift
import AppIntents

struct WidgetInstanceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Widget"
    static let defaultQuery = WidgetInstanceQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct WidgetInstanceQuery: EntityQuery {
    /// Family this query filters on; set per-kind via the intents below.
    var family: WidgetSize?

    init() {}
    init(family: WidgetSize) { self.family = family }

    private func all() -> [WidgetInstanceEntity] {
        SharedStore.appGroup().loadInstances()
            .filter { family == nil || $0.size == family }
            .map { WidgetInstanceEntity(id: $0.id.uuidString, name: $0.name) }
    }

    func entities(for identifiers: [String]) async throws -> [WidgetInstanceEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetInstanceEntity] { all() }
    func defaultResult() async -> WidgetInstanceEntity? { all().first }
}
```

`WidgetExtension/SelectWidgetIntent.swift` :

```swift
import AppIntents
import WidgetKit

struct SelectSmallWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choisir le widget"
    static let description = IntentDescription("Quel widget Better Widgets afficher.")

    @Parameter(title: "Widget", query: WidgetInstanceQuery(family: .small))
    var instance: WidgetInstanceEntity?
}

struct SelectMediumWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choisir le widget"
    static let description = IntentDescription("Quel widget Better Widgets afficher.")

    @Parameter(title: "Widget", query: WidgetInstanceQuery(family: .medium))
    var instance: WidgetInstanceEntity?
}

struct SelectLargeWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choisir le widget"
    static let description = IntentDescription("Quel widget Better Widgets afficher.")

    @Parameter(title: "Widget", query: WidgetInstanceQuery(family: .large))
    var instance: WidgetInstanceEntity?
}
```

`WidgetExtension/WidgetRenderView.swift` :

```swift
import SwiftUI
import WidgetKit

struct RenderEntry: TimelineEntry {
    let date: Date
    let instanceId: UUID?
}

struct WidgetRenderView: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: RenderEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var content: some View {
        if let id = entry.instanceId, let image = loadImage(id: id) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            VStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.title2)
                Text("Configure-moi dans\nBetter Widgets")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func loadImage(id: UUID) -> NSImage? {
        let theme: Theme = colorScheme == .dark ? .dark : .light
        let url = SharedStore.appGroup().renderURL(instanceId: id, theme: theme)
        return NSImage(contentsOf: url)
    }
}
```

- [ ] **Step 2: Remplacer `WidgetBundle.swift`**

```swift
import WidgetKit
import SwiftUI
import AppIntents

@main
struct BetterWidgetsWidgets: WidgetBundle {
    var body: some Widget {
        BWSmallWidget()
        BWMediumWidget()
        BWLargeWidget()
    }
}

/// One provider per intent type (WidgetKit requires concrete intent types per kind).
struct RenderProvider<Intent: WidgetConfigurationIntent>: AppIntentTimelineProvider {
    let instanceId: (Intent) -> UUID?

    func placeholder(in context: Context) -> RenderEntry { RenderEntry(date: .now, instanceId: nil) }

    func snapshot(for configuration: Intent, in context: Context) async -> RenderEntry {
        RenderEntry(date: .now, instanceId: instanceId(configuration))
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<RenderEntry> {
        // Single entry, .never: the app drives reloads via WidgetCenter.
        Timeline(entries: [RenderEntry(date: .now, instanceId: instanceId(configuration))], policy: .never)
    }
}

private func uuid(_ entity: WidgetInstanceEntity?) -> UUID? {
    entity.flatMap { UUID(uuidString: $0.id) }
}

struct BWSmallWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "bw.small", intent: SelectSmallWidgetIntent.self,
                               provider: RenderProvider { uuid($0.instance) }) { entry in
            WidgetRenderView(entry: entry)
        }
        .configurationDisplayName("Better Widget — Petit")
        .description("Un widget créé dans Better Widgets.")
        .supportedFamilies([.systemSmall])
    }
}

struct BWMediumWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "bw.medium", intent: SelectMediumWidgetIntent.self,
                               provider: RenderProvider { uuid($0.instance) }) { entry in
            WidgetRenderView(entry: entry)
        }
        .configurationDisplayName("Better Widget — Moyen")
        .description("Un widget créé dans Better Widgets.")
        .supportedFamilies([.systemMedium])
    }
}

struct BWLargeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "bw.large", intent: SelectLargeWidgetIntent.self,
                               provider: RenderProvider { uuid($0.instance) }) { entry in
            WidgetRenderView(entry: entry)
        }
        .configurationDisplayName("Better Widget — Grand")
        .description("Un widget créé dans Better Widgets.")
        .supportedFamilies([.systemLarge])
    }
}
```

- [ ] **Step 3: Builder et vérifier**

Run: `xcodegen generate && xcodebuild build -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: `BUILD SUCCEEDED`.

La vérification visuelle complète (galerie de widgets) n'est possible qu'après la Task 10 (il faut l'app lancée + des instances). Ne pas la faire ici.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: widget extension — three configurable kinds rendering shared PNGs"
```

---

### Task 10: App barre de menus — composition root + instance de démo (bout-en-bout)

**Files:**
- Modify: `BetterWidgets/App/BetterWidgetsApp.swift`
- Create: `BetterWidgets/App/AppState.swift`

**Interfaces:**
- Consumes: tout (Tasks 2-9)
- Produces: `@MainActor final class AppState: ObservableObject { @Published var instances: [WidgetInstance]; func bootstrap(); func refreshAll(); var shared: SharedStore }` — consommé plus tard par l'UI du Plan 3.

- [ ] **Step 1: Écrire `AppState.swift`**

```swift
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var instances: [WidgetInstance] = []

    let shared = SharedStore.appGroup()
    let templates = TemplateStore.applicationSupport()
    private lazy var pipeline = RenderPipeline(
        templates: templates, shared: shared,
        registry: .standard(), engine: RenderEngine(), reloader: WidgetCenterReloader())
    private lazy var scheduler = Scheduler(refresher: pipeline, templates: templates)

    func bootstrap() {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("templates") {
            try? templates.installBundledTemplates(from: bundled)
        }
        instances = shared.loadInstances()
        if instances.isEmpty {
            let demo = WidgetInstance(id: UUID(), name: "Horloge", templateId: "hello-clock",
                                      size: .small, paramValues: [:])
            instances = [demo]
            try? shared.saveInstances(instances)
        }
        scheduler.start(instances: instances)
    }

    func refreshAll() {
        scheduler.refreshAllNow(instances: instances)
    }

    func statusLine(for instance: WidgetInstance) -> String {
        let state = shared.loadState(instanceId: instance.id)
        if let error = state.lastError { return "⚠︎ \(instance.name) — \(error.prefix(40))" }
        if state.stale { return "◔ \(instance.name) — données périmées" }
        return "● \(instance.name)"
    }
}
```

- [ ] **Step 2: Remplacer `BetterWidgetsApp.swift`**

⚠️ Piège : le bootstrap doit tourner **au lancement**, pas au premier clic sur le menu — `MenuBarExtra` n'a pas de `onAppear` fiable au launch, d'où le `NSApplicationDelegateAdaptor` :

```swift
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var onLaunch: (() -> Void)?
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.onLaunch?()
    }
}

@main
struct BetterWidgetsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra("Better Widgets", systemImage: "square.grid.2x2") {
            ForEach(state.instances) { instance in
                Text(state.statusLine(for: instance))
            }
            Divider()
            Button("Tout rafraîchir") { state.refreshAll() }
            Button("Quitter") { NSApp.terminate(nil) }
        }
    }

    init() {
        let state = _state
        AppDelegate.onLaunch = { Task { @MainActor in state.wrappedValue.bootstrap() } }
    }
}
```

- [ ] **Step 3: Build + lancement manuel bout-en-bout**

Run:
```bash
xcodegen generate && xcodebuild build -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet
APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/BetterWidgets-*/Build/Products/Debug/*.app | head -1)
open "$APP"
sleep 20
CONTAINER=~/Library/Group\ Containers/5C67TFSJ2B.betterwidgets/Store
ls -la "$CONTAINER/renders/"
```
Expected: deux PNG (`<uuid>-light.png`, `<uuid>-dark.png`) présents et non vides. Ouvrir l'un des deux (`open <png>`) et vérifier visuellement l'horloge.

- [ ] **Step 4: Vérification widget réel (manuelle, avec Maxim si besoin)**

1. L'app tourne (icône barre de menus visible).
2. Bureau macOS → clic droit → « Modifier les widgets » → chercher « Better Widget — Petit » → le poser.
3. Clic droit sur le widget → « Modifier le widget » → choisir « Horloge ».
4. Le widget affiche l'horloge rendue ; basculer le Mac en mode sombre → l'image passe en variante sombre.

Si la galerie ne liste pas les widgets : vérifier que l'app a été **lancée au moins une fois depuis /Applications ou DerivedData** (l'enregistrement WidgetKit suit LaunchServices), et `pluginkit -m | grep -i betterwidgets`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: menu bar app with bootstrap, demo instance and end-to-end refresh"
```

---

### Task 11: Smoke test scripté + docs du sous-projet

**Files:**
- Create: `scripts/smoke.sh`
- Create: `README.md`
- Create: `CLAUDE.md`

**Interfaces:**
- Consumes: tout
- Produces: vérification bout-en-bout reproductible + doc d'entrée pour les sessions futures.

- [ ] **Step 1: Écrire `scripts/smoke.sh`**

```bash
#!/usr/bin/env bash
# Smoke E2E: build, launch, assert fresh renders exist in the App Group container.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
xcodebuild build -project BetterWidgets.xcodeproj -scheme BetterWidgets \
  -destination 'platform=macOS' -quiet

APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/BetterWidgets-*/Build/Products/Debug/*.app | head -1)
CONTAINER="$HOME/Library/Group Containers/5C67TFSJ2B.betterwidgets/Store"

pkill -x "Better Widgets" 2>/dev/null || true
rm -rf "$CONTAINER/renders"
open "$APP"

for i in $(seq 1 30); do
  count=$(ls "$CONTAINER/renders/" 2>/dev/null | grep -c '\.png$' || true)
  if [ "${count:-0}" -ge 2 ]; then
    echo "✅ smoke OK — $count render(s) in $CONTAINER/renders"
    exit 0
  fi
  sleep 2
done

echo "❌ smoke FAILED — no renders after 60s" >&2
exit 1
```

Run: `chmod +x scripts/smoke.sh && ./scripts/smoke.sh`
Expected: `✅ smoke OK — 2 render(s) …`.

- [ ] **Step 2: Écrire `README.md`**

Contenu : pitch (2 phrases), prérequis (Xcode, xcodegen, team `5C67TFSJ2B`), commandes (`xcodegen generate`, build, test, `scripts/smoke.sh`), lien vers le spec, statut « Plan 1 — fondations ».

- [ ] **Step 3: Écrire `CLAUDE.md`**

Contenu : stack (Swift/SwiftUI/WidgetKit/XcodeGen), **le .xcodeproj est généré — éditer `project.yml`**, App Group `5C67TFSJ2B.betterwidgets`, kinds `bw.*` immuables, commande de test canonique, pointeurs spec + plans, convention commits (MaximCosta, pas d'IA), état d'avancement des plans 1-4.

- [ ] **Step 4: Test final complet + commit**

Run: `xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet && ./scripts/smoke.sh`
Expected: `TEST SUCCEEDED` puis `✅ smoke OK`.

```bash
git add -A && git commit -m "chore: smoke script and project docs"
```

---

## Self-review (fait à l'écriture)

- **Couverture spec** : §3 architecture → Tasks 1,9,10 ; §4 format/manifest/BW → Tasks 3,5,2 ; §5 pipeline/refresh → Tasks 7,8 ; §6 providers json+system → Task 6 (weather/calendar/rss = Plan 2) ; §7 sécurité → https-only dans JSONDataProvider (le reste du modèle de permissions = Plan 2) ; §8 UI → menu bar minimal seulement (UI complète = Plan 3) ; §9 erreurs → Tasks 6,7 (fail-soft) ; §10 tests → chaque task + smoke ; §11 distribution = Plan 4 ; §12-13 → Task 2 (spike en premier).
- **Types cohérents** : `RenderContext`/`Rendering`/`Refreshing`/`WidgetReloading` définis une fois, consommés avec les mêmes signatures (Tasks 2→7→8→10) ; `SourceSpec.knownTypes` vérifié au manifest uniquement (note Task 6).
- **Placeholders** : aucun TODO/TBD ; tout le code des steps est complet.
