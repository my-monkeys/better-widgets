# Better Widgets — Plan 3b-2 : Mode avancé code (CodeMirror embarqué)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permettre d'écrire ses propres templates de widget en HTML/CSS/JS libre + manifest, dans un éditeur de code (CodeMirror embarqué, coloration + numéros de ligne) avec preview live et validation — via « Nouveau template » / « Forker » depuis la Galerie.

**Architecture:** Un `TemplateCodeEditorView` (feuille) en deux volets : à gauche `CodeEditorView` (onglets `index.html`/`manifest.json` au-dessus d'un `CodeEditorBridge` = CodeMirror 5 bundlé dans une WKWebView + pont Swift↔JS), à droite la `LivePreviewView` réutilisée de 3b-1. `TemplateStore` gagne des écritures (create/fork/save/delete de templates **utilisateur** ; les bundlés sont read-only). Le template est créé sur disque d'abord (scaffold/fork), puis édité/sauvé en place.

**Tech Stack:** Swift 5.9, SwiftUI, WebKit (WKWebView + `WKScriptMessageHandler`), CodeMirror 5 (assets statiques bundlés, aucun CDN au runtime), XCTest, XcodeGen. macOS 14+, Xcode 27.

## Global Constraints

- **Templates bundlés = read-only** (`hello-clock`/`feed-list`/`agenda`/`weather-now`) : jamais édités en place ni supprimés. Pour les modifier → **Forker**. Les templates **utilisateur** (créés/forkés) portent un marqueur fichier `.user` dans leur dossier et sont éditables/supprimables.
- **CodeMirror embarqué** (décision actée), **CodeMirror 5** (drop-in .js/.css, embeddable sans bundler — CM6 nécessite un build). Assets vendorés dans `BetterWidgets/Resources/codemirror/`, **aucun CDN au runtime**.
- **Confinement WebView préservé** : l'éditeur et la preview chargent via un scheme handler confiné (réutilise `TemplateAssetSchemeHandler` + `NavigationPolicy`, pas de `file://`). Un template utilisateur n'a aucun privilège supplémentaire.
- **Validation au save** : `manifest.json` doit passer `TemplateManifest.validated` (déjà là) ; invalide → refus + message précis, rien n'est écrit. Le HTML est libre (non validé).
- **On édite le template, pas l'instance** (l'éditeur de params d'instance = 3b-1). Pas de secrets ici (notion d'instance).
- **Le `.xcodeproj` est généré** : fichiers `Core/**`/`App/**` auto-inclus ; les fichiers de logique testés (`TemplateEditorModel.swift`) s'ajoutent **individuellement** aux sources `BetterWidgetsTests` de `project.yml` (jamais le dossier `App/`). Les assets `Resources/codemirror/` s'ajoutent en folder-resource (comme `Resources/templates`). `xcodegen generate` après tout changement de `project.yml`.
- **Commande de test** : `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`. Départ : **93 tests verts**.
- Commits : Conventional Commits, auteur `MaximCosta <maxim@users.noreply.github.com>`, **aucune mention d'IA**. Code/commentaires anglais ; UI français.
- Flake connu `RenderEngineTests.testMediumSizeDimensions` (relancer isolé si besoin).

## Périmètre

**Dans 3b-2** : spike CodeMirror + `CodeEditorBridge` ; écritures `TemplateStore` ; `TemplateEditorModel` + validation ; `CodeEditorView` (onglets) + `TemplateCodeEditorView` (2 volets, preview réutilisée) ; entrées Galerie (Nouveau / Forker / Supprimer). **Hors 3b-2** : import/export `.bwidget` + consentement + météo localisation (3c) ; distribution (4) ; autocomplétion/linting ; nettoyage des instances orphelines.

---

## Structure des fichiers

```
BetterWidgets/
├── Resources/codemirror/       # NOUVEAU : CM5 vendoré (codemirror.min.js/.css + modes) + editor.html
├── Core/
│   └── TemplateStore.swift      # MODIF : createUserTemplate/forkTemplate/saveTemplate/deleteUserTemplate/isUserTemplate
├── App/
│   ├── CodeEditorBridge.swift   # NOUVEAU : NSViewRepresentable WKWebView + CodeMirror + pont Swift↔JS (spike)
│   ├── CodeEditorView.swift     # NOUVEAU : onglets html/manifest au-dessus du bridge
│   ├── TemplateEditorModel.swift# NOUVEAU : copie de travail html+manifest, validate, previewContext, save
│   ├── TemplateCodeEditorView.swift # NOUVEAU : écran 2 volets (code / preview) + save/erreurs
│   └── GalleryView.swift        # MODIF : Nouveau template / Forker / Supprimer → ouvre l'éditeur
├── project.yml                  # MODIF : folder-resource Resources/codemirror + TemplateEditorModel.swift aux tests
└── Tests/
    ├── TemplateStoreWriteTests.swift  # NOUVEAU
    └── TemplateEditorModelTests.swift # NOUVEAU
```

---

### Task 1: Spike CodeMirror — `CodeEditorBridge` (vendorer CM5 + pont Swift↔JS)

