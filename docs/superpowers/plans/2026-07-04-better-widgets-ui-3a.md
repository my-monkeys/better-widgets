# Better Widgets — Plan 3a : Coquille d'app + « Mes widgets »

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Donner à Better Widgets une vraie fenêtre principale (navigation sidebar « Mes widgets » / « Galerie »), permettant de créer un widget depuis la galerie, de le voir rendu dans « Mes widgets » avec son statut, et de le dupliquer/supprimer — le tout dans un langage visuel éditorial minimal partagé.

**Architecture:** On ajoute un `WindowGroup` à côté du `MenuBarExtra` existant (app reste `LSUIElement`). `AppState` (source de vérité déjà en place) gagne le CRUD d'instances et devient injectable pour être testé. Les vues SwiftUI (MainWindow/MyWidgets/WidgetCard/Gallery) consomment `AppState` et un `DesignTokens` partagé. Deux prérequis techniques sont corrigés au passage : `Scheduler.restart` (dette « start-after-stop » de Plan 1) et `SharedStore.removeInstance`.

**Tech Stack:** Swift 5.9, SwiftUI (`NavigationSplitView`, `WindowGroup`, `MenuBarExtra`), AppKit (`NSApp.activate`, `NSColor` dynamic), XCTest, XcodeGen. macOS 14+, Xcode 27.

## Global Constraints

