# Better Widgets — Design UI 3b-1 : Éditeur de params + preview live + secrets Keychain

**Date** : 2026-07-04
**Statut** : validé (brainstorming) — en attente de relecture du spec
**Projet** : `~/Documents/my-monkey/better-widgets/` — sous-plan 3b-1 de la phase UI
**Réfs** : spec produit `2026-07-03-better-widgets-design.md` (§7 sécurité/secrets, §8 éditeur) ; spec UI `2026-07-04-better-widgets-ui-3a-design.md`

## 1. Contexte & découpage

Plans 1, 2, 3a faits & mergés : moteur de rendu, extension WidgetKit, providers, permissions, coquille d'app (fenêtre + Mes widgets + Galerie minimale + `DesignTokens`). Le bouton **« Éditer » d'une carte est présent mais désactivé** en 3a — ce sous-plan l'active.

La phase éditeur (Plan 3b) est **scindée** (décision produit) :
- **3b-1 (ce document)** : éditeur de **params** (formulaire généré du manifest) + **preview live** + **secrets Keychain** pour les sources `json`.
- **3b-2 (spec ultérieur)** : mode avancé **code** (CodeMirror embarqué, écrire/forker des templates HTML/manifest).

DA : **éditorial minimal** (déjà actée, `DesignTokens`). Skill `minimalist-ui` à invoquer pour toute vue.

## 2. Périmètre 3b-1

**Dans 3b-1** : activer « Éditer » d'une carte → écran éditeur (formulaire de params à gauche, preview live à droite avec bascule taille + clair/sombre) ; Enregistrer/Annuler ; `AppState.updateInstance` ; `SecretResolver` + stockage Keychain des secrets de sources `json` ; résolution des secrets dans `RenderPipeline` (et dans la preview). 

**Hors 3b-1** : mode avancé code / CodeMirror (3b-2) ; import/export `.bwidget` + UI de consentement (3c) ; météo par localisation courante (3c). Le formulaire édite **les params déclarés** du manifest ; il ne crée pas de nouveaux params ni ne modifie le HTML.

## 3. Architecture

```
Fenêtre principale (3a) — MyWidgetsView
└── WidgetCard « Éditer » (activé) → onEdit(instance)
    └── .sheet → WidgetEditorView(instance, onSave, onCancel)   [NOUVEAU]
        ├── ParamFormView       (gauche) — lignes générées de manifest.params + SecureFields secrets
        └── LivePreviewView     (droite) — WKWebView vivante (NSViewRepresentable) + toggles taille/thème
```