**But** : prouver que CodeMirror 5 bundlé charge dans une WKWebView, que le texte édité remonte à Swift, et qu'on peut le (ré)injecter. Risque n°1 du plan — si insoluble après investigation sérieuse, rapporter BLOCKED (fallback `TextEditor` natif à décider avec le contrôleur).

**Files:**
- Create: `BetterWidgets/Resources/codemirror/` (assets CM5 + `editor.html`)
- Create: `BetterWidgets/App/CodeEditorBridge.swift`
- Modify: `project.yml` (folder-resource `Resources/codemirror`)

**Interfaces:**
- Consumes: `TemplateAssetSchemeHandler` (`.scheme` = `"bwasset"`) + `NavigationPolicy` (Plan 2).
- Produces:
  - `struct CodeEditorBridge: NSViewRepresentable` — `init(text: Binding<String>, language: Language, assetsDir: URL)` où `enum Language: String { case html, json }`. Monte une WKWebView qui charge `editor.html` (servi via un `TemplateAssetSchemeHandler(templateDir: assetsDir)` sur `bwasset://template/editor.html`), initialise CodeMirror sur le contenu de `text`, met à jour le `@Binding` à chaque édition (via `WKScriptMessageHandler` nommé `bwEditor`), et ré-injecte le contenu/le mode quand `text`/`language` changent depuis l'extérieur.

- [ ] **Step 1: Vendorer CodeMirror 5** (dev-time, committé — aucun CDN au runtime)

Récupérer CM 5.65.16 depuis cdnjs (dev-time) et les committer dans `BetterWidgets/Resources/codemirror/` :

```bash
cd /Users/maxim/Documents/my-monkey/better-widgets
mkdir -p BetterWidgets/Resources/codemirror/mode/{xml,javascript,css,htmlmixed}
BASE=https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16
curl -fsSL "$BASE/codemirror.min.js"                 -o BetterWidgets/Resources/codemirror/codemirror.min.js
curl -fsSL "$BASE/codemirror.min.css"                -o BetterWidgets/Resources/codemirror/codemirror.min.css
curl -fsSL "$BASE/mode/xml/xml.min.js"               -o BetterWidgets/Resources/codemirror/mode/xml/xml.min.js
curl -fsSL "$BASE/mode/javascript/javascript.min.js" -o BetterWidgets/Resources/codemirror/mode/javascript/javascript.min.js
curl -fsSL "$BASE/mode/css/css.min.js"               -o BetterWidgets/Resources/codemirror/mode/css/css.min.js
curl -fsSL "$BASE/mode/htmlmixed/htmlmixed.min.js"   -o BetterWidgets/Resources/codemirror/mode/htmlmixed/htmlmixed.min.js
# sanity : les 6 fichiers non vides
for f in codemirror.min.js codemirror.min.css mode/xml/xml.min.js mode/javascript/javascript.min.js mode/css/css.min.js mode/htmlmixed/htmlmixed.min.js; do
  test -s "BetterWidgets/Resources/codemirror/$f" || echo "MANQUE: $f"
done
```
Expected: aucune ligne `MANQUE`. (Si cdnjs est injoignable, essayer `https://unpkg.com/codemirror@5.65.16/lib/codemirror.js` etc. — l'important est d'avoir les fichiers CM5 committés localement.)

- [ ] **Step 2: Écrire `editor.html`** (dans `Resources/codemirror/`)

```html
<!doctype html>
<html><head><meta charset="utf-8">
<link rel="stylesheet" href="codemirror.min.css">
<style>
  html,body,.CodeMirror{height:100%;margin:0}
  .CodeMirror{font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace}
</style>
<script src="codemirror.min.js"></script>
<script src="mode/xml/xml.min.js"></script>
<script src="mode/css/css.min.js"></script>
<script src="mode/javascript/javascript.min.js"></script>
<script src="mode/htmlmixed/htmlmixed.min.js"></script>
</head><body>
<textarea id="ta"></textarea>
<script>
  var cm = CodeMirror.fromTextArea(document.getElementById("ta"), {
    lineNumbers: true, mode: "htmlmixed"
  });
  var suppress = false;
  cm.on("change", function () {
    if (suppress) return;
    window.webkit.messageHandlers.bwEditor.postMessage(cm.getValue());
  });
  // Called from Swift.
  window.bwSetContent = function (text, mode) {
    suppress = true;
    cm.setOption("mode", mode === "json" ? {name:"javascript", json:true} : "htmlmixed");
    if (cm.getValue() !== text) cm.setValue(text);
    suppress = false;
  };
</script></body></html>
```

- [ ] **Step 3: Ajouter le folder-resource dans `project.yml`**

Sous le target `BetterWidgets` → `sources`, ajouter (comme `Resources/templates`) :
```yaml
      - path: BetterWidgets/Resources/codemirror
        type: folder
        buildPhase: resources
```
Et si le glob principal `BetterWidgets` inclut déjà `Resources/**`, ajouter `Resources/codemirror/**` à ses `excludes` (comme `Resources/templates/**`) pour éviter le double-bundling.

