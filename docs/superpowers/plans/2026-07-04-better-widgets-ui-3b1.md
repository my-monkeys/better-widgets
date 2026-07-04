# Better Widgets — Plan 3b-1 : Éditeur de params + preview live + secrets Keychain

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Activer le bouton « Éditer » d'un widget : ouvrir un éditeur où l'on ajuste les params du template (formulaire généré du manifest) en voyant une **preview live** se mettre à jour, et où l'on saisit les **secrets d'API** (sources `json`) stockés dans le Keychain — jamais sur disque en clair.

**Architecture:** Un `WidgetEditorView` (feuille modale) piloté par un `WidgetEditorModel` (copie de travail des params/secrets). La preview est une **WKWebView vivante** réutilisant le contrat `window.BW` + le confinement `bwasset://` du moteur. Les secrets sont abstraits derrière `SecretResolver` (backing Keychain en prod, mémoire en test) ; ils sont résolus en en-têtes HTTPS **dans `RenderPipeline`** (qui détient l'instanceId), laissant le protocole `DataProvider` de Plan 2 intact.

**Tech Stack:** Swift 5.9, SwiftUI, WebKit (WKWebView live via `NSViewRepresentable`), Security (Keychain `SecItem`), XCTest, XcodeGen. macOS 14+, Xcode 27.

## Global Constraints

- **DA éditoriale minimale** (`DesignTokens`) ; **invoquer `minimalist-ui`** avant toute vue. Tout style vient de `DesignTokens` (couleurs/Space/FontSize/Radius) — pas de valeurs en dur.
- **Secrets jamais en clair sur disque** : uniquement Keychain ↔ mémoire éditeur ↔ en-tête HTTPS. Jamais dans `instances.json` ni un futur export `.bwidget`.
- **Convention secret** : une source `json` déclare un secret par une clé de config `secret.<Header>` (ex. `secret.Authorization`), distincte de `header.<Name>` (en-tête non secret, déjà géré par `JSONDataProvider`).
- **Le protocole `DataProvider` ne change pas** : la résolution des secrets se fait dans `RenderPipeline` en transformant `secret.<H>` → `header.<H>` avant `fetchAll`.
- **Le `.xcodeproj` est généré** : nouveaux fichiers `Core/**` auto-inclus dans app+tests ; nouveaux fichiers `App/**` dans l'app (les fichiers de logique testés — ex. `WidgetEditorModel.swift` — doivent être ajoutés **individuellement** aux sources `BetterWidgetsTests` de `project.yml`, comme `AppState.swift`/`WidgetCard.swift`, jamais le dossier `App/` entier sinon le `@main` entre dans le bundle de test). Ne jamais éditer le `.xcodeproj`.
- **Commande de test** : `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`. Départ : **75 tests verts**.
- **Keychain en tests** : jamais le vrai Keychain — `SecretResolver` prend un `SecretBackingStore` injectable ; les tests utilisent un backing mémoire.
- Commits : Conventional Commits, auteur `MaximCosta <maxim@users.noreply.github.com>`, **aucune mention d'IA**. Code/commentaires anglais ; UI en français.
- Widget kinds immuables ; app `LSUIElement` ; flake connu `RenderEngineTests.testMediumSizeDimensions` (relancer isolé si besoin).

## Périmètre

**Dans 3b-1** : `KeychainStore`/`SecretBackingStore`, `SecretResolver`/`SecretResolving`, résolution secrets dans `RenderPipeline` + purge à la suppression, `AppState.updateInstance`, `WidgetEditorModel`, `WidgetEditorView`+`ParamFormView`, activation « Éditer » + présentation, `LivePreviewView`. **Hors 3b-1** : mode avancé code/CodeMirror (3b-2) ; import/export `.bwidget` + UI consentement (3c) ; création de params ou édition du HTML.

---

## Structure des fichiers

```
BetterWidgets/
├── Core/
│   ├── KeychainStore.swift      # NOUVEAU : SecretBackingStore protocol + KeychainStore (SecItem)
│   ├── SecretResolver.swift     # NOUVEAU : SecretResolving + SecretResolver + NoopSecretResolver
│   └── Render/RenderPipeline.swift  # MODIF : param `secrets` + résolution avant fetchAll
├── App/
│   ├── AppState.swift           # MODIF : secrets exposé, updateInstance, deleteInstance purge
│   ├── WidgetEditorModel.swift  # NOUVEAU : copie de travail params/secrets + previewContext
│   ├── WidgetEditorView.swift   # NOUVEAU : layout 2 volets + ParamFormView + Save/Cancel
│   ├── LivePreviewView.swift    # NOUVEAU : NSViewRepresentable WKWebView vivante
│   ├── WidgetCard.swift         # MODIF : activer « Éditer » (onEdit)
│   └── MyWidgetsView.swift      # MODIF : présenter l'éditeur (.sheet)
└── Tests/
    ├── KeychainStoreTests.swift     # NOUVEAU (backing mémoire)
    ├── SecretResolverTests.swift    # NOUVEAU
    ├── RenderPipelineTests.swift    # MODIF : résolution secret→header
    ├── AppStateTests.swift          # MODIF : updateInstance + deleteInstance purge + init secrets
    └── WidgetEditorModelTests.swift # NOUVEAU
```

---

### Task 1: `KeychainStore` + `SecretBackingStore`

**Files:**
- Create: `BetterWidgets/Core/KeychainStore.swift`
- Test: `Tests/KeychainStoreTests.swift`

**Interfaces:**
- Produces:
  - `protocol SecretBackingStore { func setSecret(_ value: String, forKey key: String); func secret(forKey key: String) -> String?; func deleteSecret(forKey key: String) }`
  - `struct KeychainStore: SecretBackingStore` — `init()` ; service `fr.my-monkey.BetterWidgets` ; `setSecret` = delete-then-add (`SecItemAdd`), `secret(forKey:)` = `SecItemCopyMatching`, `deleteSecret` = `SecItemDelete`.
- Tests use an in-memory `SecretBackingStore` (defined in the test file), NOT `KeychainStore`, to avoid touching the real Keychain.

- [ ] **Step 1: Écrire `Tests/KeychainStoreTests.swift` (échoue)**

```swift
import XCTest

final class KeychainStoreTests: XCTestCase {
    // In-memory backing so tests never touch the real Keychain.
    final class InMemorySecretStore: SecretBackingStore {
        private var store: [String: String] = [:]
        func setSecret(_ value: String, forKey key: String) { store[key] = value }
        func secret(forKey key: String) -> String? { store[key] }
        func deleteSecret(forKey key: String) { store[key] = nil }
    }

    func testRoundTrip() {
        let s: SecretBackingStore = InMemorySecretStore()
        XCTAssertNil(s.secret(forKey: "k"))
        s.setSecret("v", forKey: "k")
        XCTAssertEqual(s.secret(forKey: "k"), "v")
        s.setSecret("v2", forKey: "k")   // overwrite
        XCTAssertEqual(s.secret(forKey: "k"), "v2")
        s.deleteSecret(forKey: "k")
        XCTAssertNil(s.secret(forKey: "k"))
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -only-testing:BetterWidgetsTests/KeychainStoreTests -quiet`
Expected: FAIL — `cannot find type 'SecretBackingStore' in scope`.

- [ ] **Step 3: Implémenter `KeychainStore.swift`**

```swift
import Foundation
import Security

/// Abstraction over secret storage so the app uses the Keychain in production
/// while tests inject an in-memory backing (the real Keychain is never touched in tests).
protocol SecretBackingStore {
    func setSecret(_ value: String, forKey key: String)
    func secret(forKey key: String) -> String?
    func deleteSecret(forKey key: String)
}

/// Keychain-backed secret store (generic password items, one service).
struct KeychainStore: SecretBackingStore {
    private let service = "fr.my-monkey.BetterWidgets"

    func setSecret(_ value: String, forKey key: String) {
        deleteSecret(forKey: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func secret(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteSecret(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 4: Vérifier que le test passe**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/KeychainStoreTests -quiet`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: keychain-backed secret store behind an injectable backing protocol"
```

---

### Task 2: `SecretResolver` + `SecretResolving` + `NoopSecretResolver`

**Files:**
- Create: `BetterWidgets/Core/SecretResolver.swift`
- Test: `Tests/SecretResolverTests.swift`

**Interfaces:**
- Consumes: `SecretBackingStore` (Task 1), `SourceSpec` (`key`, `type`, `config`).
- Produces:
  - `protocol SecretResolving { func resolvedConfig(for source: SourceSpec, instanceId: UUID) -> [String: String]? }`
  - `struct SecretResolver: SecretResolving` :
    - `init(backing: SecretBackingStore)`
    - `func set(_ value: String, instanceId: UUID, sourceKey: String, header: String)`
    - `func get(instanceId: UUID, sourceKey: String, header: String) -> String?`
    - `func delete(instanceId: UUID, sourceKey: String, header: String)`
    - `func deleteAll(instanceId: UUID, sources: [SourceSpec])` — supprime les secrets de toutes les clés `secret.<H>` des sources `json`
    - `func resolvedConfig(for:instanceId:)` — pour une source `json`, remplace chaque `secret.<H>` par `header.<H>` = valeur Keychain (omis si absente) ; pour les autres types, renvoie `source.config` tel quel
    - clé Keychain = `"\(instanceId.uuidString).\(sourceKey).\(header)"`
  - `struct NoopSecretResolver: SecretResolving { func resolvedConfig(for source: SourceSpec, instanceId: UUID) -> [String: String]? { source.config } }` — défaut du pipeline / tests existants.

- [ ] **Step 1: Écrire `Tests/SecretResolverTests.swift` (échoue)**

```swift
import XCTest

final class SecretResolverTests: XCTestCase {
    private final class MemStore: SecretBackingStore {
        var store: [String: String] = [:]
        func setSecret(_ value: String, forKey key: String) { store[key] = value }
        func secret(forKey key: String) -> String? { store[key] }
        func deleteSecret(forKey key: String) { store[key] = nil }
    }

    func testSetGetDelete() {
        let mem = MemStore(); let r = SecretResolver(backing: mem)
        let id = UUID()
        r.set("tok", instanceId: id, sourceKey: "api", header: "Authorization")
        XCTAssertEqual(r.get(instanceId: id, sourceKey: "api", header: "Authorization"), "tok")
        r.delete(instanceId: id, sourceKey: "api", header: "Authorization")
        XCTAssertNil(r.get(instanceId: id, sourceKey: "api", header: "Authorization"))
    }

    func testResolvedConfigMapsSecretToHeader() {
        let mem = MemStore(); let r = SecretResolver(backing: mem)
        let id = UUID()
        r.set("Bearer xyz", instanceId: id, sourceKey: "api", header: "Authorization")
        let source = SourceSpec(key: "api", type: "json",
                                config: ["url": "https://x", "secret.Authorization": "", "header.Accept": "json"])
        let resolved = r.resolvedConfig(for: source, instanceId: id)
        XCTAssertEqual(resolved?["header.Authorization"], "Bearer xyz")  // secret → header
        XCTAssertNil(resolved?["secret.Authorization"])                  // secret key removed
        XCTAssertEqual(resolved?["header.Accept"], "json")               // existing header untouched
        XCTAssertEqual(resolved?["url"], "https://x")
    }

    func testResolvedConfigOmitsMissingSecret() {
        let mem = MemStore(); let r = SecretResolver(backing: mem)
        let source = SourceSpec(key: "api", type: "json", config: ["secret.Authorization": ""])
        let resolved = r.resolvedConfig(for: source, instanceId: UUID())
        XCTAssertNil(resolved?["header.Authorization"])  // no stored value → omitted
        XCTAssertNil(resolved?["secret.Authorization"])
    }

    func testNonJSONSourceUnchanged() {
        let r = SecretResolver(backing: MemStore())
        let source = SourceSpec(key: "sys", type: "system", config: ["secret.X": ""])
        XCTAssertEqual(r.resolvedConfig(for: source, instanceId: UUID())?["secret.X"], "")  // untouched
    }

    func testDeleteAllPurgesDeclaredSecrets() {
        let mem = MemStore(); let r = SecretResolver(backing: mem)
        let id = UUID()
        r.set("a", instanceId: id, sourceKey: "api", header: "Authorization")
        let sources = [SourceSpec(key: "api", type: "json", config: ["secret.Authorization": ""])]
        r.deleteAll(instanceId: id, sources: sources)
        XCTAssertNil(r.get(instanceId: id, sourceKey: "api", header: "Authorization"))
    }

    func testNoopResolverReturnsConfigUnchanged() {
        let source = SourceSpec(key: "api", type: "json", config: ["secret.Authorization": ""])
        XCTAssertEqual(NoopSecretResolver().resolvedConfig(for: source, instanceId: UUID())?["secret.Authorization"], "")
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/SecretResolverTests -quiet`
Expected: FAIL — `cannot find 'SecretResolver' in scope`.

- [ ] **Step 3: Implémenter `SecretResolver.swift`**

```swift
import Foundation

/// What RenderPipeline needs from secret handling: turn a source's `secret.<H>`
/// config entries into resolved `header.<H>` entries (reading stored secret values).
protocol SecretResolving {
    func resolvedConfig(for source: SourceSpec, instanceId: UUID) -> [String: String]?
}

/// Stores per-instance API secrets and resolves them into request headers at fetch time.
/// Keeps secrets out of instances.json — they live only in the backing store (Keychain in prod).
struct SecretResolver: SecretResolving {
    private let backing: SecretBackingStore

    init(backing: SecretBackingStore) { self.backing = backing }

    private func key(_ instanceId: UUID, _ sourceKey: String, _ header: String) -> String {
        "\(instanceId.uuidString).\(sourceKey).\(header)"
    }

    func set(_ value: String, instanceId: UUID, sourceKey: String, header: String) {
        backing.setSecret(value, forKey: key(instanceId, sourceKey, header))
    }

    func get(instanceId: UUID, sourceKey: String, header: String) -> String? {
        backing.secret(forKey: key(instanceId, sourceKey, header))
    }

    func delete(instanceId: UUID, sourceKey: String, header: String) {
        backing.deleteSecret(forKey: key(instanceId, sourceKey, header))
    }

    /// Purge every declared secret of an instance (called when the instance is deleted).
    func deleteAll(instanceId: UUID, sources: [SourceSpec]) {
        for source in sources where source.type == "json" {
            for (k, _) in source.config ?? [:] where k.hasPrefix("secret.") {
                delete(instanceId: instanceId, sourceKey: source.key,
                       header: String(k.dropFirst("secret.".count)))
            }
        }
    }

    func resolvedConfig(for source: SourceSpec, instanceId: UUID) -> [String: String]? {
        guard source.type == "json", let config = source.config else { return source.config }
        var result = config
        for (k, _) in config where k.hasPrefix("secret.") {
            result.removeValue(forKey: k)
            let header = String(k.dropFirst("secret.".count))
            if let value = get(instanceId: instanceId, sourceKey: source.key, header: header) {
                result["header.\(header)"] = value
            }
        }
        return result
    }
}

/// Null object: no secret resolution (default for RenderPipeline and pre-3b-1 tests).
struct NoopSecretResolver: SecretResolving {
    func resolvedConfig(for source: SourceSpec, instanceId: UUID) -> [String: String]? { source.config }
}
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/SecretResolverTests -quiet`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: SecretResolver — per-instance secrets mapped to request headers"
```

---

### Task 3: Résolution des secrets dans `RenderPipeline` + câblage `AppState`

**Files:**
- Modify: `BetterWidgets/Core/Render/RenderPipeline.swift`
- Modify: `BetterWidgets/App/AppState.swift`
- Test: `Tests/RenderPipelineTests.swift`

**Interfaces:**
- Consumes: `SecretResolving`/`SecretResolver`/`NoopSecretResolver` (Task 2), `SourceSpec`.
- Produces:
  - `RenderPipeline.init` gagne un paramètre **avec défaut** : `secrets: any SecretResolving = NoopSecretResolver()` (inséré après `registry:`). Comportement : avant `fetchAll(allowed)`, chaque source `allowed` est remappée via `secrets.resolvedConfig(for:instanceId:)` (secret.<H>→header.<H>) ; le reste inchangé. Le défaut Noop préserve le comportement des tests existants.
  - `AppState` : nouvelle propriété publique `let secrets: SecretResolver` ; designated `init` gagne `secrets: SecretResolver` (après `templates:`) ; convenience `init()` construit `SecretResolver(backing: KeychainStore())` et le passe au pipeline (`secrets: secrets`) ; `deleteInstance` purge les secrets de l'instance (via `secrets.deleteAll(instanceId:sources:)`, sources issues du manifest).

- [ ] **Step 1: Écrire le test dans `Tests/RenderPipelineTests.swift`**

Ajouter (le fichier a déjà `FakeEngine`/`FakeReloader`/`setUp` avec un template « clock ») un test qui prouve que le secret est injecté dans la config passée au provider. On utilise un faux provider qui capture la config reçue :

```swift
    func testSecretResolvedIntoHeaderBeforeFetch() async throws {
        // Template with a json source declaring a secret header.
        let dir = tmp.appendingPathComponent("templates/api")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"{ "id": "api", "name": "API", "version": "1.0.0", "sizes": ["small"], "refresh": 60, "params": [], "sources": [{"key":"api","type":"json","config":{"url":"https://x","secret.Authorization":""}}] }"#
            .write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "<html></html>".write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

        final class CapturingProvider: DataProvider {
            static let type = "json"
            let minimumInterval: TimeInterval = 60
            var lastConfig: [String: String]?
            func fetch(spec: SourceSpec, paramValues: [String: String]) async throws -> Any {
                lastConfig = spec.config
                return ["ok": true]
            }
        }
        let capturing = CapturingProvider()
        let mem = InMemorySecretStore()   // defined in this test file (see below)
        let resolver = SecretResolver(backing: mem)
        let instance = WidgetInstance(id: UUID(), name: "a", templateId: "api", size: .small, paramValues: [:])
        resolver.set("Bearer T", instanceId: instance.id, sourceKey: "api", header: "Authorization")

        let pipeline = RenderPipeline(templates: templates, shared: shared, permissions: permissions,
                                      registry: DataProviderRegistry(providers: [capturing]),
                                      secrets: resolver, engine: FakeEngine(), reloader: FakeReloader())
        await pipeline.refresh(instance)

        XCTAssertEqual(capturing.lastConfig?["header.Authorization"], "Bearer T")
        XCTAssertNil(capturing.lastConfig?["secret.Authorization"])
    }
```

Ajouter en haut du fichier de test une petite classe backing mémoire (si pas déjà présente) :

```swift
    final class InMemorySecretStore: SecretBackingStore {
        private var s: [String: String] = [:]
        func setSecret(_ value: String, forKey key: String) { s[key] = value }
        func secret(forKey key: String) -> String? { s[key] }
        func deleteSecret(forKey key: String) { s[key] = nil }
    }
```

Note : les constructions existantes de `RenderPipeline(...)` dans ce fichier **n'ont pas** de `secrets:` → elles compilent grâce au défaut `NoopSecretResolver()`. Ne pas les modifier.

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/RenderPipelineTests -quiet`
Expected: FAIL — `RenderPipeline` n'a pas de paramètre `secrets:`.

- [ ] **Step 3: Modifier `RenderPipeline.swift`**

Ajouter la propriété + le paramètre (avec défaut) et la remap avant `fetchAll` :

Dans la classe : `private let secrets: any SecretResolving`.
Init — insérer après `registry: DataProviderRegistry` :
```swift
         registry: DataProviderRegistry, secrets: any SecretResolving = NoopSecretResolver(),
         engine: any Rendering, reloader: any WidgetReloading) {
        ...
        self.registry = registry
        self.secrets = secrets
        self.engine = engine
        ...
```
Dans `refresh`, remplacer `let fetch = await registry.fetchAll(sources: allowed, paramValues: params)` par :
```swift
            // Resolve per-instance API secrets (secret.<H> → header.<H>) before fetching.
            let resolvedAllowed = allowed.map {
                SourceSpec(key: $0.key, type: $0.type,
                           config: secrets.resolvedConfig(for: $0, instanceId: instance.id))
            }
            let fetch = await registry.fetchAll(sources: resolvedAllowed, paramValues: params)
```

- [ ] **Step 4: Modifier `AppState.swift`**

Ajouter la propriété `let secrets: SecretResolver`, l'injecter, et purger à la suppression :

Designated init — insérer `secrets: SecretResolver` après `templates:` :
```swift
    let secrets: SecretResolver

    init(shared: SharedStore, templates: TemplateStore, secrets: SecretResolver,
         scheduler: any InstanceScheduling) {
        self.shared = shared
        self.templates = templates
        self.secrets = secrets
        self.scheduler = scheduler
    }
```
Convenience init — construire le resolver réel et le passer au pipeline :
```swift
    convenience init() {
        let shared = SharedStore.appGroup()
        let templates = TemplateStore.applicationSupport()
        let permissions = PermissionStore.appGroup()
        let secrets = SecretResolver(backing: KeychainStore())
        let pipeline = RenderPipeline(templates: templates, shared: shared, permissions: permissions,
                                      registry: .standard(), secrets: secrets, engine: RenderEngine(),
                                      reloader: WidgetCenterReloader())
        self.init(shared: shared, templates: templates, secrets: secrets,
                  scheduler: Scheduler(refresher: pipeline, templates: templates))
    }
```
`deleteInstance` — purger les secrets avant de retirer :
```swift
    func deleteInstance(_ id: UUID) {
        if let instance = instances.first(where: { $0.id == id }),
           let manifest = try? templates.manifest(id: instance.templateId) {
            secrets.deleteAll(instanceId: id, sources: manifest.sources)
        }
        instances.removeAll { $0.id == id }
        shared.removeInstance(id: id)
        persistAndReschedule()
    }
```

- [ ] **Step 5: Mettre à jour `Tests/AppStateTests.swift` pour le nouveau init**

Le designated init gagne `secrets:`. Mettre à jour le helper `makeState()` (et toute construction directe) pour injecter un `SecretResolver` à backing mémoire. Ajouter au fichier la classe backing mémoire (si absente) et modifier `makeState` :

```swift
    // add near the top of AppStateTests:
    final class MemSecretStore: SecretBackingStore {
        private var s: [String: String] = [:]
        func setSecret(_ value: String, forKey key: String) { s[key] = value }
        func secret(forKey key: String) -> String? { s[key] }
        func deleteSecret(forKey key: String) { s[key] = nil }
    }

    // in makeState():
    private func makeState() -> (AppState, SpyScheduler) {
        let spy = SpyScheduler()
        let state = AppState(shared: shared, templates: templates,
                             secrets: SecretResolver(backing: MemSecretStore()), scheduler: spy)
        return (state, spy)
    }
```

- [ ] **Step 6: Vérifier — suite complète**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: PASS (RenderPipeline secret test + AppStateTests mis à jour + reste). L'app build (convenience init câblé).

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: resolve per-instance secrets into headers in the render pipeline"
```

---

### Task 4: `AppState.updateInstance`

**Files:**
- Modify: `BetterWidgets/App/AppState.swift`
- Test: `Tests/AppStateTests.swift`

**Interfaces:**
- Produces: `func updateInstance(_ updated: WidgetInstance)` — remplace l'instance de même `id` dans `instances` (no-op si absente), `saveInstances`, `scheduler.restart` + refresh (via `persistAndReschedule`).

- [ ] **Step 1: Écrire le test**

```swift
    func testUpdateInstanceReplacesAndPersists() {
        let (state, spy) = makeState()
        let a = state.createInstance(templateId: "hello-clock", size: .small)
        var edited = a
        edited.paramValues = ["accent": "#000000"]
        state.updateInstance(edited)
        XCTAssertEqual(state.instances.first(where: { $0.id == a.id })?.paramValues, ["accent": "#000000"])
        XCTAssertEqual(shared.loadInstances().first(where: { $0.id == a.id })?.paramValues, ["accent": "#000000"])
        XCTAssertEqual(spy.restarted.last, state.instances)
    }

    func testUpdateInstanceUnknownIdIsNoOp() {
        let (state, _) = makeState()
        _ = state.createInstance(templateId: "hello-clock", size: .small)
        let before = state.instances
        state.updateInstance(WidgetInstance(id: UUID(), name: "x", templateId: "hello-clock",
                                            size: .small, paramValues: [:]))
        XCTAssertEqual(state.instances, before)
    }
```

(`WidgetInstance.paramValues` est `var` — vérifié dans `WidgetInstance.swift` ; sinon reconstruire l'instance.)

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/AppStateTests -quiet`
Expected: FAIL — `AppState` n'a pas de membre `updateInstance`.

- [ ] **Step 3: Implémenter dans `AppState.swift`** (dans la section CRUD)

```swift
    func updateInstance(_ updated: WidgetInstance) {
        guard let index = instances.firstIndex(where: { $0.id == updated.id }) else { return }
        instances[index] = updated
        persistAndReschedule()
    }
```

- [ ] **Step 4: Vérifier que les tests passent**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/AppStateTests -quiet`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: AppState.updateInstance persists an edited instance"
```

---

### Task 5: `WidgetEditorModel` (copie de travail + previewContext)

**Files:**
- Create: `BetterWidgets/App/WidgetEditorModel.swift`
- Test: `Tests/WidgetEditorModelTests.swift`
- Modify: `project.yml` (ajouter `BetterWidgets/App/WidgetEditorModel.swift` aux sources `BetterWidgetsTests`)

**Interfaces:**
- Consumes: `WidgetInstance`, `TemplateManifest` (`params`, `sources`), `ParamSpec`, `SourceSpec`, `WidgetSize`, `Theme`, `RenderContext`, `SecretResolver`.
- Produces: `@MainActor final class WidgetEditorModel: ObservableObject`
  - init `init(instance: WidgetInstance, manifest: TemplateManifest, secrets: SecretResolver)` — seed `paramValues` (copie), `secretValues` (chargés depuis `secrets.get` pour chaque `secret.<H>` déclaré), `previewSize = instance.size`, `previewTheme = .light`.
  - `@Published var paramValues: [String: String]`
  - `@Published var secretValues: [String: String]` (clé `"\(sourceKey).\(header)"`)
  - `@Published var previewSize: WidgetSize` ; `@Published var previewTheme: Theme`
  - `var secretRequirements: [(sourceKey: String, header: String)]` — dérivé des sources `json` du manifest (`secret.<H>`)
  - `func mergedParams() -> [String: String]` — défauts du manifest ⊕ `paramValues`
  - `func previewContext(data: [String: Any], stale: Bool) -> RenderContext` — `RenderContext(params: mergedParams(), data: data, size: previewSize, theme: previewTheme, stale: stale)`
  - `func updatedInstance() -> WidgetInstance` — instance d'origine avec `paramValues` de travail
  - `func persistSecrets(instanceId: UUID)` — écrit chaque `secretValues` non vide via `secrets.set(...)`

- [ ] **Step 1: Écrire `Tests/WidgetEditorModelTests.swift` (échoue)**

```swift
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
        let m = manifest(params: #"{"key":"accent","type":"color","label":"A","default":"#fff"}"#)
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
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test ... -only-testing:BetterWidgetsTests/WidgetEditorModelTests -quiet`
Expected: FAIL — `cannot find 'WidgetEditorModel' in scope` (après ajout du fichier à `project.yml`, cf. Step 3).

- [ ] **Step 3: Ajouter le fichier aux sources de test dans `project.yml`**

Sous le target `BetterWidgetsTests` → `sources`, ajouter (comme `AppState.swift`/`WidgetCard.swift`) :
```yaml
      - path: BetterWidgets/App/WidgetEditorModel.swift
        optional: true
```

- [ ] **Step 4: Implémenter `WidgetEditorModel.swift`**

```swift
import Foundation
import SwiftUI

/// Working copy of an instance being edited: params + secrets + preview size/theme,
/// isolated from the real instance until save.
@MainActor
final class WidgetEditorModel: ObservableObject {
    let instance: WidgetInstance
    let manifest: TemplateManifest
    private let secrets: SecretResolver

    @Published var paramValues: [String: String]
    @Published var secretValues: [String: String]   // "<sourceKey>.<header>" -> value
    @Published var previewSize: WidgetSize
    @Published var previewTheme: Theme = .light

    init(instance: WidgetInstance, manifest: TemplateManifest, secrets: SecretResolver) {
        self.instance = instance
        self.manifest = manifest
        self.secrets = secrets
        self.paramValues = instance.paramValues
        self.previewSize = instance.size
        var seeded: [String: String] = [:]
        for req in Self.secretRequirements(from: manifest) {
            seeded["\(req.sourceKey).\(req.header)"] =
                secrets.get(instanceId: instance.id, sourceKey: req.sourceKey, header: req.header) ?? ""
        }
        self.secretValues = seeded
    }

    static func secretRequirements(from manifest: TemplateManifest) -> [(sourceKey: String, header: String)] {
        manifest.sources.filter { $0.type == "json" }.flatMap { source in
            (source.config ?? [:]).keys.filter { $0.hasPrefix("secret.") }
                .map { (source.key, String($0.dropFirst("secret.".count))) }
        }
    }

    var secretRequirements: [(sourceKey: String, header: String)] { Self.secretRequirements(from: manifest) }

    func mergedParams() -> [String: String] {
        var params: [String: String] = [:]
        for spec in manifest.params { params[spec.key] = spec.default }
        params.merge(paramValues) { _, working in working }
        return params
    }

    func previewContext(data: [String: Any], stale: Bool) -> RenderContext {
        RenderContext(params: mergedParams(), data: data, size: previewSize, theme: previewTheme, stale: stale)
    }

    func updatedInstance() -> WidgetInstance {
        var copy = instance
        copy.paramValues = paramValues
        return copy
    }

    func persistSecrets(instanceId: UUID) {
        for (composite, value) in secretValues where !value.isEmpty {
            let parts = composite.split(separator: ".", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            secrets.set(value, instanceId: instanceId, sourceKey: parts[0], header: parts[1])
        }
    }
}
```

- [ ] **Step 5: Vérifier que les tests passent**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: WidgetEditorModel — isolated working copy of params + secrets"
```

---

### Task 6: `WidgetEditorView` + `ParamFormView` + activation « Éditer »

**Files:**
- Create: `BetterWidgets/App/WidgetEditorView.swift` (contient `WidgetEditorView` + `ParamFormView`)
- Modify: `BetterWidgets/App/WidgetCard.swift` (activer « Éditer » via un callback `onEdit`)
- Modify: `BetterWidgets/App/MyWidgetsView.swift` (présenter l'éditeur en `.sheet`)

**Interfaces:**
- Consumes: `WidgetEditorModel` (Task 5), `AppState` (`updateInstance`, `secrets`, `templates`), `TemplateManifest`, `ParamSpec`, `DesignTokens`.
- Produces:
  - `struct WidgetEditorView: View` — `init(state: AppState, instance: WidgetInstance, onClose: () -> Void)` ; layout 2 volets (gauche `ParamFormView`, droite un **placeholder** « Aperçu (bientôt) » — remplacé par la vraie preview en Task 7) ; barre Enregistrer (→ `state.updateInstance(model.updatedInstance())` + `model.persistSecrets(instanceId:)` + `onClose()`) / Annuler (`confirmationDialog` si modifs).
  - `struct ParamFormView: View` — une ligne par `ParamSpec` (string/number/url→TextField, color→ColorPicker via hex) + un `SecureField` par `model.secretRequirements`.
  - `WidgetCard` : `Button("Éditer")` **activé**, appelle un nouveau paramètre `onEdit: () -> Void` (remplace le `.disabled(true)`).
  - `MyWidgetsView` : `@State editing: WidgetInstance?` ; `WidgetCard(..., onEdit: { editing = instance })` ; `.sheet(item: $editing) { WidgetEditorView(state: state, instance: $0) { editing = nil } }`.
- Vues SwiftUI → pas de test unitaire ; gate = build vert. La logique (model) est déjà testée (Task 5).

- [ ] **Step 1: Invoquer la skill `minimalist-ui`** avant d'écrire le SwiftUI.

- [ ] **Step 2: Implémenter `WidgetEditorView.swift`**

```swift
import SwiftUI

struct WidgetEditorView: View {
    @StateObject private var model: WidgetEditorModel
    private let state: AppState
    private let onClose: () -> Void
    @State private var confirmCancel = false

    init(state: AppState, instance: WidgetInstance, onClose: @escaping () -> Void) {
        self.state = state
        self.onClose = onClose
        let manifest = (try? state.templates.manifest(id: instance.templateId))
            ?? TemplateManifest(id: instance.templateId, name: instance.name, version: "1",
                                sizes: [instance.size], refresh: 60, params: [], sources: [], links: nil)
        _model = StateObject(wrappedValue: WidgetEditorModel(instance: instance, manifest: manifest,
                                                             secrets: state.secrets))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: DesignTokens.Space.xl) {
                ParamFormView(model: model)
                    .frame(width: 320)
                previewPlaceholder
            }
            .padding(DesignTokens.Space.xl)
            Divider()
            toolbar
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(DesignTokens.background)
        .confirmationDialog("Abandonner les modifications ?", isPresented: $confirmCancel) {
            Button("Abandonner", role: .destructive, action: onClose)
            Button("Continuer l'édition", role: .cancel) {}
        }
    }

    private var previewPlaceholder: some View {
        // Replaced by LivePreviewView in Task 7.
        RoundedRectangle(cornerRadius: DesignTokens.Radius.preview)
            .fill(DesignTokens.surface)
            .overlay(Text("Aperçu (bientôt)").foregroundStyle(DesignTokens.textSecondary))
            .frame(maxWidth: .infinity, minHeight: 360)
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.preview).stroke(DesignTokens.separator, lineWidth: 1))
    }

    private var toolbar: some View {
        HStack {
            Text(model.instance.name).font(.system(size: DesignTokens.FontSize.title, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)
            Spacer()
            Button("Annuler") { confirmCancel = true }
            Button("Enregistrer") {
                state.updateInstance(model.updatedInstance())
                model.persistSecrets(instanceId: model.instance.id)
                onClose()
            }
            .buttonStyle(.borderedProminent).tint(DesignTokens.accent)
        }
        .padding(DesignTokens.Space.lg)
    }
}

struct ParamFormView: View {
    @ObservedObject var model: WidgetEditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Space.lg) {
                ForEach(model.manifest.params, id: \.key) { spec in
                    paramRow(spec)
                }
                ForEach(model.secretRequirements, id: \.header) { req in
                    secretRow(req)
                }
            }
            .padding(DesignTokens.Space.lg)
        }
    }

    @ViewBuilder private func paramRow(_ spec: ParamSpec) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.xs) {
            Text(spec.label).font(.system(size: DesignTokens.FontSize.label, weight: .medium))
                .foregroundStyle(DesignTokens.textPrimary)
            switch spec.type {
            case .color:
                ColorPicker("", selection: colorBinding(spec.key), supportsOpacity: false).labelsHidden()
            default:
                TextField("", text: paramBinding(spec.key)).textFieldStyle(.roundedBorder)
            }
        }
    }

    private func secretRow(_ req: (sourceKey: String, header: String)) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.xs) {
            Text("Secret : \(req.header)").font(.system(size: DesignTokens.FontSize.label, weight: .medium))
                .foregroundStyle(DesignTokens.textPrimary)
            SecureField("", text: secretBinding(req)).textFieldStyle(.roundedBorder)
        }
    }

    private func paramBinding(_ key: String) -> Binding<String> {
        Binding(get: { model.paramValues[key] ?? "" }, set: { model.paramValues[key] = $0 })
    }

    private func secretBinding(_ req: (sourceKey: String, header: String)) -> Binding<String> {
        let composite = "\(req.sourceKey).\(req.header)"
        return Binding(get: { model.secretValues[composite] ?? "" }, set: { model.secretValues[composite] = $0 })
    }

    private func colorBinding(_ key: String) -> Binding<Color> {
        Binding(
            get: { Color(hex: model.paramValues[key] ?? "#000000") },
            set: { model.paramValues[key] = $0.toHex() })
    }
}
```

`Color(hex:)` / `toHex()` : ajouter un petit helper en bas de `WidgetEditorView.swift` (conversion `#rrggbb` ⇄ `Color` via `NSColor`) :

```swift
extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b)
    }
    func toHex() -> String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int(ns.redComponent * 255), Int(ns.greenComponent * 255), Int(ns.blueComponent * 255))
    }
}
```

- [ ] **Step 3: Activer « Éditer » dans `WidgetCard.swift`**

Ajouter un paramètre `let onEdit: () -> Void` à `WidgetCard` et remplacer `Button("Éditer") {}.disabled(true)` par `Button("Éditer", action: onEdit)`.

- [ ] **Step 4: Présenter l'éditeur dans `MyWidgetsView.swift`**

Ajouter `@State private var editing: WidgetInstance?` ; passer `onEdit: { editing = instance }` à chaque `WidgetCard` ; ajouter le modifier `.sheet(item: $editing) { instance in WidgetEditorView(state: state, instance: instance) { editing = nil } }`. (`WidgetInstance` est `Identifiable` — OK pour `.sheet(item:)`.)

- [ ] **Step 5: Vérifier le build + suite**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: PASS (suite inchangée) ; l'app build avec l'éditeur (Éditer ouvre la feuille, formulaire + placeholder d'aperçu, Enregistrer persiste).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: widget param editor (form + secrets) opened from the Éditer action"
```

---

### Task 7: `LivePreviewView` (WKWebView vivante) intégrée à l'éditeur + vérif réelle

**Files:**
- Create: `BetterWidgets/App/LivePreviewView.swift`
- Modify: `BetterWidgets/App/WidgetEditorView.swift` (remplace le placeholder par `LivePreviewView` + toggles taille/thème + fetch initial des données)

**Interfaces:**
- Consumes: `WidgetEditorModel`, `AppState` (`templates`, `secrets`, `permissions` via un fetch), `DataProviderRegistry`, `RenderContext`, `NavigationPolicy` + `TemplateAssetSchemeHandler` (Plan 2), `WidgetSize`, `Theme`, `DesignTokens`.
- Produces:
  - `struct LivePreviewView: NSViewRepresentable` — `init(html: String, templateDir: URL, context: RenderContext)` ; monte une WKWebView (config = scheme handler `bwasset://` sur `templateDir` + `NavigationPolicy` en nav delegate) ; charge le HTML avec `window.BW` injecté ; `updateNSView` ré-injecte `window.BW` (params/size/theme) via `evaluateJavaScript` + dispatch un event `bwParamsChanged`, redimensionne à `context.size.pointSize`, applique l'`appearance` selon `context.theme`.
  - `WidgetEditorView` : remplace `previewPlaceholder` par un panneau contenant les toggles (Picker taille parmi `manifest.sizes`, toggle clair/sombre) + `LivePreviewView(html:templateDir:context: model.previewContext(data:stale:))`. Les **données** sont fetchées une fois au `.task` d'ouverture (via `DataProviderRegistry.standard()` + résolution permissions/secrets) et stockées en `@State`; bouton « Rafraîchir l'aperçu » refait le fetch.

- [ ] **Step 1: Invoquer la skill `minimalist-ui`** avant le SwiftUI des toggles.

- [ ] **Step 2: Implémenter `LivePreviewView.swift`**

```swift
import SwiftUI
import WebKit

/// A live WKWebView preview of a template — same window.BW contract and bwasset://
/// confinement as the render engine, so the preview matches the final widget.
struct LivePreviewView: NSViewRepresentable {
    let html: String
    let templateDir: URL
    let context: RenderContext

    func makeNSView(context ctx: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(TemplateAssetSchemeHandler(templateDir: templateDir),
                                   forURLScheme: TemplateAssetSchemeHandler.scheme)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = ctx.coordinator
        ctx.coordinator.load(webView, html: html, context: self.context)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context ctx: Context) {
        webView.appearance = NSAppearance(named: self.context.theme == .dark ? .darkAqua : .aqua)
        ctx.coordinator.reinject(webView, context: self.context)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var loaded = false

        func load(_ webView: WKWebView, html: String, context: RenderContext) {
            let bw = (try? context.bwJSON()) ?? "{}"
            let script = "window.BW = \(bw); window.BW.ready = function(){};"
            webView.configuration.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            webView.appearance = NSAppearance(named: context.theme == .dark ? .darkAqua : .aqua)
            webView.loadHTMLString(html, baseURL: URL(string: "\(TemplateAssetSchemeHandler.scheme)://template/"))
        }

        /// Re-push params/size/theme into a loaded page without a full reload.
        func reinject(_ webView: WKWebView, context: RenderContext) {
            guard loaded, let bw = try? context.bwJSON() else { return }
            webView.evaluateJavaScript(
                "window.BW = \(bw); window.dispatchEvent(new Event('bwParamsChanged'));", completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true }

        nonisolated func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(NavigationPolicy.decide(for: action.request.url))
        }
    }
}
```

Note : la ré-injection suppose que le template relit `window.BW` (soit au chargement, soit sur l'event `bwParamsChanged`). Les templates maison sont statiques (lisent `BW` au load) → pour eux, un changement de param **debounce → reload** est plus fiable. Choix : dans `updateNSView`, si seul un param a changé, ré-injecter + reload léger (`webView.reload()` après avoir mis à jour le userScript). Pour rester simple et fiable au 1er jet : **recharger** la webview sur changement de contexte (les templates 3a/Plan 2 ne câblent pas `bwParamsChanged`). Implémentation retenue : `updateNSView` reconstruit le userScript `BW` et fait `webView.loadHTMLString(...)` à nouveau (debounce géré côté `WidgetEditorView` par la nature de `@Published`). Documenter ce choix ; l'event `bwParamsChanged` reste offert pour les templates qui voudront un update sans flash.

- [ ] **Step 3: Intégrer dans `WidgetEditorView.swift`** (remplacer `previewPlaceholder`)

Ajouter à `WidgetEditorView` : `@State private var previewData: [String: Any] = [:]` et `@State private var previewStale = false`. Remplacer `previewPlaceholder` par :

```swift
    private var previewPanel: some View {
        VStack(spacing: DesignTokens.Space.md) {
            HStack(spacing: DesignTokens.Space.md) {
                Picker("", selection: $model.previewSize) {
                    ForEach(model.manifest.sizes, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).fixedSize()
                Toggle("Sombre", isOn: Binding(get: { model.previewTheme == .dark },
                                               set: { model.previewTheme = $0 ? .dark : .light }))
                Spacer()
                Button("Rafraîchir l'aperçu") { Task { await fetchPreviewData() } }
            }
            LivePreviewView(html: html, templateDir: templateDir,
                            context: model.previewContext(data: previewData, stale: previewStale))
                .frame(width: model.previewSize.pointSize.width, height: model.previewSize.pointSize.height)
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.preview).stroke(DesignTokens.separator, lineWidth: 1))
        }
        .task { await fetchPreviewData() }
    }

    private var html: String { (try? state.templates.html(id: model.instance.templateId)) ?? "<html></html>" }
    private var templateDir: URL { state.templates.templateDirectory(id: model.instance.templateId) }

    @MainActor private func fetchPreviewData() async {
        // Resolve secrets + permissions like the pipeline, fetch once for the preview.
        let granted = state.permissions.grantedTypes(instanceId: model.instance.id)
        let allowed = model.manifest.sources.filter { !$0.requiresConsent || granted.contains($0.type) }
        // Apply working-copy secrets so the preview is authenticated even before save.
        for (composite, value) in model.secretValues where !value.isEmpty {
            let parts = composite.split(separator: ".", maxSplits: 1).map(String.init)
            if parts.count == 2 { state.secrets.set(value, instanceId: model.instance.id, sourceKey: parts[0], header: parts[1]) }
        }
        let resolved = allowed.map { SourceSpec(key: $0.key, type: $0.type,
            config: state.secrets.resolvedConfig(for: $0, instanceId: model.instance.id)) }
        let result = await DataProviderRegistry.standard().fetchAll(sources: resolved, paramValues: model.mergedParams())
        var data = result.data
        for source in model.manifest.sources where source.requiresConsent && !granted.contains(source.type) {
            data[source.key] = ["__denied": true]
        }
        previewData = data
        previewStale = !result.failedKeys.isEmpty
    }
```

⚠️ Note : `fetchPreviewData` écrit les secrets de travail dans le Keychain **avant** save (nécessaire pour une preview authentifiée). C'est acceptable (les secrets d'une instance existante) ; `persistSecrets` au save reste la source de vérité. Documenter.

Remplacer, dans `body`, l'appel `previewPlaceholder` par `previewPanel`.

- [ ] **Step 4: Vérifier build + suite**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet`
Expected: PASS (suite inchangée) + l'app build avec la preview live.

- [ ] **Step 5: Vérification réelle**

```bash
xcodegen generate && xcodebuild build -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS' -quiet
APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/BetterWidgets-*/Build/Products/Debug/*.app | head -1)
pkill -x BetterWidgets 2>/dev/null || true; sleep 1
open "$APP"; sleep 8
osascript -e 'tell application "System Events" to tell process "BetterWidgets" to set frontmost to true' 2>/dev/null || true
screencapture -x /tmp/bw-3b1-editor.png 2>/dev/null || true
ls -la /tmp/bw-3b1-editor.png 2>/dev/null || echo "screenshot not captured (screen may be locked)"
```
À vérifier (œil / capture si l'écran n'est pas verrouillé) : ouvrir un widget via « Éditer » → le formulaire liste les params du template ; changer la couleur d'accent → la preview se met à jour ; basculer la taille et le thème → la preview suit ; Enregistrer → la carte reflète le changement. Rapporter honnêtement si la capture échoue (écran verrouillé) ; décrire l'évidence fonctionnelle (build, pas de crash) sinon. Sauver `/tmp/bw-3b1-editor.png` — le controller le relaiera.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: live WKWebView preview in the editor (size/theme toggles, secret-aware fetch)"
```

---

## Self-review (fait à l'écriture)

- **Couverture spec** : §3 archi/éditeur → Tasks 6,7 ; §4 updateInstance → Task 4 ; §5 formulaire params → Task 6 ; §6 preview live → Task 7 ; §7 secrets Keychain (KeychainStore + SecretResolver + résolution pipeline + purge delete + preview authentifiée) → Tasks 1,2,3,7 ; §8 erreurs (confirm annuler, secret vide→stale) → Tasks 6,7 ; §10 tests → Tasks 1-5 (unit) + 6,7 (build+réel).
- **Cohérence des types** : `SecretBackingStore` (T1) consommé par `SecretResolver` (T2) + tests ; `SecretResolving` (T2) = param `secrets` du `RenderPipeline` (T3, défaut `NoopSecretResolver`) ; `SecretResolver` exposé par `AppState` (T3) consommé par `WidgetEditorModel` (T5) + `WidgetEditorView`/preview (T6,7) ; `WidgetEditorModel(instance:manifest:secrets:)` cohérent T5→T6 ; `RenderContext(params:data:size:theme:stale:)` réutilisé (moteur Plan 1) ; `resolvedConfig(for:instanceId:)` signature identique T2→T3→T7 ; `TemplateAssetSchemeHandler.scheme` + `NavigationPolicy.decide` réutilisés (Plan 2) en T7.
- **Churn maîtrisé** : `RenderPipeline.secrets` a un **défaut Noop** → les constructions existantes de `RenderPipelineTests` ne changent pas ; seul `AppStateTests.makeState` change (nouveau param `secrets:` du designated init).
- **Placeholders** : aucun TODO/TBD ; code complet. Vues SwiftUI (T6,7) sans test unitaire → build + vérif réelle ; logique (T1-5) en TDD. La ré-injection live (T7) documente le choix reload-sur-changement pour fiabilité avec les templates statiques.
- **Secrets** : jamais dans `instances.json` (T5 `updatedInstance` ne porte que `paramValues`) ; purgés au delete (T3) ; en test toujours backing mémoire (jamais le vrai Keychain).
