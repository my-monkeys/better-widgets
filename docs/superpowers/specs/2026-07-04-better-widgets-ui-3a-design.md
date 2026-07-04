# Better Widgets — Design UI 3a : Coquille d'app + « Mes widgets »

**Date** : 2026-07-04
**Statut** : validé (brainstorming) — en attente de relecture du spec
**Projet** : `~/Documents/my-monkey/better-widgets/` — sous-plan 3a de la phase UI
**Spec produit de référence** : `docs/superpowers/specs/2026-07-03-better-widgets-design.md` (§8 Éditeur/UX)

## 1. Contexte & décisions cadre

Plans 1-2 sont faits & mergés : moteur de rendu HTML→PNG, extension WidgetKit (3 kinds), providers (`json`/`system`/`rss`/`calendar`/`weather`), modèle de permission, sandbox WebView. **L'UI de l'app se limite aujourd'hui à un `MenuBarExtra` minimal.** La phase UI (Plan 3 du spec produit) est **découpée en 3 sous-plans** :

- **3a (ce document)** : coquille d'app (fenêtre principale + navigation), écran « Mes widgets », Galerie minimale (créer une instance), langage visuel partagé.
- **3b** (spec ultérieur) : éditeur riche — formulaire de params généré du manifest + **preview live** (la vraie webview de rendu) + mode avancé code (CodeMirror).
- **3c** (spec ultérieur) : import/export `.bwidget`, secrets `json` dans le Keychain, UI de consentement (grants du `PermissionStore`).

**Direction artistique actée** : **éditorial minimal** (skill `minimalist-ui`) — mono chaud, typo hiérarchisée, accent orange `#e8590c` parcimonieux, grille éditoriale. Décision produit de Maxim ; s'applique à toute l'UI (3a fixe les tokens, 3b/3c les réutilisent).

## 2. Périmètre 3a

**Dans 3a** : fenêtre principale, navigation sidebar (Mes widgets / Galerie), écran Mes widgets (cartes avec preview PNG réel + statut + actions dupliquer/supprimer/ajouter-au-bureau), Galerie **minimale** (liste des templates bundlés + « Créer » = instancie avec params par défaut), `DesignTokens` partagés, CRUD d'instances dans `AppState`.

**Hors 3a (report explicite)** : édition des params (3b), preview live dans l'éditeur (3b), mode avancé code (3b), import/export `.bwidget` (3c), secrets Keychain (3c), écran de consentement (3c). En 3a, le bouton « Éditer » d'une carte est **présent mais désactivé** (« bientôt »), et la création utilise les **valeurs par défaut** du manifest (pas de formulaire).

## 3. Architecture

```
BetterWidgetsApp (LSUIElement)
├── MenuBarExtra (existant) + item « Ouvrir Better Widgets » → active la fenêtre
└── WindowGroup "main"
    └── MainWindowView : NavigationSplitView
        ├── sidebar : Section("Mes widgets"), Section("Galerie")
        └── detail : MyWidgetsView | GalleryView selon la sélection
```

- **Fenêtre summonnée** : l'app reste `LSUIElement` (menu-bar, pas d'icône dock permanente). « Ouvrir Better Widgets » fait `NSApp.activate(ignoringOtherApps: true)` + ouvre/ramène la fenêtre `main`. Fermer la fenêtre ne quitte pas l'app (le scheduler continue).
- **`NavigationSplitView`** (natif macOS 14) : sidebar fine + detail. Sélection persistée en `@State`/`@SceneStorage` (défaut : « Mes widgets »).

### Composants (frontières)