- [ ] **Step 4: Implémenter `CodeEditorBridge.swift`**

```swift
import SwiftUI
import WebKit

struct CodeEditorBridge: NSViewRepresentable {
    enum Language: String { case html, json }

    @Binding var text: String
    var language: Language
    let assetsDir: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "bwEditor")
        config.setURLSchemeHandler(TemplateAssetSchemeHandler(templateDir: assetsDir),
                                   forURLScheme: TemplateAssetSchemeHandler.scheme)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.pendingText = text
        context.coordinator.pendingLanguage = language
        webView.load(URLRequest(url: URL(string: "\(TemplateAssetSchemeHandler.scheme)://template/editor.html")!))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.applyExternal(text: text, language: language)
    }

    func makeCoordinator() -> Coordinator { Coordinator($text) }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let text: Binding<String>
        weak var webView: WKWebView?
        var pendingText = ""
        var pendingLanguage: Language = .html
        private var loaded = false
        private var lastSet = ""

        init(_ text: Binding<String>) { self.text = text }

        // Text edited in CodeMirror flows back to the SwiftUI binding.
        nonisolated func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let value = message.body as? String else { return }
            Task { @MainActor in
                self.lastSet = value
                self.text.wrappedValue = value
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            setContent(pendingText, pendingLanguage)
        }

        nonisolated func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(NavigationPolicy.decide(for: action.request.url))
        }

        // Push external changes (tab switch / programmatic edit) into CodeMirror,
        // skipping echoes of what the editor itself just sent.
        func applyExternal(text value: String, language: Language) {
            pendingText = value; pendingLanguage = language
            guard loaded, value != lastSet else { return }
            setContent(value, language)
        }

        private func setContent(_ value: String, _ language: Language) {
            lastSet = value
            let escaped = String(data: try! JSONSerialization.data(withJSONObject: [value]), encoding: .utf8)!
            // escaped is a JSON array "[\"...\"]"; take element 0 in JS.
            webView?.evaluateJavaScript("window.bwSetContent(\(escaped)[0], '\(language.rawValue)');")
        }
    }
}
```

- [ ] **Step 5: Build + vérification réelle (round-trip)**

Run: `xcodegen generate && xcodebuild build -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: `BUILD SUCCEEDED` (les assets CM sont bundlés).

Vérification réelle du pont : la façon la plus simple est un mini-harnais temporaire — un `WindowGroup` de debug ou un preview qui monte un `CodeEditorBridge` avec un `@State text` affiché à côté. Puisque l'éditeur complet arrive en Task 4, pour le spike : monter `CodeEditorBridge` dans une petite fenêtre de test lancée à la main, taper, et vérifier que le `@State` Swift se met à jour (log via `print` ou affichage). L'implémenteur documente précisément : CodeMirror s'affiche-t-il (coloration + numéros de ligne) ? le texte tapé remonte-t-il à Swift ? un `text` changé côté Swift se ré-injecte-t-il ? Captures si l'écran n'est pas verrouillé. **Si CodeMirror ne charge pas / le pont ne fonctionne pas après investigation** → rapporter BLOCKED avec les détails (le contrôleur décidera du fallback `TextEditor`). Retirer tout harnais de debug avant le commit.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: CodeMirror-backed code editor bridge (WKWebView + Swift↔JS)"
```

---

### Task 2: Écritures `TemplateStore` (create/fork/save/delete utilisateur)

**Files:**
- Modify: `BetterWidgets/Core/TemplateStore.swift`
- Test: `Tests/TemplateStoreWriteTests.swift`

**Interfaces:**
- Consumes: `TemplateManifest.validated(from:)`, `ManifestError`.
- Produces (sur `TemplateStore`) :
  - `func isUserTemplate(id: String) -> Bool` — présence du marqueur `.user` dans le dossier du template.
  - `func createUserTemplate(name: String) -> String` — id-slug unique ; crée dossier + `index.html` scaffold + `manifest.json` par défaut valide + marqueur `.user` ; renvoie l'id.
  - `func forkTemplate(from sourceId: String) throws -> String` — nouvel id unique (`<source>-copie`) ; copie `index.html`, copie `manifest.json` avec les champs `id` réécrit et `name` suffixé « (copie) » ; marqueur `.user` ; renvoie l'id ; throw `TemplateStoreError.notFound` si source absente.
  - `func saveTemplate(id: String, html: String, manifestJSON: String) throws` — valide `manifestJSON` (`TemplateManifest.validated`), écrit `index.html` + `manifest.json` atomiquement ; throw l'`ManifestError`/erreur si invalide (rien écrit).
  - `func deleteUserTemplate(id: String)` — supprime le dossier si `isUserTemplate`, sinon no-op.
  - `func slug(for name: String) -> String` (interne) + unicité par suffixe numérique.

- [ ] **Step 1: Écrire `Tests/TemplateStoreWriteTests.swift` (échoue)**