- **Direction artistique : éditorial minimal** (skill `minimalist-ui`) — mono chaud, typo hiérarchisée (≥ 3 tailles + contraste de poids), grille éditoriale, **un seul accent : orange `#e8590c`** (clair) / `#ff7a33` (sombre), espacements généreux. **Interdits** : gradients violet/bleu génériques, glassmorphism, ombres bleutées molles, `text-center` par flemme. L'implémenteur des tâches de vue **doit invoquer la skill `minimalist-ui`** avant d'écrire le SwiftUI.
- **App `LSUIElement`** : pas d'icône dock permanente ; la fenêtre est summonnée. Fermer la fenêtre ne quitte pas l'app (le scheduler continue).
- **Widget kinds immuables** `bw.small`/`bw.medium`/`bw.large` (déjà en place) — ne pas toucher.
- **Le `.xcodeproj` est généré** depuis `project.yml` (gitignoré) — nouveaux fichiers sous `BetterWidgets/App/**` et `BetterWidgets/Core/**` auto-inclus (l'app compile `BetterWidgets` en entier) ; ne jamais éditer le `.xcodeproj`. `xcodegen generate` avant chaque build.
- **Nouveaux fichiers de vue/état vont dans l'app uniquement** (l'extension ne compile que `Core/Models` + `Core/SharedStore.swift` — ne pas y ajouter d'UI).
- **Commande de test** : `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`. Point de départ : **61 tests verts**.
- Commits : Conventional Commits, auteur `MaximCosta <maxim@users.noreply.github.com>` (configuré), **aucune mention d'IA**.
- Code, commentaires, identifiants en **anglais** ; chaînes UI en **français**.
- Flake connu (non introduit ici) : `RenderEngineTests.testMediumSizeDimensions` (cold-start WKWebView) — si flake, relancer isolé, ne pas « corriger » en touchant les timeouts.

## Périmètre (rappel du spec `2026-07-04-better-widgets-ui-3a-design.md`)

Dans 3a : fenêtre + nav, Mes widgets (cartes preview PNG + statut + dupliquer/supprimer/ajouter-au-bureau ; Éditer présent mais **désactivé « bientôt »**), Galerie minimale (créer avec params par défaut), `DesignTokens`, CRUD `AppState`, `Scheduler.restart`, `SharedStore.removeInstance`. **Hors 3a** : édition de params + preview live + mode avancé (3b) ; import/export `.bwidget` + Keychain + consentement (3c) — **pas de bouton Importer en 3a**.

---

## Structure des fichiers

```
BetterWidgets/
├── App/
│   ├── BetterWidgetsApp.swift   # MODIF : + WindowGroup + item menu « Ouvrir »
│   ├── AppState.swift           # MODIF : injectable + CRUD + status(for:)
│   ├── MainWindowView.swift     # NOUVEAU : NavigationSplitView sidebar/detail
│   ├── MyWidgetsView.swift      # NOUVEAU : grille de cartes + état vide
│   ├── WidgetCard.swift         # NOUVEAU : carte (vue) + WidgetCardModel
│   ├── GalleryView.swift        # NOUVEAU : liste templates + créer
│   └── AddToDesktopGuide.swift  # NOUVEAU : sheet guide « poser sur le bureau »
├── Core/
│   ├── DesignTokens.swift       # NOUVEAU : couleurs/espacements/typo/statut
│   ├── Scheduler.swift          # MODIF : + restart(instances:) + InstanceScheduling
│   └── SharedStore.swift        # MODIF : + removeInstance(id:)
└── Tests/
    ├── SchedulerTests.swift        # MODIF : + test restart
    ├── SharedStoreTests.swift      # MODIF : + test removeInstance
    ├── AppStateTests.swift         # NOUVEAU : CRUD
    ├── DesignTokensTests.swift     # NOUVEAU : échelles
    └── WidgetCardModelTests.swift  # NOUVEAU : statut/thème→PNG
```

---

### Task 1: Prérequis CRUD — `Scheduler.restart` + `SharedStore.removeInstance`

**Files:**
- Modify: `BetterWidgets/Core/Scheduler.swift`
- Modify: `BetterWidgets/Core/SharedStore.swift`
- Test: `Tests/SchedulerTests.swift`
- Test: `Tests/SharedStoreTests.swift`

**Interfaces:**
- Consumes: `Scheduler` (Plan 1), `SharedStore` (Plan 1), `Theme`, `WidgetInstance`.
- Produces:
  - `@MainActor protocol InstanceScheduling { func restart(instances: [WidgetInstance]); func refreshAllNow(instances: [WidgetInstance]) }` + `extension Scheduler: InstanceScheduling {}`.
  - `Scheduler.restart(instances:)` — tears down timers + old stream/worker, recreates a fresh stream/worker, then `start(instances:)`. Fixes "enqueue after stop is a no-op".
  - `SharedStore.removeInstance(id: UUID)` — deletes `<id>-light.png`, `<id>-dark.png`, and `state/<id>.json` ; no-op if absent (never throws on missing files).

- [ ] **Step 1: Écrire le test de `restart` dans `Tests/SchedulerTests.swift`**

Ajouter à la classe existante (réutilise `CountingRefresher` + `TemplateStore` sur temp déjà présents dans le fichier) :

```swift
    @MainActor
    func testRestartAfterStopStillRefreshes() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let refresher = CountingRefresher()
        let scheduler = Scheduler(refresher: refresher, templates: TemplateStore(rootURL: tmp))
        scheduler.stop()                          // finish the initial stream/worker
        let a = WidgetInstance(id: UUID(), name: "a", templateId: "g", size: .small, paramValues: [:])
        scheduler.restart(instances: [a])         // must recreate the worker and refresh
        try await Task.sleep(for: .milliseconds(300))
        scheduler.stop()
        XCTAssertGreaterThanOrEqual(refresher.safeCount, 1, "restart must recreate the queue so enqueues run")
    }
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -only-testing:BetterWidgetsTests/SchedulerTests -quiet`
Expected: FAIL — `value of type 'Scheduler' has no member 'restart'`.

- [ ] **Step 3: Implémenter `restart` + le protocole dans `Scheduler.swift`**

Extraire la création du worker et ajouter `restart`. Remplacer le corps de `init` par un appel à `spawnWorker()` et ajouter les membres :

```swift
    init(refresher: any Refreshing, templates: TemplateStore) {
        self.refresher = refresher
        self.templates = templates
        spawnWorker()
    }

    private func spawnWorker() {
        let (stream, continuation) = AsyncStream.makeStream(of: WidgetInstance.self)
        queueContinuation = continuation
        worker = Task { [refresher] in
            for await instance in stream {
                await refresher.refresh(instance)
            }
        }
    }

    /// Tears down and recreates the serial queue, then starts timers/refreshes.
    /// Needed because `stop()` finishes the stream — a plain `start()` afterwards
    /// would enqueue into a dead continuation (no-op). Called on every instance-list change.
    func restart(instances: [WidgetInstance]) {
        stopTimers()
        queueContinuation?.finish()
        worker?.cancel()
        spawnWorker()
        start(instances: instances)
    }
```

Ajouter en bas du fichier :

```swift
@MainActor
protocol InstanceScheduling {
    func restart(instances: [WidgetInstance])
    func refreshAllNow(instances: [WidgetInstance])
}

extension Scheduler: InstanceScheduling {}
```

- [ ] **Step 4: Écrire le test `removeInstance` dans `Tests/SharedStoreTests.swift`**

```swift
    func testRemoveInstanceDeletesRendersAndState() throws {
        let id = UUID()
        try store.writeRender(Data("l".utf8), instanceId: id, theme: .light)
        try store.writeRender(Data("d".utf8), instanceId: id, theme: .dark)
        try store.saveState(InstanceState(stale: true), instanceId: id)

        store.removeInstance(id: id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.renderURL(instanceId: id, theme: .light).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.renderURL(instanceId: id, theme: .dark).path))
        XCTAssertEqual(store.loadState(instanceId: id), InstanceState()) // state file gone → default
    }

    func testRemoveInstanceIsNoOpWhenAbsent() {
        store.removeInstance(id: UUID()) // must not throw/crash
    }
```

(Note : `InstanceState(stale: true)` suppose le memberwise init ; si `InstanceState` a des defaults, `var s = InstanceState(); s.stale = true` — adapter au type réel vu dans `InstanceState.swift`.)

- [ ] **Step 5: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/SharedStoreTests -quiet`
Expected: FAIL — `value of type 'SharedStore' has no member 'removeInstance'`.

- [ ] **Step 6: Implémenter `removeInstance` dans `SharedStore.swift`**

Ajouter dans la section State (ou à la fin de la classe) :

```swift
    /// Deletes the two render PNGs and the state file for an instance. No-op if absent.
    func removeInstance(id: UUID) {
        let urls = [
            renderURL(instanceId: id, theme: .light),
            renderURL(instanceId: id, theme: .dark),
            stateURL.appendingPathComponent("\(id.uuidString).json"),
        ]
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }
```

(`stateURL` est déjà une propriété privée de `SharedStore` utilisée par `loadState`/`saveState`.)

- [ ] **Step 7: Vérifier que tout passe**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: PASS (61 + 3 nouveaux).

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat: scheduler restart + shared-store removeInstance (crud prerequisites)"
```

---

### Task 2: `DesignTokens` — langage visuel partagé

**Files:**
- Create: `BetterWidgets/Core/DesignTokens.swift`
- Test: `Tests/DesignTokensTests.swift`

**Interfaces:**
- Consumes: SwiftUI `Color`, AppKit `NSColor`.
- Produces:
  - `enum DesignTokens` avec :
    - Couleurs adaptatives (clair/sombre) : `background`, `surface`, `textPrimary`, `textSecondary`, `separator`, `accent`, `statusOK`, `statusStale`, `statusError` (toutes `static let ... : Color`).
    - `enum Space { static let xs=4.0, sm=8.0, md=12.0, lg=16.0, xl=24.0, xxl=40.0, section=80.0 }` (CGFloat).
    - `enum FontSize { static let caption=11.0, label=13.0, title=18.0, titleXL=28.0 }` (CGFloat).
    - `static func statusColor(_ status: InstanceStatus) -> Color` (mappe ok→statusOK, stale→statusStale, error→statusError). `InstanceStatus` est défini en Task 3 ; **cette fonction est ajoutée en Task 3** (voir note). En Task 2, ne fournir QUE les couleurs + échelles.
  - Helper `static func adaptive(light: NSColor, dark: NSColor) -> Color`.

- [ ] **Step 1: Écrire `Tests/DesignTokensTests.swift` (échoue)**

```swift
import XCTest
import SwiftUI

final class DesignTokensTests: XCTestCase {
    func testSpacingScaleIsMonotonic() {
        let scale = [DesignTokens.Space.xs, DesignTokens.Space.sm, DesignTokens.Space.md,
                     DesignTokens.Space.lg, DesignTokens.Space.xl, DesignTokens.Space.xxl,
                     DesignTokens.Space.section]
        XCTAssertEqual(scale, scale.sorted(), "spacing scale must increase")
        XCTAssertEqual(DesignTokens.Space.lg, 16)
    }

    func testTypeScaleHasDistinctSizes() {
        let sizes = Set([DesignTokens.FontSize.caption, DesignTokens.FontSize.label,
                         DesignTokens.FontSize.title, DesignTokens.FontSize.titleXL])
        XCTAssertEqual(sizes.count, 4, "≥ 3 distinct type sizes required")
        XCTAssertGreaterThan(DesignTokens.FontSize.titleXL, DesignTokens.FontSize.title)
    }

    func testAccentIsDefined() {
        XCTAssertNotNil(DesignTokens.accent)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/DesignTokensTests -quiet`
Expected: FAIL — `cannot find 'DesignTokens' in scope`.

- [ ] **Step 3: Implémenter `DesignTokens.swift`**

```swift
import SwiftUI
import AppKit

/// Shared visual language (editorial minimal): warm monochrome + a single orange accent.
/// Single source of truth for 3a/3b/3c so screens stay consistent.
enum DesignTokens {
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    static let background = adaptive(light: hex(0xFAF8F4), dark: hex(0x16130E))
    static let surface    = adaptive(light: hex(0xFFFFFF), dark: hex(0x201C16))
    static let textPrimary   = adaptive(light: hex(0x1A1A1A), dark: hex(0xF0ECE4))
    static let textSecondary = adaptive(light: hex(0x6B6560), dark: hex(0xA8A199))
    static let separator = adaptive(light: NSColor.black.withAlphaComponent(0.10),
                                    dark: NSColor.white.withAlphaComponent(0.12))
    static let accent     = adaptive(light: hex(0xE8590C), dark: hex(0xFF7A33))
    static let statusOK    = adaptive(light: hex(0x2F9E44), dark: hex(0x51CF66))
    static let statusStale = adaptive(light: hex(0xF08C00), dark: hex(0xFFA94D))
    static let statusError = adaptive(light: hex(0xE03131), dark: hex(0xFF6B6B))

    enum Space {
        static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12, lg: CGFloat = 16
        static let xl: CGFloat = 24, xxl: CGFloat = 40, section: CGFloat = 80
    }

    enum FontSize {
        static let caption: CGFloat = 11, label: CGFloat = 13, title: CGFloat = 18, titleXL: CGFloat = 28
    }
}
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/DesignTokensTests -quiet`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: DesignTokens — shared editorial-minimal visual language"
```

---

### Task 3: `AppState` injectable + CRUD d'instances + `InstanceStatus`

**Files:**
- Modify: `BetterWidgets/App/AppState.swift`
- Modify: `BetterWidgets/Core/DesignTokens.swift` (ajoute `statusColor`)
- Test: `Tests/AppStateTests.swift`

**Interfaces:**
- Consumes: `SharedStore`, `TemplateStore`, `PermissionStore`, `RenderPipeline`, `RenderEngine`, `WidgetCenterReloader`, `Scheduler`, `InstanceScheduling` (Task 1), `WidgetInstance`, `WidgetSize`, `InstanceState`.
- Produces:
  - `enum InstanceStatus: Equatable { case ok, stale, error(String) }`
  - `AppState` refactoré : `init(shared:templates:scheduler:)` (désigné, injectable) + `convenience init()` (câblage réel). Propriétés publiques `shared: SharedStore`, `templates: TemplateStore`. Le `scheduler` devient `any InstanceScheduling` (privé).
  - `func createInstance(templateId: String, size: WidgetSize) -> WidgetInstance` (nom = `manifest.name` ou templateId ; paramValues vides ; persiste + `scheduler.restart` + refresh).
  - `func deleteInstance(_ id: UUID)` (retire + persiste + `shared.removeInstance(id:)` + `scheduler.restart`).
  - `func duplicateInstance(_ id: UUID) -> WidgetInstance?` (nouvel id, nom « <nom> (copie) », mêmes size/params ; persiste + restart + refresh).
  - `func status(for id: UUID) -> InstanceStatus`.
  - `bootstrap()` utilise `scheduler.restart(instances:)` (au lieu de `start`).

- [ ] **Step 1: Écrire `Tests/AppStateTests.swift` (échoue)**

```swift
import XCTest

@MainActor
final class AppStateTests: XCTestCase {
    private var tmp: URL!
    private var shared: SharedStore!
    private var templates: TemplateStore!

    final class SpyScheduler: InstanceScheduling {
        var restarted: [[WidgetInstance]] = []
        var refreshed: [[WidgetInstance]] = []
        func restart(instances: [WidgetInstance]) { restarted.append(instances) }
        func refreshAllNow(instances: [WidgetInstance]) { refreshed.append(instances) }
    }

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        shared = try SharedStore(baseURL: tmp.appendingPathComponent("shared"))
        let tplRoot = tmp.appendingPathComponent("templates")
        try FileManager.default.createDirectory(at: tplRoot.appendingPathComponent("hello-clock"),
                                                withIntermediateDirectories: true)
        try #"{ "id": "hello-clock", "name": "Horloge", "version": "1.0.0", "sizes": ["small","medium"], "refresh": 60, "params": [], "sources": [] }"#
            .write(to: tplRoot.appendingPathComponent("hello-clock/manifest.json"), atomically: true, encoding: .utf8)
        try "<html></html>".write(to: tplRoot.appendingPathComponent("hello-clock/index.html"),
                                  atomically: true, encoding: .utf8)
        templates = TemplateStore(rootURL: tplRoot)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func makeState() -> (AppState, SpyScheduler) {
        let spy = SpyScheduler()
        return (AppState(shared: shared, templates: templates, scheduler: spy), spy)
    }

    func testCreateInstanceUsesTemplateNameAndPersists() {
        let (state, spy) = makeState()
        let created = state.createInstance(templateId: "hello-clock", size: .medium)
        XCTAssertEqual(created.name, "Horloge")
        XCTAssertEqual(created.size, .medium)
        XCTAssertTrue(state.instances.contains(created))
        XCTAssertEqual(shared.loadInstances(), state.instances)  // persisted
        XCTAssertEqual(spy.restarted.last, state.instances)      // scheduler restarted with new list
    }

    func testDeleteInstanceRemovesAndCleansStore() throws {
        let (state, spy) = makeState()
        let a = state.createInstance(templateId: "hello-clock", size: .small)
        try shared.writeRender(Data("x".utf8), instanceId: a.id, theme: .light)
        state.deleteInstance(a.id)
        XCTAssertFalse(state.instances.contains(a))
        XCTAssertEqual(shared.loadInstances(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: shared.renderURL(instanceId: a.id, theme: .light).path))
        XCTAssertEqual(spy.restarted.last, [])
    }

    func testDuplicateInstance() {
        let (state, _) = makeState()
        let a = state.createInstance(templateId: "hello-clock", size: .small)
        let dup = state.duplicateInstance(a.id)
        XCTAssertNotNil(dup)
        XCTAssertNotEqual(dup!.id, a.id)
        XCTAssertEqual(dup!.name, "Horloge (copie)")
        XCTAssertEqual(dup!.size, a.size)
        XCTAssertEqual(state.instances.count, 2)
    }

    func testStatusMapping() throws {
        let (state, _) = makeState()
        let a = state.createInstance(templateId: "hello-clock", size: .small)
        XCTAssertEqual(state.status(for: a.id), .ok)
        var s = InstanceState(); s.stale = true
        try shared.saveState(s, instanceId: a.id)
        XCTAssertEqual(state.status(for: a.id), .stale)
        var e = InstanceState(); e.lastError = "boom"
        try shared.saveState(e, instanceId: a.id)
        XCTAssertEqual(state.status(for: a.id), .error("boom"))
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/AppStateTests -quiet`
Expected: FAIL — `AppState` n'a pas d'init `init(shared:templates:scheduler:)`.

- [ ] **Step 3: Réécrire `AppState.swift`**

```swift
import Foundation
import SwiftUI

enum InstanceStatus: Equatable {
    case ok, stale, error(String)
}

@MainActor
final class AppState: ObservableObject {
    @Published var instances: [WidgetInstance] = []

    let shared: SharedStore
    let templates: TemplateStore
    private let scheduler: any InstanceScheduling

    /// Designated init — injectable for tests.
    init(shared: SharedStore, templates: TemplateStore, scheduler: any InstanceScheduling) {
        self.shared = shared
        self.templates = templates
        self.scheduler = scheduler
    }

    /// Real wiring used by the app.
    convenience init() {
        let shared = SharedStore.appGroup()
        let templates = TemplateStore.applicationSupport()
        let permissions = PermissionStore.appGroup()
        let pipeline = RenderPipeline(templates: templates, shared: shared, permissions: permissions,
                                      registry: .standard(), engine: RenderEngine(),
                                      reloader: WidgetCenterReloader())
        self.init(shared: shared, templates: templates,
                  scheduler: Scheduler(refresher: pipeline, templates: templates))
    }

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
        scheduler.restart(instances: instances)
    }

    func refreshAll() {
        scheduler.refreshAllNow(instances: instances)
    }

    // MARK: CRUD

    func createInstance(templateId: String, size: WidgetSize) -> WidgetInstance {
        let name = (try? templates.manifest(id: templateId).name) ?? templateId
        let instance = WidgetInstance(id: UUID(), name: name, templateId: templateId,
                                      size: size, paramValues: [:])
        instances.append(instance)
        persistAndReschedule()
        return instance
    }

    func deleteInstance(_ id: UUID) {
        instances.removeAll { $0.id == id }
        shared.removeInstance(id: id)
        persistAndReschedule()
    }

    @discardableResult
    func duplicateInstance(_ id: UUID) -> WidgetInstance? {
        guard let original = instances.first(where: { $0.id == id }) else { return nil }
        let copy = WidgetInstance(id: UUID(), name: "\(original.name) (copie)",
                                  templateId: original.templateId, size: original.size,
                                  paramValues: original.paramValues)
        instances.append(copy)
        persistAndReschedule()
        return copy
    }

    func status(for id: UUID) -> InstanceStatus {
        let state = shared.loadState(instanceId: id)
        if let error = state.lastError { return .error(error) }
        if state.stale { return .stale }
        return .ok
    }

    private func persistAndReschedule() {
        try? shared.saveInstances(instances)
        scheduler.restart(instances: instances)
    }
}
```

Note : le `statusLine(for:)` de Plan 1 (utilisé par le `MenuBarExtra`) est **supprimé** — le menu bar sera mis à jour en Task 7 pour utiliser `status(for:)`. Si tu exécutes les tâches dans l'ordre, garde `statusLine` temporairement pour ne pas casser `BetterWidgetsApp.swift`, OU mets à jour le menu bar ici (Step 4). Choix du plan : **garder `statusLine` en Task 3** (le menu bar compile inchangé), le retirer en Task 7.

- [ ] **Step 3b: Conserver `statusLine` pour ne pas casser le build**

Ré-ajouter à `AppState` (identique à Plan 1) pour que `BetterWidgetsApp.swift` compile jusqu'à la Task 7 :

```swift
    func statusLine(for instance: WidgetInstance) -> String {
        switch status(for: instance.id) {
        case .error(let msg): return "⚠︎ \(instance.name) — \(msg.prefix(40))"
        case .stale: return "◔ \(instance.name) — données périmées"
        case .ok: return "● \(instance.name)"
        }
    }
```

- [ ] **Step 4: Ajouter `statusColor` à `DesignTokens.swift`**

```swift
    static func statusColor(_ status: InstanceStatus) -> Color {
        switch status {
        case .ok: return statusOK
        case .stale: return statusStale
        case .error: return statusError
        }
    }
```

- [ ] **Step 5: Vérifier que tout passe**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: PASS (AppStateTests + suite). Le build de l'app doit rester vert (`statusLine` conservé).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: injectable AppState with instance CRUD + status"
```

---

### Task 4: `WidgetCardModel` + `WidgetCard` (vue)

**Files:**
- Create: `BetterWidgets/App/WidgetCard.swift` (contient `WidgetCardModel` + `WidgetCard`)
- Test: `Tests/WidgetCardModelTests.swift`

**Interfaces:**
- Consumes: `WidgetInstance`, `WidgetSize`, `InstanceStatus`, `Theme`, `SharedStore`, `DesignTokens`.
- Produces:
  - `struct WidgetCardModel { let instance: WidgetInstance; let status: InstanceStatus; let rendersDir: (UUID, Theme) -> URL; func imageURL(dark: Bool) -> URL; var statusLabel: String; var cardWidth: CGFloat }`
    - `imageURL(dark:)` → `rendersDir(instance.id, dark ? .dark : .light)`.
    - `statusLabel` → « À jour » / « Données périmées » / « Erreur ».
    - `cardWidth` → 170 (small) / 340 (medium/large) — proportionnel à la taille du widget.
  - `struct WidgetCard: View` — affiche l'image (via `NSImage(contentsOf:)`, placeholder si absent), le nom (`FontSize.title`), la pastille de statut (`DesignTokens.statusColor`), et un menu d'actions (Dupliquer, Supprimer, Ajouter au bureau, Éditer désactivé). Callbacks : `onDuplicate`, `onDelete`, `onAddToDesktop`.

- [ ] **Step 1: Écrire `Tests/WidgetCardModelTests.swift` (échoue)**

```swift
import XCTest

final class WidgetCardModelTests: XCTestCase {
    private func model(_ status: InstanceStatus, size: WidgetSize = .small) -> WidgetCardModel {
        let inst = WidgetInstance(id: UUID(), name: "T", templateId: "x", size: size, paramValues: [:])
        return WidgetCardModel(instance: inst, status: status,
                               rendersDir: { id, theme in
                                   URL(fileURLWithPath: "/tmp/\(id.uuidString)-\(theme.rawValue).png")
                               })
    }

    func testImageURLByTheme() {
        let m = model(.ok)
        XCTAssertTrue(m.imageURL(dark: false).lastPathComponent.hasSuffix("-light.png"))
        XCTAssertTrue(m.imageURL(dark: true).lastPathComponent.hasSuffix("-dark.png"))
    }

    func testStatusLabels() {
        XCTAssertEqual(model(.ok).statusLabel, "À jour")
        XCTAssertEqual(model(.stale).statusLabel, "Données périmées")
        XCTAssertEqual(model(.error("x")).statusLabel, "Erreur")
    }

    func testCardWidthBySize() {
        XCTAssertEqual(model(.ok, size: .small).cardWidth, 170)
        XCTAssertEqual(model(.ok, size: .medium).cardWidth, 340)
        XCTAssertEqual(model(.ok, size: .large).cardWidth, 340)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/WidgetCardModelTests -quiet`
Expected: FAIL — `cannot find 'WidgetCardModel' in scope`.

- [ ] **Step 3: Invoquer la skill `minimalist-ui`** avant d'écrire le SwiftUI de la carte (respect DA).

- [ ] **Step 4: Implémenter `WidgetCard.swift`**

```swift
import SwiftUI

struct WidgetCardModel {
    let instance: WidgetInstance
    let status: InstanceStatus
    let rendersDir: (UUID, Theme) -> URL

    func imageURL(dark: Bool) -> URL { rendersDir(instance.id, dark ? .dark : .light) }

    var statusLabel: String {
        switch status {
        case .ok: return "À jour"
        case .stale: return "Données périmées"
        case .error: return "Erreur"
        }
    }

    var cardWidth: CGFloat { instance.size == .small ? 170 : 340 }
}

struct WidgetCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let model: WidgetCardModel
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onAddToDesktop: () -> Void

    private var image: NSImage? {
        NSImage(contentsOf: model.imageURL(dark: colorScheme == .dark))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.sm) {
            preview
            HStack(spacing: DesignTokens.Space.sm) {
                Circle().fill(DesignTokens.statusColor(model.status)).frame(width: 7, height: 7)
                Text(model.instance.name).font(.system(size: DesignTokens.FontSize.title, weight: .semibold))
                Spacer()
                actions
            }
            Text(model.statusLabel)
                .font(.system(size: DesignTokens.FontSize.caption))
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(DesignTokens.Space.lg)
        .frame(width: model.cardWidth + DesignTokens.Space.lg * 2, alignment: .leading)
        .background(DesignTokens.surface)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DesignTokens.separator, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var preview: some View {
        let ratio: CGFloat = model.instance.size == .large ? 382.0 / 364.0 : (model.instance.size == .medium ? 170.0 / 364.0 : 1)
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                DesignTokens.background
                Text("rendu en cours…")
                    .font(.system(size: DesignTokens.FontSize.caption))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
        .frame(width: model.cardWidth, height: model.cardWidth * ratio)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var actions: some View {
        Menu {
            Button("Éditer") {}.disabled(true)  // 3b
            Button("Dupliquer", action: onDuplicate)
            Button("Ajouter au bureau…", action: onAddToDesktop)
            Divider()
            Button("Supprimer", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis.circle").foregroundStyle(DesignTokens.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
```

- [ ] **Step 5: Vérifier tests + build**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: PASS (WidgetCardModelTests + suite ; l'app build avec la nouvelle vue même si pas encore affichée).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: WidgetCard view + testable card model"
```

---

### Task 5: `MyWidgetsView` + `AddToDesktopGuide`

**Files:**
- Create: `BetterWidgets/App/MyWidgetsView.swift`
- Create: `BetterWidgets/App/AddToDesktopGuide.swift`

**Interfaces:**
- Consumes: `AppState` (`@ObservedObject`/`@EnvironmentObject`), `WidgetCard`, `WidgetCardModel`, `DesignTokens`, `SharedStore.renderURL`.
- Produces:
  - `struct MyWidgetsView: View` — grille (`LazyVGrid`) de `WidgetCard` pour `state.instances` ; état vide éditorial avec CTA ; gère la confirmation de suppression (`confirmationDialog`) et la présentation de `AddToDesktopGuide` (`.sheet`).
  - `struct AddToDesktopGuide: View` — contenu de sheet expliquant « clic droit sur le bureau → Modifier les widgets → chercher Better Widget → poser → clic droit → choisir ce widget », avec un bouton Fermer.
- Pas de test unitaire (vues SwiftUI) ; vérifié au build ici, visuellement en Task 7.

- [ ] **Step 1: Invoquer la skill `minimalist-ui`** avant d'écrire le SwiftUI.

- [ ] **Step 2: Implémenter `AddToDesktopGuide.swift`**

```swift
import SwiftUI

struct AddToDesktopGuide: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.lg) {
            Text("Ajouter au bureau")
                .font(.system(size: DesignTokens.FontSize.titleXL, weight: .bold))
                .foregroundStyle(DesignTokens.textPrimary)
            Text("macOS ne permet pas de poser un widget à ta place. En trois gestes :")
                .foregroundStyle(DesignTokens.textSecondary)
            VStack(alignment: .leading, spacing: DesignTokens.Space.md) {
                step(1, "Clic droit sur le bureau → « Modifier les widgets ».")
                step(2, "Cherche « Better Widget » et fais-le glisser à la taille voulue.")
                step(3, "Clic droit sur le widget posé → « Modifier le widget » → choisis celui-ci.")
            }
            HStack {
                Spacer()
                Button("Fermer", action: onClose).buttonStyle(.borderedProminent).tint(DesignTokens.accent)
            }
        }
        .padding(DesignTokens.Space.xxl)
        .frame(width: 440)
        .background(DesignTokens.background)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Space.md) {
            Text("\(n)").font(.system(size: DesignTokens.FontSize.label, weight: .bold))
                .foregroundStyle(DesignTokens.accent)
            Text(text).foregroundStyle(DesignTokens.textPrimary)
        }
    }
}
```

- [ ] **Step 3: Implémenter `MyWidgetsView.swift`**

```swift
import SwiftUI

