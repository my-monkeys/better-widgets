# Better Widgets — Design v1

**Date** : 2026-07-03
**Statut** : validé (brainstorming) — en attente de relecture du spec
**Projet** : `~/Documents/my-monkey/better-widgets/` — produit My-Monkey distribuable

## 1. Objectif

App macOS qui permet de **créer facilement de vrais widgets système** (bureau macOS / centre de notifications) : on choisit un template dans une galerie, on le configure via un formulaire, et le widget apparaît dans la galerie de widgets macOS. Un mode avancé permet d'écrire son widget en HTML/CSS/JS libre. L'inspiration directe est le pattern `trmnl-byos` (définir un écran en HTML, l'afficher sur un device), appliqué aux widgets Apple.

**Produit** : distribuable au public (pas un outil perso). **v1 = macOS uniquement**, le moteur est pensé pour être portable vers iOS en v2.

## 2. Décisions actées

| Question | Décision |
|---|---|
| Où vivent les widgets | Vrais widgets système **WidgetKit** (pas de fenêtres flottantes) |
| Audience | Produit My-Monkey distribuable |
| Plateforme v1 | macOS d'abord, iOS en v2 |
| Création | **Templates configurables + mode avancé HTML** |
| Éditeur | **Dans l'app Mac** (pas de compte, pas de sync, offline OK) |
| Sources de données v1 | JSON API custom, infos système, WeatherKit + EventKit, RSS |
| Moteur | **A — HTML → image rendu localement** (WKWebView offscreen → PNG) |

### Approches écartées

- **B — Moteur natif JSON→SwiftUI** : meilleur rendu natif mais incompatible avec le mode avancé HTML, éditeur ×3 plus coûteux.
- **C — Hybride A+B** : deux moteurs à maintenir dès la v1, trop pour un solo-dev. Reste l'état final possible en v3+.

## 3. Architecture

```
Better Widgets.app (SwiftUI, login item barre de menus + fenêtre principale)
├── Éditeur / galerie de templates
├── Moteur de rendu : WKWebView offscreen → PNG (clair + sombre, @2x)
├── DataProviders : json / system / weather / calendar / rss
└── Scheduler : re-rend chaque widget selon son intervalle
        │  écrit PNG + état dans l'App Group partagé
        ▼
Widget Extension (WidgetKit)
└── 3 kinds : Small / Medium / Large, configurables par AppIntent
```

- **Un widget par famille de taille**, déclaré statiquement (contrainte WidgetKit). Le paramètre de configuration (AppIntentConfiguration + AppEntity dynamique) liste les instances créées par l'utilisateur : il pose un « Better Widget Small » puis choisit lequel afficher (pattern Widgetsmith).
- **L'extension est passive** : elle lit le PNG (variante clair/sombre selon `colorScheme`) dans l'App Group et l'affiche, plus des `Link` pour les zones cliquables déclarées. Toute l'intelligence (données, rendu, planification) vit dans l'app.
- **App Group** : images rendues + `state.json` par widget (dernier rendu, erreurs, péremption).

### Composants (frontières)

| Unité | Rôle | API publique |
|---|---|---|
| `TemplateStore` | CRUD templates + instances, validation manifest, import/export `.bwidget` | `list/load/save/import/export` |
| `RenderEngine` | HTML + contexte → PNG clair/sombre @2x à taille exacte | `render(instance, size, theme) → PNG` |
| `DataProviderRegistry` | Résolution et exécution des sources de données | `fetch(sourceSpec) → JSON` |
| `Scheduler` | File de re-rendu par intervalle, coalescing, appelle `WidgetCenter.reloadTimelines` | `schedule(instance)` / `refreshNow(instance)` |
| `SharedStore` (App Group) | Contrat app ↔ extension | chemins PNG + `state.json` |
| Widget Extension | Affichage pur | — |

Chaque unité est testable indépendamment ; l'extension ne dépend que de `SharedStore`.

## 4. Format des widgets

**Template** (unité partageable ; futur format communautaire `.bwidget` = zip) :

```
mon-template/
├── manifest.json
├── index.html        # + CSS/JS inline ou fichiers
└── assets/           # images, fonts
```

`manifest.json` :

```jsonc
{
  "id": "weather-minimal",
  "name": "Météo minimale",
  "version": "1.0.0",
  "sizes": ["small", "medium"],          // tailles supportées
  "refresh": 900,                        // intervalle en secondes (borné par provider)
  "params": [                            // → formulaire généré par l'app
    { "key": "city", "type": "string", "label": "Ville", "default": "Montpellier" },
    { "key": "accent", "type": "color", "label": "Couleur d'accent", "default": "#e8590c" }
  ],
  "sources": [                           // sources de données REQUISES (modèle permission)
    { "key": "weather", "type": "weather" }
  ],
  "links": [                             // zones cliquables optionnelles
    { "rect": "full", "url": "https://weather.com/..." }
  ]
}
```

**Instance** (ce que l'utilisateur crée) : `{ templateId, valeurs des params, taille choisie, overrides }`. Le **mode avancé** crée un template local dont l'utilisateur édite directement `index.html` + `manifest.json`.

**Contrat de rendu** : l'app injecte avant le rendu

```js
window.BW = {
  params: { city: "Montpellier", accent: "#e8590c" },
  data:   { weather: {...} },            // uniquement les sources accordées
  size:   { w: 170, h: 170, family: "small" },
  theme:  "light" | "dark",
  stale:  false                           // true si données périmées (fetch en échec)
}
```

et attend l'événement `BW.ready()` (ou un timeout de 5 s) avant le snapshot — permet aux templates async (fonts, images) de signaler qu'ils sont prêts.

## 5. Pipeline de rendu & refresh

1. Scheduler déclenche (intervalle atteint, param modifié, ou refresh manuel).
2. `DataProviderRegistry.fetch()` pour chaque source du manifest ; en cas d'échec, dernières données connues + `stale: true`.
3. `RenderEngine` : WKWebView offscreen à la taille exacte du widget, injection `window.BW`, attente `BW.ready()`, `takeSnapshot()` @2x — deux passes (clair puis sombre via `color-scheme` forcé).
4. PNG + `state.json` écrits dans l'App Group, `WidgetCenter.reloadTimelines(ofKind:)`.

**Refresh piloté par l'app** (login item) : sur macOS, `reloadTimelines` appelé par l'app locale n'est pas soumis au budget strict d'iOS — c'est ce qui rend le design viable. Intervalles typiques : 60 s (horloge/système), 15 min (météo), 1 h (RSS). Si l'app ne tourne pas : les widgets affichent la dernière image, et au-delà de 2× l'intervalle l'extension superpose un indicateur discret « ouvre Better Widgets ».

## 6. DataProviders

Interface commune : `fetch(spec) → JSON` + intervalle minimal imposé par le provider.

| Type | Contenu | Permission |
|---|---|---|
| `json` | GET URL + headers custom, JSON brut exposé au template | — |
| `system` | batterie, CPU, RAM, disque, uptime, heure | — |
| `weather` | WeatherKit (ville fixe ou localisation) | Localisation (si localisation) ; compte dev Apple requis |
| `calendar` | EventKit : événements + rappels à venir | TCC calendrier/rappels |
| `rss` | RSS/Atom parsé ; images converties en data URI | — |

## 7. Sécurité

Un template communautaire = HTML/JS arbitraire exécuté chez l'utilisateur. Garde-fous v1 :

- WKWebView de rendu **sandboxée sans accès fichiers** (pas de `file://` hors assets du template) ; seules les requêtes **https** sortantes sont autorisées.
- **Modèle permission par template** : on n'injecte que les sources déclarées dans le manifest ; à l'installation d'un template, l'app affiche ce qu'il demande (façon permissions d'extension navigateur). Un template sans source `calendar` ne voit jamais le calendrier.
- Les secrets (headers d'API du provider `json`) sont saisis au niveau de l'**instance**, stockés dans le Keychain, et ne voyagent pas dans un `.bwidget` exporté.

Risque résiduel assumé v1 : un template malveillant peut exfiltrer via https les données qu'on lui a accordées — mitigé par l'écran de permissions et l'absence de galerie en ligne en v1 (import manuel uniquement).

## 8. Éditeur / UX

Fenêtre principale, trois écrans :

1. **Mes widgets** — instances avec mini-preview, statut (OK / stale / erreur), actions (éditer, dupliquer, supprimer, « ajouter au bureau » → guide système, macOS ne permet pas de poser un widget par code).
2. **Galerie** — templates fournis + bouton Importer (`.bwidget`). v1 : **8-10 templates maison** couvrant météo, calendrier, horloge, système, RSS, compteur JSON, citation, image.
3. **Éditeur** — gauche : formulaire de params généré du manifest ; droite : preview live (la vraie webview de rendu, tailles commutables, toggle clair/sombre). Mode avancé : onglet code (CodeMirror embarqué) pour HTML/manifest, preview identique.

Design premium suivant les skills design du monorepo (pas de look générique) ; direction artistique à définir en phase d'implémentation via `brandkit`/`frontend-design`.

## 9. Gestion d'erreurs

- **Fetch en échec** → re-rendu avec dernières données + `stale: true` (le template peut l'afficher) ; badge dans « Mes widgets ».
- **Rendu en échec** (JS error, timeout `BW.ready`) → on conserve l'image précédente, erreur loggée et visible dans l'app (console par widget).
- **Manifest invalide** à l'import → refus avec message précis (validation schéma).
- L'extension ne peut pas échouer : s'il n'y a pas de PNG, elle affiche un placeholder « configure-moi » pointant vers l'app.

## 10. Tests

- **Unit** : validation/parsing des manifests ; chaque DataProvider avec fixtures (réseau mocké).
- **Snapshot** : HTML de référence → PNG comparé (tolérance pixel) — verrouille le RenderEngine.
- **Smoke bout-en-bout** : créer une instance → rendre → vérifier PNG + `state.json` dans l'App Group.
- **Vérification visuelle réelle** (widget posé sur le bureau) avant chaque release.

## 11. Distribution

- Compte Apple Developer requis (WeatherKit + notarization).
- v1 : **DMG notarized + cask `my-monkeys/tap/better-widgets`** — même chaîne qu'OpenSuperWhisper.
- App Store : envisageable ensuite, le design est sandbox-compatible (App Group, WKWebView, pas d'API privée).
- Attribution **My-Monkey** (jamais de nom perso).
- Site vitrine `better-widgets.my-monkey.fr` : hors périmètre v1.

## 12. Périmètre

**v1** : app macOS + extension WidgetKit (S/M/L), 8-10 templates maison, 5 DataProviders, éditeur avec mode avancé, import/export `.bwidget`, DMG notarized.

**Hors v1 (préparé par l'architecture)** : iOS (le moteur HTML→image est portable ; le refresh en arrière-plan iOS est la vraie difficulté — rendu serveur optionnel à évaluer à ce moment-là), galerie communautaire en ligne, sync/comptes, éditeur visuel drag & drop, widgets interactifs au-delà des liens, moteur natif SwiftUI (approche C).

## 13. Risques & inconnues

| Risque | Mitigation |
|---|---|
| `takeSnapshot` WKWebView : fiabilité offscreen (fonts, timing) | L'événement `BW.ready()` + spike technique en tout début d'implémentation |
| Refresh WidgetKit macOS moins permissif que prévu | Vérifier au spike ; au pire coalescer les reloads (1 reload → toutes les timelines) |
| Poids : N webviews simultanées | Pool de 1-2 webviews réutilisées, rendus sérialisés |
| WeatherKit = coût/quota compte dev | Quota gratuit 500k appels/mois, largement suffisant ; cache 15 min |