```swift
import XCTest

final class TemplateStoreWriteTests: XCTestCase {
    private var root: URL!
    private var store: TemplateStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = TemplateStore(rootURL: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testCreateUserTemplateScaffoldIsValidAndMarked() throws {
        let id = store.createUserTemplate(name: "Mon Widget")
        XCTAssertTrue(store.isUserTemplate(id: id))
        let m = try store.manifest(id: id)          // scaffold parses & validates
        XCTAssertEqual(m.id, id)
        XCTAssertFalse(m.sizes.isEmpty)
        XCTAssertFalse(try store.html(id: id).isEmpty)
    }

    func testCreateUserTemplateUniqueIds() {
        let a = store.createUserTemplate(name: "Dup")
        let b = store.createUserTemplate(name: "Dup")
        XCTAssertNotEqual(a, b)                       // collision → suffix
    }

    func testForkCopiesAndReid() throws {
        let src = store.createUserTemplate(name: "Source")
        try store.saveTemplate(id: src, html: "<p>hi</p>",
            manifestJSON: #"{"id":"\#(src)","name":"Source","version":"1.0.0","sizes":["small"],"refresh":900,"params":[],"sources":[]}"#)
        let fork = try store.forkTemplate(from: src)
        XCTAssertNotEqual(fork, src)
        XCTAssertTrue(store.isUserTemplate(id: fork))
        XCTAssertEqual(try store.manifest(id: fork).id, fork)   // manifest id rewritten
        XCTAssertEqual(try store.html(id: fork), "<p>hi</p>")   // html copied
    }

    func testSaveRejectsInvalidManifest() {
        let id = store.createUserTemplate(name: "T")
        let before = try? store.html(id: id)
        XCTAssertThrowsError(try store.saveTemplate(id: id, html: "<b>x</b>",
            manifestJSON: #"{"id":"\#(id)","name":"T","version":"1","sizes":[],"refresh":900,"params":[],"sources":[]}"#))  // emptySizes
        XCTAssertEqual(try? store.html(id: id), before)  // nothing written on invalid
    }

    func testSaveWritesWhenValid() throws {
        let id = store.createUserTemplate(name: "T")
        try store.saveTemplate(id: id, html: "<b>ok</b>",
            manifestJSON: #"{"id":"\#(id)","name":"T","version":"1.0.0","sizes":["medium"],"refresh":600,"params":[],"sources":[]}"#)
        XCTAssertEqual(try store.html(id: id), "<b>ok</b>")
        XCTAssertEqual(try store.manifest(id: id).refresh, 600)
    }

    func testDeleteUserTemplateRemovesUserButNotBundled() throws {
        let user = store.createUserTemplate(name: "U")
        store.deleteUserTemplate(id: user)
        XCTAssertThrowsError(try store.manifest(id: user))     // gone

        // simulate a bundled (no .user marker) template
        let bundledDir = root.appendingPathComponent("bundled")
        try FileManager.default.createDirectory(at: bundledDir, withIntermediateDirectories: true)
        try #"{"id":"bundled","name":"B","version":"1.0.0","sizes":["small"],"refresh":900,"params":[],"sources":[]}"#
            .write(to: bundledDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        XCTAssertFalse(store.isUserTemplate(id: "bundled"))
        store.deleteUserTemplate(id: "bundled")                 // no-op
        XCTAssertNoThrow(try store.manifest(id: "bundled"))     // still there
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -only-testing:BetterWidgetsTests/TemplateStoreWriteTests -quiet`
Expected: FAIL — `value of type 'TemplateStore' has no member 'createUserTemplate'`.

- [ ] **Step 3: Implémenter les écritures dans `TemplateStore.swift`**

Ajouter dans la classe :

