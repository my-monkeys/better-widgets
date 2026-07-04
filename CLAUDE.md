# CLAUDE.md — `better-widgets`

App macOS barre de menus + extension WidgetKit qui rend des templates HTML en PNG clair/sombre
(WKWebView offscreen) pour afficher de vrais widgets système. Voir [`README.md`](README.md) pour
le pitch produit ; ce fichier couvre les conventions et gotchas pour continuer le développement.

**Spec** : [`docs/superpowers/specs/2026-07-03-better-widgets-design.md`](docs/superpowers/specs/2026-07-03-better-widgets-design.md)
**Plan 1 (fondations, ce qui est fait)** : [`docs/superpowers/plans/2026-07-03-better-widgets-fondations.md`](docs/superpowers/plans/2026-07-03-better-widgets-fondations.md)
**Plan 2 (providers & permissions, ce qui est fait)** : [`docs/superpowers/plans/2026-07-03-better-widgets-providers-permissions.md`](docs/superpowers/plans/2026-07-03-better-widgets-providers-permissions.md)
**Plan 3a (coquille d'app + Mes widgets, ce qui est fait)** : [spec](docs/superpowers/specs/2026-07-04-better-widgets-ui-3a-design.md) · [plan](docs/superpowers/plans/2026-07-04-better-widgets-ui-3a.md)

## Stack

Swift 5.9 · SwiftUI · WidgetKit (`AppIntentConfiguration`) · WKWebView (moteur de rendu) ·
XcodeGen · macOS 14+ · Xcode 27. Pas de dépendance externe (SPM vide) — tout est Foundation/
AppKit/WebKit/WidgetKit.

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

Côté **app UI** (Plan 3a, dans `BetterWidgets/App/`, target app uniquement) : `AppState` (source de
vérité `@MainActor`, **injectable** : init désigné + convenience ; CRUD create/delete/duplicate +
`status(for:)` → `InstanceStatus{ok,pending,stale,error}`), `MainWindowView` (`Window(id:"main")`
singleton + `NavigationSplitView` Mes widgets/Galerie), `MyWidgetsView` (grille de cartes, refresh
via `TimelineView(.periodic)`), `WidgetCard` (+ `WidgetCardModel` testable), `GalleryView`,
`AddToDesktopGuide`. Les fichiers de logique testés (`AppState.swift`, `WidgetCard.swift`) sont
ajoutés individuellement aux sources de `BetterWidgetsTests` dans `project.yml` (jamais le dossier
`App/` entier — sinon le `@main` entre dans le bundle de test).

`SharedStore.swift` et `Core/Models/**` sont compilés dans **les deux** targets (app + extension)
via `project.yml` — pas de framework partagé, YAGNI tant qu'il n'y a que ces deux consommateurs.
`Core/Render` et `Core/Data` ne sont compilés que dans l'app : l'extension ne fait ni rendu ni
fetch, elle lit seulement les PNG déjà écrits par l'app dans l'App Group.

## Commande de test canonique

```bash
xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets \
  -destination 'platform=macOS' -quiet
```

75 tests (`ManifestTests`, `Plan2ManifestTests`, `SharedStoreTests`, `TemplateStoreTests`,
`RenderEngineTests`, `NavigationPolicyTests`, `TemplateAssetSchemeHandlerTests`,
`DataProviderTests`, `RSSDataProviderTests`, `RSSFeedParserTests`, `CalendarDataProviderTests`,
`WeatherDataProviderTests`, `PermissionStoreTests`, `RenderPipelineTests`, `SchedulerTests`,
`WidgetSizeTests`, `SmokeTests`, `DesignTokensTests`, `AppStateTests`, `WidgetCardModelTests`).
Doit rester vert avant tout commit. Les vues SwiftUI n'ont pas de tests unitaires (gate = build vert
+ vérif réelle) ; la logique (CRUD, model, scheduler, store, tokens) est testée.

Smoke E2E (build + lance l'app + vérifie les PNG dans l'App Group) : `./scripts/smoke.sh` — voir
[`README.md`](README.md) pour le détail de ce qu'il fait et pourquoi il tue le process par son nom
exact (`BetterWidgets`, pas `Better Widgets`).

## Convention de commits

Conventional Commits (`feat:`, `fix:`, `test:`, `chore:`, …), auteur `MaximCosta
<maxim@users.noreply.github.com>` (déjà configuré dans le repo). **Aucune mention d'IA** dans les
messages de commit.

## État d'avancement des plans

- **Plan 1 — Fondations** (`feat/fondations`, ce plan) : **fait**. Pipeline bout-en-bout : app →
  bootstrap → rendu `hello-clock` (clair+sombre) → App Group → extension enregistrée
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
  WebView). Trois templates démo bundlés exercent ces providers : `feed-list` (rss, sans
  permission), `agenda` (calendar, gère `__denied`), `weather-now` (weather, gère `__denied`).
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
  - **3b — Éditeur** : formulaire de params généré du manifest + **preview live** (vraie webview) +
    mode avancé code (CodeMirror). Branche le bouton « Éditer » des cartes. Inclura les secrets `json`
    dans le Keychain (saisis au niveau de l'instance).
  - **3c — Partage & consentement** : import/export `.bwidget` (⚠️ le confinement symlink-safe de la
    WebView, fait en Plan 2, est un **prérequis dur** avant l'import), UI de consentement (grants du
    `PermissionStore`), + météo par localisation courante (`CLLocationManager`).
- **Plan 4 — Templates & distribution** : 8-10 templates maison, direction artistique poussée, DMG
  notarized + cask `my-monkeys/tap/better-widgets` (même chaîne qu'OpenSuperWhisper). ⚠️ Provisionner
  **WeatherKit** au portail Apple Developer (capability + clé) pour la météo réelle.
