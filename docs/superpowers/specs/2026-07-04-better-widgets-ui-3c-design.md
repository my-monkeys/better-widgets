# Better Widgets — Design UI 3c : Import/export `.bwidget` + consentement + météo localisation

**Date** : 2026-07-04
**Statut** : validé (brainstorming) — en attente de relecture du spec
**Projet** : `~/Documents/my-monkey/better-widgets/` — sous-plan 3c de la phase UI
**Réfs** : spec produit `2026-07-03-better-widgets-design.md` (§7 sécurité/secrets, §8 galerie) ; specs 3a/3b-1/3b-2

## 1. Contexte & découpage

Plans 1, 2, 3a, 3b-1, 3b-2 faits & mergés : moteur, extension, providers, permissions, coquille d'app, éditeur de params + preview + secrets Keychain, mode avancé code (CodeMirror + templates utilisateur). Acquis réutilisés par 3c :
- `PermissionStore` : `grantedTypes(instanceId:)`, `setGrantedTypes(_:instanceId:)`, `grant(type:instanceId:)`.
- `TemplateStore` : écritures utilisateur (`createUserTemplate`, `saveTemplate(id:html:manifestJSON:)`, `isUserTemplate`), `templateDirectory(id:)`.
- Durcissement WebView **symlink-safe** (`resolveTemplateAsset`, Plan 2) — le confinement d'assets est le **prérequis dur** de l'import, désormais en place.
- `SourceSpec.requiresConsent` / `consentRequiredTypes = ["calendar","weather"]`.
- `WeatherDataProvider` derrière `WeatherFetching` + `geocodeCity` (3b-1/Plan 2).

3c est le **dernier sous-plan de la phase UI (Plan 3)** : import/export `.bwidget`, UI de consentement des permissions, météo par localisation courante.

DA : **éditorial minimal** (`DesignTokens`) ; skill `minimalist-ui` pour les vues.

## 2. Périmètre 3c