```swift
    private var userMarkerName: String { ".user" }

    func isUserTemplate(id: String) -> Bool {
        FileManager.default.fileExists(atPath:
            templateDirectory(id: id).appendingPathComponent(userMarkerName).path)
    }

    private func existingIds() -> Set<String> {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)) ?? []
        return Set(dirs.map { $0.lastPathComponent })
    }

    private func uniqueID(base: String) -> String {
        let slug = base.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { acc, ch in
                if ch == "-" && acc.last == "-" { return }; acc.append(ch)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let root = slug.isEmpty ? "widget" : slug
        let taken = existingIds()
        if !taken.contains(root) { return root }
        var n = 2
        while taken.contains("\(root)-\(n)") { n += 1 }
        return "\(root)-\(n)"
    }

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

    func saveTemplate(id: String, html: String, manifestJSON: String) throws {
        _ = try TemplateManifest.validated(from: Data(manifestJSON.utf8))   // throws if invalid → nothing written
        let dir = templateDirectory(id: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try manifestJSON.write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try html.write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }

    func deleteUserTemplate(id: String) {
        guard isUserTemplate(id: id) else { return }
        try? FileManager.default.removeItem(at: templateDirectory(id: id))
    }
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/TemplateStoreWriteTests -quiet`
Expected: PASS. Puis suite complète verte.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: TemplateStore user-template writes (create/fork/save/delete)"
```

---

### Task 3: `TemplateEditorModel`

**Files:**
- Create: `BetterWidgets/App/TemplateEditorModel.swift`
- Modify: `project.yml` (ajouter `BetterWidgets/App/TemplateEditorModel.swift` aux sources `BetterWidgetsTests`)
- Test: `Tests/TemplateEditorModelTests.swift`

**Interfaces:**
- Consumes: `TemplateStore` (`html`, `manifest` — mais on charge le manifest **brut** ; `saveTemplate`), `TemplateManifest`/`ManifestError`, `RenderContext`, `WidgetSize`, `Theme`.
- Produces: `@MainActor final class TemplateEditorModel: ObservableObject`
  - `init(templateId: String, store: TemplateStore)` — charge `htmlText` (via `store.html`) et `manifestText` (le JSON brut du fichier `manifest.json`, pas re-sérialisé — lire le fichier tel quel).
  - `let templateId: String`
  - `@Published var htmlText: String` ; `@Published var manifestText: String` ; `@Published var tab: Tab` (`enum Tab { case html, manifest }`, défaut `.html`)
  - `func validate() -> Result<TemplateManifest, Error>` — `TemplateManifest.validated(from: Data(manifestText.utf8))`.
  - `func previewManifest() -> TemplateManifest?` — `try? validate().get()`.
  - `func previewContext(data: [String: Any], stale: Bool) -> RenderContext` — params = défauts du `previewManifest` (`spec.default`), size = première taille du previewManifest (sinon `.small`), theme `.light`.
  - `func save(into store: TemplateStore) throws` — `store.saveTemplate(id: templateId, html: htmlText, manifestJSON: manifestText)`.
  - `func errorMessage(_ error: Error) -> String` — mappe `ManifestError` en texte FR.

- [ ] **Step 1: Ajouter le fichier aux sources de test dans `project.yml`**

Sous `BetterWidgetsTests.sources`, ajouter `- path: BetterWidgets/App/TemplateEditorModel.swift` avec `optional: true`.

- [ ] **Step 2: Écrire `Tests/TemplateEditorModelTests.swift` (échoue)**

```swift
import XCTest