struct MyWidgetsView: View {
    @ObservedObject var state: AppState
    @State private var pendingDelete: WidgetInstance?
    @State private var guideShown = false

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: DesignTokens.Space.xl)]

    var body: some View {
        Group {
            if state.instances.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: DesignTokens.Space.xl) {
                        ForEach(state.instances) { instance in
                            WidgetCard(
                                model: WidgetCardModel(instance: instance,
                                                       status: state.status(for: instance.id),
                                                       rendersDir: state.shared.renderURL),
                                onDuplicate: { _ = state.duplicateInstance(instance.id) },
                                onDelete: { pendingDelete = instance },
                                onAddToDesktop: { guideShown = true })
                        }
                    }
                    .padding(DesignTokens.Space.xxl)
                }
            }
        }
        .background(DesignTokens.background)
        .confirmationDialog("Supprimer ce widget ?", isPresented: .constant(pendingDelete != nil),
                            presenting: pendingDelete) { instance in
            Button("Supprimer « \(instance.name) »", role: .destructive) {
                state.deleteInstance(instance.id); pendingDelete = nil
            }
            Button("Annuler", role: .cancel) { pendingDelete = nil }
        }
        .sheet(isPresented: $guideShown) { AddToDesktopGuide { guideShown = false } }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.md) {
            Text("Aucun widget").font(.system(size: DesignTokens.FontSize.titleXL, weight: .bold))
                .foregroundStyle(DesignTokens.textPrimary)
            Text("Crée ton premier widget depuis la Galerie.")
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(DesignTokens.Space.section)
        .background(DesignTokens.background)
    }
}
```

Note : `renderURL` a la signature `(instanceId: UUID, theme: Theme) -> URL` mais `WidgetCardModel.rendersDir` attend `(UUID, Theme) -> URL` — les labels d'argument diffèrent. Passer `state.shared.renderURL` fonctionne (les labels ne font pas partie du type de fonction stocké). Si le compilateur râle, wrapper : `rendersDir: { id, theme in state.shared.renderURL(instanceId: id, theme: theme) }`.

- [ ] **Step 4: Vérifier le build**

Run: `xcodegen generate && xcodebuild build -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: MyWidgets grid + add-to-desktop guide sheet"
```

---

### Task 6: `GalleryView` (liste des templates + créer)

**Files:**
- Create: `BetterWidgets/App/GalleryView.swift`

**Interfaces:**
- Consumes: `AppState` (`state.templates.list()` → `[TemplateManifest]`, `state.createInstance`), `TemplateManifest` (`id`, `name`, `sizes`, `sources`), `WidgetSize`, `DesignTokens`.
- Produces: `struct GalleryView: View` — pour chaque template : nom, badges des tailles + des types de sources, bouton « Créer » ouvrant un menu de tailles (`manifest.sizes`) → `state.createInstance(templateId:size:)`. Callback `onCreated: (WidgetInstance) -> Void` pour permettre à la fenêtre de basculer sur « Mes widgets » après création. État vide si aucun template.
- Pas de test unitaire (vue) ; build vérifié ici, visuel en Task 7.

- [ ] **Step 1: Invoquer la skill `minimalist-ui`** avant d'écrire le SwiftUI.

- [ ] **Step 2: Implémenter `GalleryView.swift`**

```swift
import SwiftUI