- **Présentation** : `.sheet` sur la fenêtre principale (l'éditeur est modal par widget). Fermer = Annuler (confirmation si modifs non sauvegardées).
- **État d'édition** : `@StateObject WidgetEditorModel` détient la **copie de travail** (`paramValues` éditables + secrets saisis + taille/thème de preview), isolée de l'instance réelle jusqu'à Enregistrer.

### Composants (frontières)

| Unité | Rôle | API |
|---|---|---|
| `WidgetEditorModel` | Copie de travail (params + secrets + preview size/theme), validation, produit le `RenderContext` de preview | `@Published paramValues/secrets/previewSize/previewTheme` ; `func save()` ; `func previewContext() -> RenderContext` |
| `WidgetEditorView` | Layout 2 volets + barre Enregistrer/Annuler | consomme `WidgetEditorModel` + `AppState` |
| `ParamFormView` | Une ligne par `ParamSpec` (par type) + `SecureField` par secret déclaré | binding sur le model |
| `LivePreviewView` | `NSViewRepresentable` WKWebView vivante, injecte `window.BW`, re-injecte params (debounce) | `init(html, baseURL, contextProvider)` |
| `SecretResolver` | Stocke/lit les secrets Keychain ; mappe `secret.<H>`→`header.<H>` | `set/get/delete` + `resolvedConfig(for source, instanceId:)` |
| `KeychainStore` | Accès Keychain bas niveau (get/set/delete par clé) | `set/get/delete(key:)` |
| `AppState.updateInstance` | Persiste une instance modifiée | `func updateInstance(_ instance: WidgetInstance)` |

## 4. `AppState.updateInstance`

`func updateInstance(_ updated: WidgetInstance)` : remplace l'instance de même `id` dans `instances` (si absente, no-op), `saveInstances`, `scheduler.restart(instances:)` + refresh de l'instance modifiée. C'est le seul chemin de persistance d'une édition.

## 5. Formulaire de params

Généré de `manifest.params` (récupéré via `templates.manifest(id:)`). Une ligne par `ParamSpec` selon `type` :

- `string` → `TextField` (valeur ⇄ `paramValues[key]`)
- `color` → `ColorPicker` lié à l'hex (`#rrggbb` ⇄ `Color`), conversion aux frontières
- `number` → `TextField` (validation numérique douce ; stocké en String comme tous les params)
- `url` → `TextField` (pas de validation stricte ; le provider valide https à l'usage)

Chaque ligne montre le `label` du `ParamSpec`. Valeur initiale = `instance.paramValues[key] ?? spec.default`. Les modifs vont dans la **copie de travail** du model, pas dans l'instance.

## 6. Preview live

- `LivePreviewView` = `NSViewRepresentable` encapsulant une **WKWebView vivante** (pas un snapshot). Config identique au `RenderEngine` : scheme handler `bwasset://` confiné au dossier du template + `NavigationPolicy` (aucun `file://`). Charge le HTML du template avec `window.BW` injecté au `documentStart`.
- **Données** : récupérées **une fois à l'ouverture** de l'éditeur via `DataProviderRegistry.fetchAll` (en respectant les permissions du `PermissionStore` → sources consent-required non accordées = `__denied`), en résolvant les secrets via `SecretResolver`. Réutilisées pendant l'édition ; un bouton « Rafraîchir la preview » permet un refetch explicite.
- **Réactivité** : sur édition d'un param (debounce ~300 ms), on **ré-injecte `window.BW.params`** via `evaluateJavaScript` + un event `bwParamsChanged` que le template peut écouter ; à défaut, reload léger avec le nouveau `BW`. Le toggle **taille** redimensionne la WKWebView à `pointSize` de la taille choisie ; le toggle **thème** change l'`appearance` (clair/sombre) et ré-injecte `BW.theme`.
- Fidélité : même HTML + même contrat `BW` + même confinement que le rendu final → la preview reflète le rendu WidgetKit.

## 7. Secrets Keychain

**Modèle** : une source `json` déclare un secret via une clé de config préfixée `secret.<HeaderName>` (ex. `secret.Authorization`). Distinct de `header.<Name>` (en-tête non secret, déjà géré par `JSONDataProvider` en Plan 2).

- **Éditeur** : pour chaque `secret.<H>` des sources `json` du manifest, le formulaire affiche un `SecureField` (label = « Secret : \<H\> »). La valeur saisie est stockée dans le **Keychain** via `KeychainStore`, clé = `"\(instanceId.uuidString).\(sourceKey).\(headerName)"`. Jamais écrite dans `paramValues`/`instances.json`.
- **Résolution au fetch** : `SecretResolver.resolvedConfig(for source, instanceId:)` retourne une copie de `source.config` où chaque `secret.<H>` est **remplacé** par `header.<H>` = valeur Keychain (si présente ; sinon l'en-tête est omis). Appelée **par `RenderPipeline`** avant `fetchAll` (le pipeline a l'`instanceId`), pour chaque source `json`. Le protocole `DataProvider` reste inchangé — `JSONDataProvider` applique les `header.<H>` comme d'habitude.
- **Preview** : l'éditeur utilise le même `SecretResolver` (avec les secrets de la copie de travail, y compris ceux tout juste saisis mais pas encore persistés — le model les tient en mémoire jusqu'au save) pour un aperçu authentifié fidèle.
- **Suppression** : `deleteInstance` (3a) doit aussi purger les secrets Keychain de l'instance → étendre `AppState.deleteInstance` pour appeler `SecretResolver.deleteAll(instanceId:)`.

`KeychainStore` : wrapper minimal `SecItem` (kSecClassGenericPassword, service = `fr.my-monkey.BetterWidgets`, account = la clé). Testable en injectant un backing en mémoire (protocole `SecretBackingStore`) pour ne pas taper le vrai Keychain en tests.

## 8. Gestion d'erreurs

- Params invalides tolérés (le template gère l'absence/le vide).
- Secret vide/absent → l'en-tête n'est pas envoyé ; l'API renverra probablement une erreur → la source devient un `failedKey` → `stale`, visible dans la preview et sur la carte.
- Fermer l'éditeur avec des modifs non sauvegardées → `confirmationDialog` (« Abandonner les modifications ? »).
- Enregistrer une instance dont le template a disparu (improbable) → no-op silencieux + log.

## 9. Sécurité

- Les secrets ne transitent que Keychain ↔ mémoire de l'éditeur ↔ en-tête HTTPS de requête ; jamais sur disque en clair, jamais dans `instances.json`, jamais dans un export `.bwidget` (3c en tiendra compte : l'export ne lit que `instances.json`).
- La WKWebView de preview garde le confinement de 3b/Plan 2 (`bwasset://` + `NavigationPolicy`, pas de `file://`).

## 10. Tests

- **Unit `AppState.updateInstance`** : remplace l'instance, persiste, reschedule ; no-op si id inconnu.
- **Unit `AppState.deleteInstance`** (étendu) : purge aussi les secrets de l'instance (via un `SecretResolver` à backing mémoire injecté).
- **Unit `SecretResolver`** : set/get/delete ; `resolvedConfig` mappe `secret.<H>`→`header.<H>` avec la valeur, omet si absente, laisse les `header.<H>` existants intacts, ne touche pas les sources non-`json`.
- **Unit `KeychainStore`** (backing mémoire) : round-trip set/get/delete.
- **Unit `WidgetEditorModel`** : copie de travail isolée (éditer puis annuler ne change pas l'instance) ; `previewContext()` produit le bon `RenderContext` (params fusionnés défauts⊕édités, taille/thème de preview) ; `save()` renvoie l'instance mise à jour.
- **Unit `RenderPipeline`** (étendu) : une source `json` avec `secret.<H>` voit l'en-tête résolu injecté dans la config passée au provider (via un `SecretResolver` mémoire pré-rempli) ; sans secret enregistré, l'en-tête est omis (pas de crash).
- **Vues** (`WidgetEditorView`/`ParamFormView`/`LivePreviewView`) : pas de test unitaire (SwiftUI) → build vert + vérif réelle (ouvrir l'éditeur, changer un param, voir la preview bouger, saisir un secret, enregistrer).

## 11. Risques & inconnues

| Risque | Mitigation |
|---|---|
| WKWebView vivante + ré-injection `BW.params` sans reload | Contrat : le template lit `window.BW.params` au chargement ; pour le live, dispatch un event `bwParamsChanged` + fallback reload complet si le template ne l'écoute pas. Spike au 1er jet. |
| Résolution des secrets côté pipeline sans changer le protocole provider | `SecretResolver.resolvedConfig` renvoie une config mutée ; `RenderPipeline` l'applique par source `json` — testé unitairement. |
| Keychain en tests (prompts/permissions) | `KeychainStore` derrière un protocole `SecretBackingStore` ; tests avec backing mémoire, jamais le vrai Keychain. |
| `.sheet` éditeur + `TimelineView` de rafraîchissement de la grille (3a) | L'éditeur est modal ; à la fermeture, la grille se rafraîchit (déjà périodique). Le save déclenche un refresh de l'instance. |
| ColorPicker ⇄ hex | Conversion `Color`↔`#rrggbb` aux frontières, testée dans le model. |

## 12. Hors périmètre (rappel)

Mode avancé code / CodeMirror (**3b-2**) ; import/export `.bwidget`, UI de consentement (**3c**) ; météo localisation courante (**3c**) ; création de nouveaux params ou édition du HTML (le formulaire n'édite que les params déclarés).