@MainActor
final class TemplateEditorModelTests: XCTestCase {
    private var root: URL!
    private var store: TemplateStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = TemplateStore(rootURL: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testLoadsHtmlAndManifest() throws {
        let id = store.createUserTemplate(name: "T")
        let model = TemplateEditorModel(templateId: id, store: store)
        XCTAssertFalse(model.htmlText.isEmpty)
        XCTAssertTrue(model.manifestText.contains("\"id\""))
        XCTAssertEqual(model.tab, .html)
    }

    func testValidateOKAndError() throws {
        let id = store.createUserTemplate(name: "T")
        let model = TemplateEditorModel(templateId: id, store: store)
        if case .failure = model.validate() { XCTFail("scaffold should be valid") }
        model.manifestText = #"{"id":"t","name":"T","version":"1","sizes":[],"refresh":900,"params":[],"sources":[]}"#
        if case .success = model.validate() { XCTFail("emptySizes must fail") }
    }

    func testPreviewContextUsesManifestDefaultsAndFirstSize() throws {
        let id = store.createUserTemplate(name: "T")
        let model = TemplateEditorModel(templateId: id, store: store)
        model.manifestText = #"{"id":"t","name":"T","version":"1.0.0","sizes":["medium"],"refresh":900,"params":[{"key":"accent","type":"color","label":"A","default":"#abc"}],"sources":[]}"#
        let ctx = model.previewContext(data: [:], stale: false)
        XCTAssertEqual(ctx.size, .medium)
        XCTAssertEqual(ctx.params["accent"], "#abc")
    }

    func testSaveDelegatesToStore() throws {
        let id = store.createUserTemplate(name: "T")
        let model = TemplateEditorModel(templateId: id, store: store)
        model.htmlText = "<i>edited</i>"
        try model.save(into: store)
        XCTAssertEqual(try store.html(id: id), "<i>edited</i>")
    }
}
```

- [ ] **Step 3: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/TemplateEditorModelTests -quiet`
Expected: FAIL — `cannot find 'TemplateEditorModel' in scope`.

- [ ] **Step 4: Implémenter `TemplateEditorModel.swift`**

```swift
import Foundation
import SwiftUI

/// Working copy of a template's source (index.html + raw manifest.json) being
/// edited in advanced mode. Validation is strict only on save; the preview uses
/// the last parsable manifest.
@MainActor
final class TemplateEditorModel: ObservableObject {
    enum Tab { case html, manifest }

    let templateId: String
    @Published var htmlText: String
    @Published var manifestText: String
    @Published var tab: Tab = .html

    init(templateId: String, store: TemplateStore) {
        self.templateId = templateId
        self.htmlText = (try? store.html(id: templateId)) ?? ""
        let manifestURL = store.templateDirectory(id: templateId).appendingPathComponent("manifest.json")
        self.manifestText = (try? String(contentsOf: manifestURL, encoding: .utf8)) ?? ""
    }

    func validate() -> Result<TemplateManifest, Error> {
        Result { try TemplateManifest.validated(from: Data(manifestText.utf8)) }
    }

    func previewManifest() -> TemplateManifest? { try? validate().get() }

    func previewContext(data: [String: Any], stale: Bool) -> RenderContext {
        let manifest = previewManifest()
        var params: [String: String] = [:]
        for spec in manifest?.params ?? [] { params[spec.key] = spec.default }
        let size = manifest?.sizes.first ?? .small
        return RenderContext(params: params, data: data, size: size, theme: .light, stale: stale)
    }

    func save(into store: TemplateStore) throws {
        try store.saveTemplate(id: templateId, html: htmlText, manifestJSON: manifestText)
    }

    func errorMessage(_ error: Error) -> String {
        guard let e = error as? ManifestError else { return "Manifest invalide." }
        switch e {
        case .invalidJSON: return "JSON invalide (syntaxe)."
        case .emptySizes: return "Le champ « sizes » ne peut pas être vide."
        case .refreshTooSmall: return "« refresh » doit être ≥ 30 secondes."
        case .duplicateParamKey(let k): return "Clé de paramètre en double : \(k)."
        case .duplicateSourceKey(let k): return "Clé de source en double : \(k)."
        case .unknownSourceType(let t): return "Type de source inconnu : \(t)."
        }
    }
}
```

- [ ] **Step 5: Vérifier que les tests passent**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: TemplateEditorModel — working copy + manifest validation for advanced mode"
```

---

### Task 4: `CodeEditorView` + `TemplateCodeEditorView` + entrée « Nouveau template »

**Files:**
- Create: `BetterWidgets/App/CodeEditorView.swift`
- Create: `BetterWidgets/App/TemplateCodeEditorView.swift`
- Modify: `BetterWidgets/App/GalleryView.swift` (bouton « Nouveau template » → crée + ouvre l'éditeur)

**Interfaces:**
- Consumes: `CodeEditorBridge` (Task 1), `TemplateEditorModel` (Task 3), `AppState` (`templates`), `TemplateStore` (`createUserTemplate`, `templateDirectory`), `LivePreviewView` (3b-1), `DataProviderRegistry`, `RenderContext`, `DesignTokens`, `WidgetSize`, `Theme`, `SourceSpec`.
- Produces:
  - `struct CodeEditorView: View` — `init(model: TemplateEditorModel, assetsDir: URL)` ; un `Picker` d'onglet (`index.html` / `manifest.json`) au-dessus d'un `CodeEditorBridge` dont le `text`/`language` sont liés à `model.htmlText`/`model.manifestText` selon `model.tab`.
  - `struct TemplateCodeEditorView: View` — `init(state: AppState, templateId: String, onClose: () -> Void)` ; 2 volets (gauche `CodeEditorView`, droite `LivePreviewView` avec un fetch de données de preview) ; barre Enregistrer (valide → `model.save`; invalide → bandeau d'erreur, ne ferme pas) / Fermer.
  - `GalleryView` : un bouton « Nouveau template » en tête → `let id = state.templates.createUserTemplate(name: "Nouveau widget")` → présente `TemplateCodeEditorView(state:templateId:)` en `.sheet`.
- Vues SwiftUI → build-gated ; logique déjà testée (Tasks 2,3).

- [ ] **Step 1: Invoquer `minimalist-ui`** avant le SwiftUI.

- [ ] **Step 2: Implémenter `CodeEditorView.swift`**

```swift
import SwiftUI

struct CodeEditorView: View {
    @ObservedObject var model: TemplateEditorModel
    let assetsDir: URL

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.tab) {
                Text("index.html").tag(TemplateEditorModel.Tab.html)
                Text("manifest.json").tag(TemplateEditorModel.Tab.manifest)
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(DesignTokens.Space.sm)
            CodeEditorBridge(text: activeBinding,
                             language: model.tab == .manifest ? .json : .html,
                             assetsDir: assetsDir)
        }
        .background(DesignTokens.surface)
    }

    private var activeBinding: Binding<String> {
        model.tab == .manifest
            ? Binding(get: { model.manifestText }, set: { model.manifestText = $0 })
            : Binding(get: { model.htmlText }, set: { model.htmlText = $0 })
    }
}
```

- [ ] **Step 3: Implémenter `TemplateCodeEditorView.swift`**

```swift
import SwiftUI

struct TemplateCodeEditorView: View {
    @StateObject private var model: TemplateEditorModel
    private let state: AppState
    private let onClose: () -> Void
    @State private var validationError: String?
    @State private var previewData: [String: Any] = [:]
    @State private var previewStale = false

    init(state: AppState, templateId: String, onClose: @escaping () -> Void) {
        self.state = state
        self.onClose = onClose
        _model = StateObject(wrappedValue: TemplateEditorModel(templateId: templateId, store: state.templates))
    }