**Dans 3c** : (1) format `.bwidget` (`BWidgetArchive` encode/decode) + export depuis la Galerie ; (2) import + validation sandbox + installation comme template utilisateur + écran de consentement ; (3) UI de consentement des grants (à l'import ET depuis « Mes widgets ») ; (4) `weather` par localisation courante (`config.useCurrentLocation` + `LocationProvider`).

**Hors 3c** : galerie communautaire en ligne ; signature/notarization des `.bwidget` ; distribution de l'app (Plan 4) ; nettoyage des instances orphelines.

## 3. Format `.bwidget` & `BWidgetArchive`

- Un `.bwidget` = **archive zip** d'un template : `manifest.json` + `index.html` + `assets/**` optionnels. **Aucun secret ni donnée d'instance** (les secrets sont Keychain, liés à l'instance — cf. 3b-1 ; un template ne contient pas de secret par construction).
- `BWidgetArchive` (dans `Core/`) :
  - `static func export(templateDir: URL) throws -> Data` — zip du dossier de template (manifest + html + assets), retourne les octets.
  - `static func entries(in data: Data) throws -> [(path: String, data: Data)]` — liste les entrées du zip (chemins relatifs).
  - Zip via `Foundation` (`Archive`/`Compression`) — **pas de dépendance externe**. Si l'API `Compression`/`libarchive` ne suffit pas pour un vrai zip multi-fichiers en pur Foundation, on utilise le zip natif via `NSFileCoordinator`/`FileManager.zipItem` (implémentation à trancher au plan ; contrat = round-trip fidèle + énumération des entrées).

## 4. Import : validation sandbox + installation

Bouton « Importer » dans la Galerie → `NSOpenPanel` filtré `.bwidget`. `BWidgetImporter` (dans `Core/`) fait, dans l'ordre :

1. **Décompresse** dans un dossier **temporaire** (jamais directement dans le store).
2. **Valide** (tout échec → refus, message précis, temp nettoyé, rien installé) :
   - le zip ne contient **que** `manifest.json`, `index.html`, et des entrées sous `assets/` ;
   - **chaque chemin d'entrée reste dans le dossier** : rejet des chemins absolus, des composants `..`, des symlinks — via la même logique de confinement que `resolveTemplateAsset` (Plan 2, symlink-safe) ;
   - `manifest.json` présent et passe `TemplateManifest.validated` ; `index.html` présent.
3. **Installe** comme **template utilisateur** : nouvel id unique (slug du `manifest.name` + suffixe), réécrit `manifest.id`, écrit via `TemplateStore` (marqueur `.user`). Retourne l'id installé.
4. **Consentement** : si le manifest déclare des sources `requiresConsent`, présente l'écran de consentement (section 5) pour préparer les grants. Sinon, l'import est simplement disponible dans la Galerie.

Rien n'est fetché tant que les sources consent-required ne sont pas accordées (le pipeline injecte déjà `__denied`). Interface : `BWidgetImporter.import(archive: Data, into store: TemplateStore) throws -> String` (id) + `enum ImportError: Error { case badArchive, unsafeEntry(String), missingFile(String), invalidManifest(String) }`.

## 5. UI de consentement des permissions

- `PermissionConsentModel` (view-model) : pour une instance donnée, liste les **types consent-required** de son template (`manifest.sources.filter(\.requiresConsent).map(\.type)`, dédupliqués), et l'état accordé (depuis `PermissionStore.grantedTypes`). `toggle(type:granted:)` écrit via `setGrantedTypes`.
- `PermissionConsentView` (feuille) : un toggle « Autoriser » par type, libellé FR (« Calendrier », « Météo »), une phrase expliquant ce que le widget verra. Bouton Terminé.
- **Accès** : (a) à l'installation d'un template importé qui déclare des sources consent-required — mais le consentement se fait au niveau **instance**, donc on présente l'écran quand l'utilisateur **crée une instance** de ce template (ou immédiatement si l'import propose « créer maintenant ») ; (b) depuis « Mes widgets », un bouton « Permissions… » sur la carte d'une instance dont le template exige un consentement (via `WidgetCard`).
- **Autorité TCC** : l'écran de l'app décide « ce widget a le droit de demander » (le grant `PermissionStore`). Le **prompt système macOS** (EventKit / localisation) reste la source d'autorité : il se déclenche au premier accès réel du provider. Si l'utilisateur refuse au niveau système, la source devient un `failedKey`/`stale` (déjà géré) même si le grant app est présent.

Décision assumée : le consentement est **par instance** (cohérent avec `PermissionStore` déjà keyé par `instanceId`) ; deux instances du même template ont des grants indépendants.

## 6. Météo par localisation courante

- `WeatherDataProvider` : nouvelle branche. `config.useCurrentLocation == "true"` → résout les coordonnées via un **`LocationProvider`** au lieu de `city`/`lat`+`lon`.
- `protocol LocationProvider { func currentCoordinates() async throws -> (lat: Double, lon: Double) }` + `CoreLocationProvider` (vrai, `CLLocationManager` avec permission TCC localisation) + injection d'un fake en test. `WeatherDataProvider.init` gagne un `location: LocationProvider` (défaut `CoreLocationProvider()`).
- Ordre de résolution dans `fetch` : si `useCurrentLocation` → `location.currentCoordinates()` ; sinon lat/lon explicites ; sinon `city` (géocodage) ; sinon throw.
- `weather` reste consent-required → la localisation courante n'est utilisée que si l'instance a accordé `weather`, et CLLocationManager déclenche son propre prompt TCC. Localisation indisponible/refusée → throw → `failedKey`/`stale`.
- `Info.plist` : `NSLocationWhenInUseUsageDescription` (usage string FR) ajouté via `project.yml`.

## 7. Architecture & composants

```
Core/
├── BWidgetArchive.swift     # zip encode/decode d'un template
├── BWidgetImporter.swift    # décompresse → valide (sandbox) → installe user template
├── Data/WeatherDataProvider.swift  # MODIF : useCurrentLocation + LocationProvider
└── LocationProvider.swift   # protocol + CoreLocationProvider
App/
├── GalleryView.swift        # MODIF : Importer (NSOpenPanel) + Exporter (NSSavePanel) par carte
├── PermissionConsentModel.swift  # view-model consentement
├── PermissionConsentView.swift   # feuille de consentement
├── WidgetCard.swift         # MODIF : « Permissions… » si le template exige un consentement
└── MyWidgetsView.swift      # MODIF : présenter PermissionConsentView (.sheet)
```

| Unité | Rôle | dépend de |
|---|---|---|
| `BWidgetArchive` | zip ↔ entrées (round-trip) | Foundation |
| `BWidgetImporter` | import sûr → template utilisateur | `BWidgetArchive`, `resolveTemplateAsset` (confinement), `TemplateManifest.validated`, `TemplateStore` |
| `PermissionConsentModel` | grants d'une instance | `PermissionStore`, `TemplateStore.manifest` |
| `LocationProvider`/`CoreLocationProvider` | coordonnées courantes | CoreLocation |
| `WeatherDataProvider` (étendu) | +localisation courante | `LocationProvider` |

## 8. Gestion d'erreurs

- **Import** : zip corrompu (`badArchive`), entrée hors-dossier/symlink/`..` (`unsafeEntry`), fichier requis manquant (`missingFile`), manifest invalide (`invalidManifest`) → refus + message FR précis, dossier temp supprimé, **rien installé**.
- **Export** : échec d'écriture (permissions, disque) → alerte ; le `NSSavePanel` gère l'écrasement.
- **Consentement** : accorder le grant app n'accorde pas le TCC système ; refus TCC → source `__denied`-équivalent via `failedKey`/`stale` (déjà géré). L'écran reflète l'état du grant app, pas l'état TCC (qu'on ne peut pas lire de façon fiable sans déclencher le prompt).
- **Localisation** : indisponible/refusée → `weather` throw → `failedKey`/`stale`, le template affiche son état.

## 9. Sécurité

- **Import = surface d'attaque principale.** Le confinement d'entrées (pas de chemin absolu, `..`, symlink — réutilise le durcissement symlink-safe de Plan 2) empêche un `.bwidget` d'écrire hors de son dossier de template. Le HTML importé tourne dans la **même WebView confinée** (`bwasset://`, `file://` bloqué) que tout template — aucun privilège supplémentaire.
- **Pas de secret exporté** : `BWidgetArchive.export` ne lit que `manifest.json`/`index.html`/`assets` ; les secrets vivent sur l'instance (Keychain), jamais dans un template.
- **Risque résiduel assumé** (spec §7) : un template autorisé peut exfiltrer via https les données qu'on lui a accordées — mitigé par l'écran de consentement + import **manuel uniquement** (pas de galerie en ligne en v1). Pas de signature/notarization des `.bwidget` en 3c.

## 10. Tests

- **Unit `BWidgetArchive`** : round-trip `export`→`entries` d'un template (manifest+html+asset) fidèle ; énumération correcte des chemins.
- **Unit `BWidgetImporter`** : archive valide → installe un template utilisateur (marqueur `.user`, nouvel id, manifest réécrit) ; **rejets** : entrée à chemin absolu, entrée avec `..`, entrée symlink, manifest invalide, `index.html` manquant, entrée hors whitelist → `ImportError` + rien installé. Réutilise/valide le confinement symlink-safe.
- **Unit `PermissionConsentModel`** : liste les types consent-required du template, `toggle` écrit dans un `PermissionStore` (temp), état lu correctement, isolation par instance.
- **Unit `WeatherDataProvider` (useCurrentLocation)** : `useCurrentLocation=true` appelle le `LocationProvider` (fake) et ignore city/lat/lon ; indisponible → throw ; ordre de résolution (currentLocation > lat/lon > city) respecté.
- **Vues** (`PermissionConsentView`, boutons Import/Export de la Galerie) : build + vérif réelle (exporter un template → fichier `.bwidget` créé ; le ré-importer → apparaît comme template utilisateur ; un `.bwidget` malveillant fabriqué à la main → refusé ; toggler une permission → grant écrit).

## 11. Risques & inconnues

| Risque | Mitigation |
|---|---|
| Zip multi-fichiers en pur Foundation | Spike au 1er jet (`BWidgetArchive`) ; fallback `FileManager.zipItem`/`NSFileCoordinator` ou une lib zip Foundation-only ; contrat = round-trip + énumération |
| Confinement des entrées d'import | Réutilise `resolveTemplateAsset` (symlink-safe, Plan 2) ; tests de rejet explicites (absolu/`..`/symlink) |
| CLLocationManager async + permission TCC | `LocationProvider` protocole mockable ; le vrai `CoreLocationProvider` non testé unitairement (comme WeatherKitService) ; prompt TCC = autorité système |
| Consentement app vs TCC système | L'écran gère le grant app ; le TCC reste au système ; documenté ; refus TCC → stale (déjà géré) |
| WeatherKit non provisionné | La localisation courante build+teste (fake) mais ne renvoie de vraies données qu'après provisioning portail (action Maxim) — comme tout `weather` |

## 12. Hors périmètre (rappel)

Galerie communautaire en ligne ; signature/notarization des `.bwidget` ; distribution DMG/cask (**Plan 4**) ; nettoyage des instances orphelines ; lecture de l'état TCC système sans déclencher le prompt.