| Unité | Rôle | API publique |
|---|---|---|
| `MainWindowView` | Chrome de fenêtre + `NavigationSplitView` + routage sidebar→detail | `body` ; consomme `AppState` |
| `MyWidgetsView` | Grille de cartes des instances + état vide | consomme `state.instances` + statut |
| `WidgetCard` | Une carte : PNG + nom + statut + actions | `init(instance:status:onDuplicate:onDelete:onAddToDesktop:)` |
| `GalleryView` | Liste des templates bundlés + « Créer » | consomme `state.templates.list()` ; `onCreate(templateId:size:)` |
| `AddToDesktopGuide` | Feuille (sheet) expliquant comment poser le widget sur le bureau | présentation modale, pas d'action système |
| `DesignTokens` | Couleurs / espacements / échelle typo / statut→couleur | statique, sans état |
| `AppState` (étendu) | CRUD d'instances + expose le statut par instance | `createInstance/deleteInstance/duplicateInstance` + `statusFor` |

Chaque vue est pilotée par `AppState` (source de vérité unique déjà en place) ; aucune vue ne fait d'I/O directe (le CRUD passe par `AppState`).

## 4. `AppState` — CRUD d'instances

`AppState` (Plan 1) tient déjà `@Published var instances`, `shared: SharedStore`, `templates: TemplateStore`, le `scheduler` et `pipeline`. On ajoute :

- `func createInstance(templateId: String, size: WidgetSize) -> WidgetInstance` — nom par défaut = nom du template ; `paramValues` vide (⇒ le pipeline applique les défauts du manifest) ; ajoute à `instances`, `saveInstances`, relance le scheduler et déclenche un refresh immédiat de la nouvelle instance.
- `func deleteInstance(_ id: UUID)` — retire de `instances`, `saveInstances`, relance le scheduler ; supprime aussi les PNG/state de l'App Group pour cette instance (nettoyage — nouvelle méthode `SharedStore.removeInstance(id:)`).
- `func duplicateInstance(_ id: UUID) -> WidgetInstance?` — copie profonde avec nouvel `id` et nom « <nom> (copie) », mêmes `paramValues`/`size`/`templateId` ; persiste + refresh.
- `func status(for id: UUID) -> InstanceStatus` — mappe `InstanceState` en `enum InstanceStatus { case ok, stale, error(String) }` (pour la pastille de carte).

**Invariant scheduler** : après toute mutation de la liste, `scheduler.stop()` puis `scheduler.start(instances:)` — MAIS le `Scheduler` de Plan 1 ne supporte pas `start` après `stop` (continuation finie ; cf. dette notée). **3a corrige ce point** : ajouter `Scheduler.restart(instances:)` qui recrée le stream/worker interne, ou rendre `start` idempotent (réinitialise le worker). C'est le prérequis du CRUD → traité comme une tâche du plan 3a.

## 5. Écran « Mes widgets »

- **Grille** responsive de `WidgetCard` (largeur de carte ~ proportionnelle à la taille du widget : small carré, medium/large plus larges). Le visuel = le vrai PNG lu via `SharedStore.renderURL(instanceId:theme:)`, thème selon `colorScheme` de l'app. Si pas encore de PNG (juste créé) → placeholder « rendu en cours ».
- **Statut** : pastille + libellé — vert « à jour », ambre « données périmées » (stale), rouge « erreur » (+ `lastError` en tooltip/`help`).
- **Actions par carte** : Dupliquer, Supprimer (confirmation via `confirmationDialog`), « Ajouter au bureau » (ouvre `AddToDesktopGuide`), Éditer (désactivé en 3a, `help` = « Bientôt »).
- **État vide** : composition éditoriale (titre + une ligne + CTA « Parcourir la galerie »), pas de `text-center` par flemme.

## 6. Galerie minimale

- Liste/grille des templates bundlés (`TemplateStore.list()` → `TemplateManifest`), chacun avec nom, tailles supportées, sources déclarées (badges — utile pour préfigurer le consentement de 3c), et un bouton **« Créer »**. « Créer » demande la taille (parmi `manifest.sizes`) via un petit menu puis appelle `AppState.createInstance`. Pas de preview live ni de formulaire en 3a (3b).
- Import `.bwidget` = **hors 3a** (3c) — **pas de bouton Importer en 3a** (ajouté en 3c), pour ne pas exposer une action morte.