struct GalleryView: View {
    @ObservedObject var state: AppState
    var onCreated: (WidgetInstance) -> Void = { _ in }

    private var templates: [TemplateManifest] { state.templates.list() }

    var body: some View {
        ScrollView {
            if templates.isEmpty {
                Text("Aucun template disponible.")
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                VStack(alignment: .leading, spacing: DesignTokens.Space.lg) {
                    ForEach(templates, id: \.id) { manifest in
                        row(manifest)
                    }
                }
                .padding(DesignTokens.Space.xxl)
            }
        }
        .background(DesignTokens.background)
    }

    private func row(_ manifest: TemplateManifest) -> some View {
        HStack(alignment: .center, spacing: DesignTokens.Space.lg) {
            VStack(alignment: .leading, spacing: DesignTokens.Space.xs) {
                Text(manifest.name).font(.system(size: DesignTokens.FontSize.title, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                HStack(spacing: DesignTokens.Space.sm) {
                    ForEach(manifest.sizes, id: \.self) { badge($0.rawValue) }
                    ForEach(manifest.sources, id: \.key) { badge($0.type) }
                }
            }
            Spacer()
            Menu("Créer") {
                ForEach(manifest.sizes, id: \.self) { size in
                    Button(size.rawValue) { onCreated(state.createInstance(templateId: manifest.id, size: size)) }
                }
            }
            .menuStyle(.borderlessButton).fixedSize()
            .tint(DesignTokens.accent)
        }
        .padding(DesignTokens.Space.lg)
        .background(DesignTokens.surface)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DesignTokens.separator, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(.system(size: DesignTokens.FontSize.caption))
            .padding(.horizontal, DesignTokens.Space.sm).padding(.vertical, DesignTokens.Space.xs)
            .foregroundStyle(DesignTokens.textSecondary)
            .overlay(Capsule().stroke(DesignTokens.separator, lineWidth: 1))
    }
}
```

- [ ] **Step 3: Vérifier le build**

Run: `xcodegen generate && xcodebuild build -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: minimal gallery — list bundled templates and create instances"
```

---

### Task 7: `MainWindowView` + `WindowGroup` + ouverture depuis le menu bar + vérif réelle

**Files:**
- Create: `BetterWidgets/App/MainWindowView.swift`
- Modify: `BetterWidgets/App/BetterWidgetsApp.swift`

**Interfaces:**
- Consumes: `AppState`, `MyWidgetsView`, `GalleryView`, `DesignTokens`.
- Produces:
  - `struct MainWindowView: View` — `NavigationSplitView` : sidebar avec deux entrées sélectionnables (`enum Section { case myWidgets, gallery }`), detail = `MyWidgetsView` ou `GalleryView`. Après création depuis la galerie (`onCreated`), bascule la sélection sur `.myWidgets`.
  - `BetterWidgetsApp` : ajoute `WindowGroup { MainWindowView(state: state) }` (id « main ») + un item de menu bar « Ouvrir Better Widgets » qui active l'app et ouvre la fenêtre.

- [ ] **Step 1: Invoquer la skill `minimalist-ui`** avant d'écrire le SwiftUI de la sidebar.

- [ ] **Step 2: Implémenter `MainWindowView.swift`**

```swift
import SwiftUI

struct MainWindowView: View {
    @ObservedObject var state: AppState

    enum Section: Hashable { case myWidgets, gallery }
    @State private var selection: Section = .myWidgets

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Mes widgets", systemImage: "square.grid.2x2").tag(Section.myWidgets)
                Label("Galerie", systemImage: "sparkles").tag(Section.gallery)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .tint(DesignTokens.accent)
        } detail: {
            switch selection {
            case .myWidgets: MyWidgetsView(state: state)
            case .gallery: GalleryView(state: state) { _ in selection = .myWidgets }
            }
        }
        .navigationTitle("Better Widgets")
        .frame(minWidth: 720, minHeight: 480)
    }
}
```

- [ ] **Step 3: Mettre à jour `BetterWidgetsApp.swift`**

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
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindowView(state: state)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra("Better Widgets", systemImage: "square.grid.2x2") {
            Button("Ouvrir Better Widgets") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            Divider()
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

(`statusLine` de Task 3 reste utilisé ici — on le garde.)

- [ ] **Step 4: Build + test complet**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: PASS (toute la suite).

- [ ] **Step 5: Vérification réelle (screenshots)**

Builder et lancer l'app, ouvrir la fenêtre, et vérifier le parcours. Prendre des captures pour preuve :

```bash
xcodegen generate && xcodebuild build -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet
APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/BetterWidgets-*/Build/Products/Debug/*.app | head -1)
pkill -x BetterWidgets 2>/dev/null || true; sleep 1
open "$APP"; sleep 8
# Ouvrir la fenêtre via l'item de menu bar se fait à la main ; sinon forcer :
osascript -e 'tell application "System Events" to tell process "BetterWidgets" to set frontmost to true' 2>/dev/null || true
screencapture -x /tmp/bw-3a-window.png 2>/dev/null || true
```

À vérifier visuellement (capture + œil) : la fenêtre s'ouvre avec la sidebar (Mes widgets / Galerie) ; « Mes widgets » montre au moins l'instance de démo « Horloge » avec son rendu et une pastille de statut ; la Galerie liste les templates bundlés (hello-clock, feed-list, agenda, weather-now) avec badges + bouton Créer ; créer un widget le fait apparaître dans Mes widgets ; dupliquer/supprimer fonctionnent ; « Ajouter au bureau… » ouvre la fiche-guide. Joindre `/tmp/bw-3a-window.png` au rapport (ou décrire précisément si la capture d'écran headless échoue — l'important est le parcours fonctionnel + la conformité DA).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: main window with sidebar navigation + open-from-menu-bar"
```

---

## Self-review (fait à l'écriture)

- **Couverture spec** : §3 archi/fenêtre → Tasks 7 ; §4 CRUD AppState + Scheduler.restart → Tasks 1,3 ; §5 Mes widgets/cartes/statut/actions → Tasks 4,5 ; §6 Galerie minimale → Task 6 ; §7 DesignTokens → Task 2 ; §8 erreurs (confirm suppression, guide, état vide) → Tasks 5,6 ; §9 tests (AppState CRUD, Scheduler.restart, view-model carte, removeInstance) → Tasks 1,3,4 ; vérif réelle → Task 7 Step 5.
- **Cohérence des types** : `InstanceStatus` défini en Task 3, consommé par `DesignTokens.statusColor` (Task 3 Step 4), `WidgetCardModel` (Task 4), `AppState.status(for:)` (Task 3) ; `InstanceScheduling` défini Task 1, consommé par `AppState` (Task 3) + spy de test ; `WidgetCardModel(instance:status:rendersDir:)` cohérent entre Task 4 (def) et Task 5 (usage) ; `renderURL(instanceId:theme:)` passé comme `(UUID,Theme)->URL` (note d'ambiguïté de labels traitée en Task 5). `bootstrap` passe de `start` à `restart` (Task 3) — le `Scheduler.start` reste (utilisé par les tests Plan 1 + en interne par `restart`).
- **Placeholders** : aucun TODO/TBD ; tout le code des steps est complet. Les vues SwiftUI (Tasks 5,6,7) n'ont pas de test unitaire (rendu) → vérif build à chaque tâche + vérif réelle en Task 7 ; les modèles/logique (Tasks 1,3,4) sont testés unitairement en TDD.
- **DA** : chaque tâche de vue impose d'invoquer `minimalist-ui` avant d'écrire le SwiftUI ; tokens centralisés (Task 2) ; interdits rappelés en Global Constraints.
- **Note d'exécution** : `statusLine` (Plan 1) est conservé (Task 3 Step 3b) pour que le menu bar compile jusqu'à la Task 7, où le menu bar est réécrit mais continue de l'utiliser — pas de suppression, donc pas de rupture.