    private var assetsDir: URL {
        Bundle.main.resourceURL!.appendingPathComponent("codemirror")
    }
    private var templateDir: URL { state.templates.templateDirectory(id: model.templateId) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignTokens.Space.xl) {
                CodeEditorView(model: model, assetsDir: assetsDir).frame(minWidth: 380)
                previewPanel
            }
            .padding(DesignTokens.Space.xl)
            if let validationError {
                Text(validationError).font(.system(size: DesignTokens.FontSize.caption))
                    .foregroundStyle(DesignTokens.statusError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DesignTokens.Space.xl)
            }
            Divider()
            toolbar
        }
        .frame(minWidth: 900, minHeight: 560)
        .background(DesignTokens.background)
    }

    private var previewPanel: some View {
        VStack {
            LivePreviewView(html: model.htmlText, templateDir: templateDir,
                            context: model.previewContext(data: previewData, stale: previewStale))
                .frame(width: (model.previewManifest()?.sizes.first ?? .small).pointSize.width,
                       height: (model.previewManifest()?.sizes.first ?? .small).pointSize.height)
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.preview).stroke(DesignTokens.separator, lineWidth: 1))
            if model.previewManifest() == nil {
                Text("manifest invalide — aperçu figé").font(.system(size: DesignTokens.FontSize.caption))
                    .foregroundStyle(DesignTokens.statusStale)
            }
        }
        .frame(maxWidth: .infinity)
        .task { await fetchPreviewData() }
    }

    private var toolbar: some View {
        HStack {
            Text(model.templateId).font(.system(size: DesignTokens.FontSize.label)).foregroundStyle(DesignTokens.textSecondary)
            Spacer()
            Button("Fermer", action: onClose)
            Button("Enregistrer") {
                switch model.validate() {
                case .success:
                    validationError = nil
                    try? model.save(into: state.templates)
                    Task { await fetchPreviewData() }
                case .failure(let e):
                    validationError = model.errorMessage(e)
                }
            }
            .buttonStyle(.borderedProminent).tint(DesignTokens.accent)
        }
        .padding(DesignTokens.Space.lg)
    }

    @MainActor private func fetchPreviewData() async {
        guard let manifest = model.previewManifest() else { return }
        // No instance/grants here: fetch free sources, mark consent-required as __denied.
        let allowed = manifest.sources.filter { !$0.requiresConsent }
        let denied = manifest.sources.filter { $0.requiresConsent }
        let result = await DataProviderRegistry.standard().fetchAll(sources: allowed, paramValues: [:])
        var data = result.data
        for s in denied { data[s.key] = ["__denied": true] }
        previewData = data
        previewStale = !result.failedKeys.isEmpty
    }
}
```

- [ ] **Step 4: Ajouter « Nouveau template » à `GalleryView.swift`**

Ajouter un `@State private var editingTemplateId: String?` et, en tête du `ScrollView` (avant la liste), un bouton :
```swift
            Button("Nouveau template") {
                editingTemplateId = state.templates.createUserTemplate(name: "Nouveau widget")
            }
            .buttonStyle(.borderedProminent).tint(DesignTokens.accent)
            .padding([.top, .horizontal], DesignTokens.Space.xxl)
```
et un modifier `.sheet(item: editingTemplateBinding) { id in TemplateCodeEditorView(state: state, templateId: id) { editingTemplateId = nil } }` où `editingTemplateBinding` adapte `String?` en `Identifiable` (créer un petit wrapper `struct EditingID: Identifiable { let id: String }` ou utiliser `.sheet(isPresented:)` avec un id capturé). Le plus simple : `struct IdentifiedString: Identifiable { let id: String }` et `@State editingTemplateId: IdentifiedString?`.

- [ ] **Step 5: Build**

Run: `xcodegen generate && xcodebuild build -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet` puis la suite de tests (93 inchangée).
Expected: `BUILD SUCCEEDED` + suite verte.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: advanced template code editor (tabs + live preview) with New Template entry"
```

---

### Task 5: Galerie « Forker » + « Supprimer » + vérification réelle bout-en-bout

**Files:**
- Modify: `BetterWidgets/App/GalleryView.swift`

**Interfaces:**
- Consumes: `TemplateStore` (`forkTemplate`, `deleteUserTemplate`, `isUserTemplate`), `TemplateCodeEditorView` (Task 4), `DesignTokens`.
- Produces: sur chaque carte de template de la Galerie :
  - action **« Forker »** → `let id = try? state.templates.forkTemplate(from: manifest.id)` → ouvre l'éditeur sur `id`.
  - action **« Supprimer »** (uniquement si `state.templates.isUserTemplate(id: manifest.id)`) → `confirmationDialog` → `deleteUserTemplate` + rafraîchir la liste.
  - action **« Éditer »** sur un template **utilisateur** → ouvre l'éditeur sur son id (édition en place).

- [ ] **Step 1: Invoquer `minimalist-ui`** pour les actions de carte (menu).

- [ ] **Step 2: Étendre `GalleryView.row(_:)`**

