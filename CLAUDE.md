# CLAUDE.md — `better-widgets`

App macOS barre de menus + extension WidgetKit qui rend des templates HTML en PNG clair/sombre
(WKWebView offscreen) pour afficher de vrais widgets système. Voir [`README.md`](README.md) pour
le pitch produit ; ce fichier couvre les conventions et gotchas pour continuer le développement.

**Spec** : [`docs/superpowers/specs/2026-07-03-better-widgets-design.md`](docs/superpowers/specs/2026-07-03-better-widgets-design.md)
**Plan 1 (fondations, ce qui est fait)** : [`docs/superpowers/plans/2026-07-03-better-widgets-fondations.md`](docs/superpowers/plans/2026-07-03-better-widgets-fondations.md)
**Plan 2 (providers & permissions, ce qui est fait)** : [`docs/superpowers/plans/2026-07-03-better-widgets-providers-permissions.md`](docs/superpowers/plans/2026-07-03-better-widgets-providers-permissions.md)
**Plan 3a (coquille d'app + Mes widgets, ce qui est fait)** : [spec](docs/superpowers/specs/2026-07-04-better-widgets-ui-3a-design.md) · [plan](docs/superpowers/plans/2026-07-04-better-widgets-ui-3a.md)
**Plan 3b-1 (éditeur params + preview live + secrets Keychain, ce qui est fait)** : [spec](docs/superpowers/specs/2026-07-04-better-widgets-ui-3b1-design.md) · [plan](docs/superpowers/plans/2026-07-04-better-widgets-ui-3b1.md)
**Plan 3b-2 (mode avancé code CodeMirror, ce qui est fait)** : [spec](docs/superpowers/specs/2026-07-04-better-widgets-ui-3b2-design.md) · [plan](docs/superpowers/plans/2026-07-04-better-widgets-ui-3b2.md)

## Stack

Swift 5.9 · SwiftUI · WidgetKit (`AppIntentConfiguration`) · WKWebView (moteur de rendu + preview
live + éditeur de code) · XcodeGen · macOS 14+ · Xcode 27. Pas de dépendance **SPM** — tout est
Foundation/AppKit/WebKit/WidgetKit/EventKit/WeatherKit/Security. Seul asset tiers **vendoré** (pas
un package) : **CodeMirror 5** dans `BetterWidgets/Resources/codemirror/` (mode avancé code, servi à
la WKWebView, **aucun CDN au runtime**).

## ⚠️ Le `.xcodeproj` est généré — ne jamais l'éditer à la main

`BetterWidgets.xcodeproj` est **gitignoré** (voir `.gitignore`) et regénéré depuis `project.yml` à
chaque `xcodegen generate`. Toute modification (nouveau fichier auto-inclus par un `path:` déjà
présent, nouveau target, nouvelle entitlement, nouveau schéma) se fait dans `project.yml`, jamais
dans le `.xcodeproj`. Après tout changement à `project.yml`, relancer `xcodegen generate` avant de
builder.

## Identifiants

| Élément | Valeur |
|---|---|
| Team ID | `5C67TFSJ2B` |
| Bundle ID app | `fr.my-monkey.BetterWidgets` |
| Bundle ID extension | `fr.my-monkey.BetterWidgets.WidgetExtension` |
| App Group | `5C67TFSJ2B.betterwidgets` |
| Process name (pour `pkill`/`pgrep`) | `BetterWidgets` (sans espace — différent du `CFBundleDisplayName` « Better Widgets ») |

## Widget kinds — immuables

Les 3 kinds `bw.small`, `bw.medium`, `bw.large` (définis dans `WidgetSize.kind`, `WidgetBundle.swift`)
**ne se renomment jamais** : un widget déjà posé sur le bureau d'un utilisateur est lié à son kind
par le système. Un renommage casse tous les widgets déjà placés (l'utilisateur doit les reposer).
Si un 4e format est nécessaire un jour, ajouter un kind, ne jamais réutiliser/modifier les 3 existants.

## Architecture — Core

```
BetterWidgets/Core/
├── Models/        WidgetSize, TemplateManifest (+ ParamSpec/SourceSpec/LinkSpec), WidgetInstance,
│                  InstanceState, Theme — compilés dans app ET extension
├── Render/        RenderContext, RenderEngine (WKWebView → PNG), RenderPipeline (orchestration
│                  fetch → render dual-theme → write), NavigationPolicy (whitelist de schemes —
│                  https/about/data/bwasset, tout le reste dont file:// est annulé),
│                  TemplateAssetSchemeHandler (sert bwasset://template/<path> confiné à
│                  templateDir, aucun accès file:// depuis la WebView) — EXCLU de l'extension
│                  (jamais de WebKit côté widget, l'extension est un simple lecteur de PNG)
├── Data/          DataProvider (protocol), JSONDataProvider (https only), SystemDataProvider
│                  (CPU/RAM/disque/batterie/uptime), RSSDataProvider + RSSFeedParser (RSS 2.0 +
│                  Atom via XMLParser), CalendarDataProvider (EventKit, fetcher mockable),
│                  WeatherDataProvider (WeatherKit, fetcher mockable + géocodage ville),
│                  DataProviderRegistry (fail-soft : un provider qui échoue devient une
│                  failedKey, ne bloque pas les autres sources)
├── PermissionStore.swift  grants par instance (App Group, `grants.json`) pour les sources
│                  consent-required (`calendar`/`weather`) ; consommé par RenderPipeline pour
│                  gater le fetch (voir plus bas)
├── DesignTokens.swift  langage visuel partagé (éditorial minimal) : couleurs adaptatives
│                  clair/sombre, Space, FontSize, Radius, statusColor — source unique de l'UI
├── Scheduler.swift    file de refresh sérielle par instance (1 AsyncStream + 1 worker Task) ;
│                  `restart(instances:)` recrée le stream/worker (après un `stop()`) + `InstanceScheduling`
├── SharedStore.swift  contrat App Group : instances.json, renders/<uuid>-<theme>.png, state/<uuid>.json ;
│                  `removeInstance(id:)` nettoie PNG+state
└── TemplateStore.swift   templates sur disque (Application Support) + bootstrap des templates bundlés
```

Côté **app UI** (`BetterWidgets/App/`, target app uniquement) : `AppState` (source de vérité
`@MainActor`, **injectable** : init désigné + convenience ; CRUD create/delete/**update**/duplicate +
`status(for:)` → `InstanceStatus{ok,pending,stale,error}` ; expose `shared`/`templates`/`secrets`/
`permissions`). **3a** : `MainWindowView` (`Window(id:"main")` singleton + `NavigationSplitView` Mes
widgets/Galerie), `MyWidgetsView` (grille, refresh via `TimelineView(.periodic)`), `WidgetCard`
(+`WidgetCardModel` testable), `GalleryView`, `AddToDesktopGuide`. **3b-1** (éditeur de params
d'instance) : `WidgetEditorView`/`ParamFormView`, `WidgetEditorModel`, `LivePreviewView` (WKWebView
vivante réutilisée), secrets via `Core/KeychainStore.swift`+`Core/SecretResolver.swift` (résolus dans
`RenderPipeline`, jamais dans `instances.json`). **3b-2** (mode avancé code) : `CodeEditorBridge`
(CodeMirror↔Swift), `CodeEditorView` (onglets html/manifest), `TemplateCodeEditorView` (code+preview),
`TemplateEditorModel` ; écritures de templates **utilisateur** dans `TemplateStore` (marqueur `.user` ;
bundlés read-only). Les fichiers de **logique testés** (`AppState.swift`, `WidgetCard.swift`,
`WidgetEditorModel.swift`, `TemplateEditorModel.swift`) sont ajoutés **individuellement** aux sources
de `BetterWidgetsTests` dans `project.yml` (jamais le dossier `App/` entier — sinon le `@main` entre
dans le bundle de test).

`SharedStore.swift` et `Core/Models/**` sont compilés dans **les deux** targets (app + extension)
via `project.yml` — pas de framework partagé, YAGNI tant qu'il n'y a que ces deux consommateurs.
`Core/Render` et `Core/Data` ne sont compilés que dans l'app : l'extension ne fait ni rendu ni
fetch, elle lit seulement les PNG déjà écrits par l'app dans l'App Group.

## Commande de test canonique

```bash
xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets \
  -destination 'platform=macOS' -quiet
```

154 tests. En plus des suites précédentes (Manifest, Plan2Manifest, SharedStore, TemplateStore,
RenderEngine, NavigationPolicy, TemplateAssetSchemeHandler, DataProvider, RSSDataProvider,
RSSFeedParser, CalendarDataProvider, WeatherDataProvider, PermissionStore, RenderPipeline,
Scheduler, WidgetSize, Smoke, DesignTokens, AppState, WidgetCardModel), Plan 3b-1 ajoute
`KeychainStoreTests`, `SecretResolverTests`, `WidgetEditorModelTests` ; Plan 3b-2 ajoute
`TemplateStoreWriteTests`, `TemplateEditorModelTests` ; Plan 3c ajoute `BWidgetArchiveTests`,
`BWidgetImporterTests` (8, la surface d'import), `PermissionConsentModelTests` ; Plan 4a ajoute
`BundledTemplateTests` (validation manifest + rendu `window.BW` mocké des 8 templates maison + bootstrap).
Doit rester vert avant tout commit. Les vues SwiftUI n'ont pas de tests unitaires (gate = build vert
+ vérif réelle) ; la logique (CRUD, model, scheduler, store, tokens, secrets/resolver, éditeur) est testée.
Secrets en test : toujours un `SecretBackingStore` mémoire, jamais le vrai Keychain.

Smoke E2E (build + lance l'app + vérifie les PNG dans l'App Group) : `./scripts/smoke.sh` — voir
[`README.md`](README.md) pour le détail de ce qu'il fait et pourquoi il tue le process par son nom
exact (`BetterWidgets`, pas `Better Widgets`).

## Convention de commits

Conventional Commits (`feat:`, `fix:`, `test:`, `chore:`, …), auteur `MaximCosta
<maxim@users.noreply.github.com>` (déjà configuré dans le repo). **Aucune mention d'IA** dans les
messages de commit.

## État d'avancement des plans

- **Plan 1 — Fondations** (`feat/fondations`, ce plan) : **fait**. Pipeline bout-en-bout : app →
  bootstrap → rendu du template démo (clair+sombre) → App Group → extension enregistrée
  (`fr.my-monkey.BetterWidgets.WidgetExtension`). Scheduler, `DataProviderRegistry` (`json`/`system`),
  3 kinds de widget configurables par `AppIntentConfiguration`. UI = menu bar minimal seulement.
- **Plan 2 — Providers & permissions** (`feat/fondations`) : **fait**. `SourceSpec.knownTypes`
  passe à `["json","system","rss","calendar","weather"]` (`consentRequiredTypes` = `calendar` +
  `weather`). Trois nouveaux providers dans `DataProviderRegistry.standard()` : `RSSDataProvider`
  (RSS 2.0 + Atom, parsés par `RSSFeedParser` au-dessus de `XMLParser`, aucune permission),
  `CalendarDataProvider` (EventKit, fetcher mockable en tests) et `WeatherDataProvider` (WeatherKit
  + géocodage de ville, fetcher mockable) — ces deux derniers sont consent-required et **en
  attente du provisioning WeatherKit côté portail développeur** pour des données météo réelles en
  prod (le fetcher réel est câblé, seul l'entitlement/capability portail manque). Modèle de
  permission : `PermissionStore` (App Group, grants par instance dans `grants.json`) + gating dans
  `RenderPipeline` — une source consent-required sans grant produit `data.<key>.__denied = true`
  sans affecter le `stale` existant (échec de fetch reste un chemin distinct). Durcissement
  WebView : `NavigationPolicy` n'autorise que `https`/`about`/`data`/`bwasset`, tout `file://` (et
  le reste) est annulé ; `TemplateAssetSchemeHandler` sert les assets de template via
  `bwasset://template/<path>` confiné à `templateDir` (aucun accès filesystem direct depuis la
  WebView). L'app livre désormais 8 templates maison (`weather`, `crypto`, `system`, `news`,
  `agenda`, `status`, `home`, `github` — voir Plan 4) qui exercent ces providers.
  Reportés au Plan 3 (assumé dès l'écriture du plan) : secrets `json` dans le Keychain (se
  saisissent dans l'éditeur d'instance, pas encore construit) et la météo par localisation
  courante (`CLLocationManager`) — Plan 2 ne fait que `city`/`lat`+`lon`.
- **Plan 3 — UI complète** : découpé en 3 sous-plans. **DA actée : éditorial minimal** (`DesignTokens`).
  - **3a — Coquille + Mes widgets** (`feat/fondations`) : **fait**. `Window(id:"main")` singleton
    summonnée depuis le menu bar (« Ouvrir »), `NavigationSplitView` (Mes widgets / Galerie), grille
    de cartes (PNG rendu + pastille statut ok/pending/stale/error + dupliquer/supprimer/ajouter-au-
    bureau ; Éditer désactivé « bientôt »), Galerie minimale (créer avec params par défaut),
    `AppState` injectable + CRUD, `Scheduler.restart`, `SharedStore.removeInstance`, refresh grille
    via `TimelineView(.periodic)`. Dette reportée : DRY restart/state-path ; `WidgetCard.image` non
    mémoïsé ; `enum Section` shadow `SwiftUI.Section` ; race orphelin-PNG sur delete-pendant-rendu
    (guard `writeRender`) ; auto-open once-at-launch (revisitable avec macOS 15 `.defaultLaunchBehavior(.suppressed)`).
    **Vérif visuelle bureau à faire par Maxim** (l'écran de la machine de test était verrouillé).
  - **3b — Éditeur** : scindé en 3b-1 + 3b-2.
    - **3b-1 — Params + preview + secrets** (`feat/fondations`) : **fait**. Bouton « Éditer » activé →
      `WidgetEditorView` (.sheet) : formulaire de params généré du manifest (préremplit les défauts) +
      **preview live WKWebView** (mêmes `window.BW`/`bwasset://`/`NavigationPolicy` que le moteur → la
      preview = le rendu final ; toggles taille/thème). Secrets d'API des sources `json` : convention
      `secret.<Header>` dans la config → `SecureField` → stockés au **Keychain** (`KeychainStore`/
      `SecretResolver`, clé `<uuid>.<sourceKey>.<header>`), résolus en `header.<H>` **dans
      `RenderPipeline`** (protocole `DataProvider` intact), purgés à la suppression du widget. Secrets
      **jamais** dans `instances.json` ni `window.BW` ; la preview les résout via un resolver **en
      mémoire** (aucune écriture Keychain avant « Enregistrer »). `AppState.updateInstance`.
      Dette fast-follow : factoriser le resolve/partition dupliqué entre `RenderPipeline.refresh` et
      `fetchPreviewData`.
    - **3b-2 — Mode avancé code** (`feat/fondations`) : **fait**. Depuis la Galerie, « Nouveau
      template » (scaffold) ou « Forker » un template crée un template **utilisateur** (sur disque,
      marqueur `.user` ; les bundlés restent read-only), ouvert dans `TemplateCodeEditorView` (.sheet) :
      **CodeMirror 5 vendoré** (`CodeEditorBridge`, onglets html/manifest, coloration + numéros de
      ligne, servi via `bwasset://`, pont Swift↔JS synchrone) à gauche + `LivePreviewView` à droite.
      Manifest validé à l'enregistrement (invalide → refusé + message FR) ; la preview **gèle** sur le
      dernier manifest valide pendant l'édition. Écritures `TemplateStore` : `createUserTemplate`/
      `forkTemplate`/`saveTemplate` (garde contre l'écrasement d'un bundlé)/`deleteUserTemplate`/
      `isUserTemplate`. Dette fast-follow : orphelins des templates vides (création eager au tap),
      partition `fetchPreviewData` dupliquée.
  - **3c — Partage & consentement** (`feat/fondations`) : **fait**. **`.bwidget` = conteneur JSON
    auto-décrit** (`BWidgetArchive`, PAS un zip — une app sandboxée ne peut extraire un zip sans
    `Process` bloqué ni lib SPM interdite ; le JSON ne peut pas porter d'entrée symlink = plus sûr).
    **Import** (`BWidgetImporter`, la surface d'attaque) : valide chaque entrée (whitelist
    manifest/index/assets** + rejet absolu/`..`/doublons) → `TemplateManifest.validated` → installe un
    template **utilisateur** ; confinement d'écriture (resolvingSymlinksInPath + prefix), **rien
    installé sur tout rejet** (8 tests). **UI de consentement** par instance (`PermissionConsentModel`/
    `View`, atteignable via « Permissions… » sur les cartes ; grant `PermissionStore`, le prompt TCC
    reste l'autorité). **Météo par localisation courante** (`config.useCurrentLocation` + `LocationProvider`
    mockable ; entitlement `personal-information.location` + usage string). Galerie « Importer… » /
    « Exporter… » (entitlement `files.user-selected.read-write`). Dette fast-follow : cap taille/entrées
    à l'import, `ImportError: LocalizedError`, purge des grants orphelins au delete.
- **Plan 3 — UI COMPLÈTE (3a+3b+3c) : FAIT & MERGÉ.**
- **Plan 4 — Templates & distribution** : 8-10 templates maison, direction artistique poussée, DMG
  notarized + cask `my-monkeys/tap/better-widgets` (même chaîne qu'OpenSuperWhisper). ⚠️ Provisionner
  **WeatherKit** au portail Apple Developer (capability + clé) pour la météo réelle.