## 7. Langage visuel (`DesignTokens`)

`Core/DesignTokens.swift` — source unique, réutilisée par 3b/3c :

- **Couleurs** : `background` (blanc cassé chaud clair / near-black chaud sombre), `surface`, `textPrimary`, `textSecondary`, `separator`, `accent = #e8590c`, `statusOK`/`statusStale`/`statusError`. Toutes déclinées clair/sombre (via `Color` asset-less, adaptatives).
- **Typo** : échelle nette (≥ 3 tailles distinctes + contraste de poids) — `titleXL`, `title`, `label`, `caption` en SF Pro.
- **Espacement** : échelle (4/8/12/16/24/40/80) ; sections desktop qui respirent.
- **Rayons/bordures** : rayon de carte discret, bordure 1px `separator` plutôt qu'ombre molle.

Interdits (rappel CLAUDE.md monorepo) : pas de gradient violet/bleu générique, pas de glassmorphism, pas d'ombres bleutées molles identiques, pas de `text-center` par défaut.

## 8. Gestion d'erreurs

- Statut d'instance dérivé de `InstanceState` (déjà persisté par le pipeline) ; aucune nouvelle source d'erreur côté UI.
- Suppression = destructive → `confirmationDialog` obligatoire.
- « Ajouter au bureau » n'exécute rien (macOS ne pose pas de widget par code) : c'est une **fiche pédagogique** (capture/gif du flux « Modifier les widgets »).
- Création : si `TemplateStore.list()` est vide (cas improbable, templates bundlés absents), la Galerie montre un état vide explicite plutôt qu'un crash.

## 9. Tests

- **Unit `AppState`** : `createInstance` (ajout + persistance + défauts), `deleteInstance` (retrait + `SharedStore.removeInstance` appelé), `duplicateInstance` (nouvel id, nom « (copie) », mêmes params) — via un `SharedStore`/`TemplateStore` sur dossier temp + un `Scheduler` avec refresher factice (réutilise les fakes de Plan 1).
- **Unit `Scheduler.restart`** : après `stop()` puis `restart(instances:)`, un refresh est bien déclenché (corrige la dette « start-after-stop »).
- **Unit view-model `WidgetCard`** : mapping `InstanceState → InstanceStatus` (ok/stale/error) et choix du PNG selon le thème.
- **Unit `SharedStore.removeInstance`** : supprime les 2 PNG + le state, no-op si absent.
- **Vérification réelle** (skill `verify`/screenshot) : ouvrir la fenêtre, créer un widget depuis la Galerie, le voir apparaître dans Mes widgets avec son rendu, dupliquer, supprimer. Faite avant clôture du plan 3a.

## 10. Risques & inconnues

| Risque | Mitigation |
|---|---|
| `MenuBarExtra` + `WindowGroup` cohabitation (activation, cycle de vie fenêtre fermée) | `NSApplicationDelegateAdaptor` déjà en place ; « Ouvrir » via `NSApp.activate` + `openWindow` ; test réel |
| `Scheduler` ne supporte pas `start` après `stop` (dette Plan 1) | Tâche dédiée `restart(instances:)` en 3a, testée |
| Grille SwiftUI + N vraies images PNG rechargées | Charger le PNG en `NSImage(contentsOf:)` à la demande par carte ; recharger sur changement de `state`/thème ; pas de sur-optimisation prématurée |
| Rendu visuel « premium » pas garanti par le typecheck | Vérif navigateur/screenshot + skill `minimalist-ui` invoquée à l'implémentation |

## 11. Hors périmètre (rappel)

Édition de params, preview live, mode avancé code (**3b**) ; import/export `.bwidget`, Keychain, consentement (**3c**) ; iOS, galerie communautaire en ligne, sync/comptes (spec produit, hors Plan 3).