Remplacer le `Menu("Créer")` par un menu regroupant Créer (par taille) + les actions template. Ajouter pour chaque template :
```swift
            Menu {
                ForEach(manifest.sizes, id: \.self) { size in
                    Button("Créer — \(size.rawValue)") { onCreated(state.createInstance(templateId: manifest.id, size: size)) }
                }
                Divider()
                Button("Forker") {
                    if let id = try? state.templates.forkTemplate(from: manifest.id) {
                        editingTemplateId = IdentifiedString(id: id)
                    }
                }
                if state.templates.isUserTemplate(id: manifest.id) {
                    Button("Éditer le code") { editingTemplateId = IdentifiedString(id: manifest.id) }
                    Button("Supprimer", role: .destructive) { pendingDelete = manifest.id }
                }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize().tint(DesignTokens.accent)
```
Ajouter les états `@State private var pendingDelete: String?` + le `confirmationDialog` sur suppression :
```swift
        .confirmationDialog("Supprimer ce template ?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete) { id in
            Button("Supprimer", role: .destructive) { state.templates.deleteUserTemplate(id: id); pendingDelete = nil }
            Button("Annuler", role: .cancel) { pendingDelete = nil }
        } message: { _ in Text("Les widgets basés dessus afficheront un placeholder.") }
```
(La liste `templates` est un computed `state.templates.list()` re-évalué à chaque `body` — après suppression, un changement d'état force le refresh ; si nécessaire, ajouter un `@State private var refreshTick = 0` incrémenté après suppression et référencé dans `body` pour forcer la ré-évaluation.)

- [ ] **Step 3: Build + suite**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet` + `xcodebuild build ... -quiet`.
Expected: suite verte (93) + `BUILD SUCCEEDED`.

- [ ] **Step 4: Vérification réelle bout-en-bout**

```bash
xcodegen generate && xcodebuild build -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet
APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/BetterWidgets-*/Build/Products/Debug/*.app | head -1)
pkill -x BetterWidgets 2>/dev/null || true; sleep 1
open "$APP"; sleep 8
osascript -e 'tell application "System Events" to tell process "BetterWidgets" to set frontmost to true' 2>/dev/null || true
screencapture -x /tmp/bw-3b2-editor.png 2>/dev/null || true
ls -la /tmp/bw-3b2-editor.png 2>/dev/null || echo "screenshot not captured (screen may be locked)"
```
À vérifier (œil / capture) : Galerie → « Nouveau template » ouvre l'éditeur avec CodeMirror (coloration, numéros de ligne) ; taper du HTML → la preview se met à jour ; passer sur l'onglet manifest, mettre `sizes` à `[]` → Enregistrer refuse avec un message ; corriger → Enregistrer OK ; le nouveau template apparaît dans la Galerie et est instanciable (« Créer ») ; « Forker » un bundlé crée une copie éditable ; « Supprimer » un template utilisateur le retire (bundlés non supprimables). Rapport honnête si la capture échoue (écran verrouillé). Sauver `/tmp/bw-3b2-editor.png` — le contrôleur le relaiera.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: gallery fork/delete/edit actions for user templates"
```

---

## Self-review (fait à l'écriture)

- **Couverture spec** : §3 bundlé/utilisateur (marqueur `.user`) → Task 2 ; §4 archi éditeur → Tasks 1,4 ; §5 CodeMirror → Task 1 ; §6 preview (params=défauts, sources libres, `__denied` consent) → Task 4 ; §7 validation/save → Tasks 2,3,4 ; §8 écritures TemplateStore → Task 2 ; §9 sécurité (WebView confinée) → Tasks 1,4 (réutilise `TemplateAssetSchemeHandler`+`NavigationPolicy`) ; §10 erreurs (mapping FR, preview figée) → Tasks 3,4 ; §11 tests → Tasks 2,3 (unit) + 1,4,5 (build+réel) ; §12 spike en 1re tâche → Task 1.
- **Cohérence des types** : `CodeEditorBridge(text:language:assetsDir:)` défini Task 1, consommé Task 4 ; `TemplateEditorModel(templateId:store:)` défini Task 3, consommé Task 4 ; `TemplateStore.createUserTemplate/forkTemplate/saveTemplate/deleteUserTemplate/isUserTemplate` définis Task 2, consommés Tasks 4,5 ; `LivePreviewView(html:templateDir:context:)` réutilisé (3b-1) ; `RenderContext(params:data:size:theme:stale:)` (Plan 1) ; `TemplateAssetSchemeHandler.scheme`/`NavigationPolicy.decide` (Plan 2). `IdentifiedString: Identifiable` introduit en Task 4, réutilisé Task 5.
- **Placeholders** : aucun TODO/TBD ; code complet pour Tasks 2,3 (logique, TDD) ; Tasks 1,4,5 (WebView/vues) build-gated + vérif réelle, le spike (Task 1) documente explicitement son critère et le fallback BLOCKED.
- **Risque** : Task 1 (CodeMirror) isolé en premier ; le pont dans `CodeEditorBridge` seul → un fallback `TextEditor` ne toucherait que ce fichier + `CodeEditorView`.
- **Sécurité** : l'éditeur ET la preview réutilisent le confinement `bwasset://`+`NavigationPolicy` ; templates utilisateur sans privilège ; pas de secrets (notion d'instance, 3b-1).
