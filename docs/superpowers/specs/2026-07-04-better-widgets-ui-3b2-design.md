# Better Widgets — Design UI 3b-2 : Mode avancé code (CodeMirror embarqué)

**Date** : 2026-07-04
**Statut** : validé (brainstorming) — en attente de relecture du spec
**Projet** : `~/Documents/my-monkey/better-widgets/` — sous-plan 3b-2 de la phase UI
**Réfs** : spec produit `2026-07-03-better-widgets-design.md` (§7 sécurité, §8 mode avancé) ; spec 3b-1 `2026-07-04-better-widgets-ui-3b1-design.md` (preview live réutilisée)

## 1. Contexte & découpage

Plans 1, 2, 3a, 3b-1 faits & mergés : moteur, extension, providers, permissions, coquille d'app, éditeur de **params** + preview live + secrets Keychain. `TemplateStore` sait aujourd'hui **lire** (`list`/`manifest`/`html`/`templateDirectory`) et installer les templates bundlés (`installBundledTemplates`, sans écraser) — **pas écrire**.

3b-2 ajoute le **mode avancé code** (Plan 3 → 3b → 3b-2) : écrire ses propres templates de widget en HTML/CSS/JS libre + `manifest.json`, avec coloration syntaxique (**CodeMirror embarqué**, décision actée), preview live et validation. C'est le dernier morceau de la phase éditeur.

DA : **éditorial minimal** (`DesignTokens`) ; skill `minimalist-ui` pour les vues.

## 2. Périmètre 3b-2

**Dans 3b-2** : entrées « Nouveau template » + « Forker » depuis la Galerie ; écran éditeur de code (CodeMirror HTML + manifest, onglets) + preview live (réutilise `LivePreviewView`) ; validation du manifest à la sauvegarde ; écritures `TemplateStore` (create/fork/save/delete de templates **utilisateur**) ; distinction bundlé/utilisateur.

**Hors 3b-2** : import/export `.bwidget` + UI de consentement (3c) ; météo localisation courante (3c) ; distribution (4). On n'édite pas les params d'instance ici (c'est 3b-1) — 3b-2 édite le **template** (html + manifest), pas l'instance.

## 3. Modèle de template : bundlé vs utilisateur

- **Templates bundlés** (`hello-clock`, `feed-list`, `agenda`, `weather-now`) : livrés dans l'app, installés dans Application Support par `installBundledTemplates`. **Non éditables en place et non supprimables** — les éditer divergerait silencieusement de la version livrée et un ré-install ne les restaure pas (l'install skip si le dossier existe). Pour les modifier, on **forke**.
- **Templates utilisateur** : créés par « Nouveau » (scaffold vierge) ou « Forker » (copie d'un template existant sous un nouvel id). Éditables et supprimables librement.
- **Distinction** : un fichier marqueur `.user` (vide) dans le dossier du template utilisateur. `TemplateStore.isUserTemplate(id:)` = présence du marqueur. (Alternative rejetée : un champ dans le manifest — polluerait le format partageable ; le marqueur hors-manifest est plus propre.)
- **Id utilisateur** : slug dérivé du nom + suffixe unique si collision (ex. `mon-widget`, `mon-widget-2`). Le fork d'un template `X` donne un id `X-copie` (puis `-2`, … si pris).

## 4. Architecture

```
GalleryView (3a) — MODIF
├── bouton « Nouveau template » → crée un template utilisateur scaffold → ouvre l'éditeur
└── par carte de template : action « Forker » → copie → ouvre l'éditeur ; « Supprimer » (utilisateur only)
        └── .sheet → TemplateCodeEditorView(templateId)   [NOUVEAU]
            ├── CodeEditorView   (gauche) — CodeMirror en WKWebView, onglets html/manifest
            └── LivePreviewView  (droite) — RÉUTILISÉ de 3b-1
```

### Composants (frontières)

| Unité | Rôle | API |
|---|---|---|
| `TemplateStore` (étendu) | Écritures templates utilisateur | `createUserTemplate(name:) -> String` (id), `forkTemplate(from:) -> String`, `saveTemplate(id:html:manifestJSON:) throws`, `deleteUserTemplate(id:)`, `isUserTemplate(id:) -> Bool` |
| `CodeEditorBridge` | Pont Swift↔JS CodeMirror (get/set texte, langage) | `NSViewRepresentable` + coordinator `WKScriptMessageHandler` ; `@Binding text`, `language: .html/.json` |
| `CodeEditorView` | Onglets html/manifest au-dessus du `CodeEditorBridge` | consomme un `TemplateEditorModel` |
| `TemplateCodeEditorView` | Écran 2 volets (code / preview) + Enregistrer/Annuler + erreurs de validation | consomme `AppState` + `TemplateEditorModel` |
| `TemplateEditorModel` | Copie de travail (html + manifestJSON + onglet), validation, produit le `RenderContext` de preview | `@Published htmlText/manifestText/tab` ; `func validate() -> Result<TemplateManifest, ManifestError>` ; `func save() throws` ; `func previewContext(data:stale:) -> RenderContext` |
| CodeMirror assets | JS/CSS bundlés dans l'app | `Resources/codemirror/` servis à la WKWebView |

## 5. Éditeur de code (CodeMirror)

- **CodeMirror bundlé** dans l'app (`Resources/codemirror/` : le JS/CSS de CodeMirror, une version figée, aucun CDN). Chargé dans une WKWebView via une page HTML locale + le même type de scheme handler confiné que le rendu (ou un handler dédié `bweditor://`).
- **Pont** : au chargement, Swift injecte le texte initial + le langage (`html`/`json`) ; à chaque édition, CodeMirror poste le texte via `window.webkit.messageHandlers.bwEditor.postMessage(...)` → le coordinator met à jour le `@Binding`. Changement d'onglet = swap du contenu + du mode de coloration.
- **Coloration** : HTML pour `index.html`, JSON pour `manifest.json`, numéros de ligne. Pas d'autocomplétion/linting avancé en v1 (YAGNI) — coloration + numéros de ligne suffisent.

## 6. Preview live

Réutilise `LivePreviewView` (3b-1) tel quel : WKWebView vivante confinée (`bwasset://` + `NavigationPolicy`), `window.BW` injecté. Le contexte de preview vient du `TemplateEditorModel` : params = les **défauts** du manifest en cours d'édition (pas d'instance ici — on édite un template, pas une instance) ; données = fetch une fois via `DataProviderRegistry` sur les sources du manifest édité (permissions/secrets non applicables : un template en édition n'a pas d'instance ni de grants → sources consent-required affichées `__denied`, sources `json`/`system`/`rss` fetchées normalement). Sur édition du HTML ou du manifest (debounce), la preview recharge avec le nouveau contenu. Le manifest doit être **parsable** pour piloter la preview ; s'il est invalide, la preview garde le dernier état valide + un bandeau « manifest invalide ».

## 7. Validation & sauvegarde

- **Enregistrer** : on parse `manifestText` via `TemplateManifest.validated(from:)`. Invalide → **refus**, message précis (l'erreur `ManifestError` traduite), rien n'est écrit. Valide → `TemplateStore.saveTemplate(id:html:manifestJSON:)` écrit `index.html` + `manifest.json`. Le HTML n'est pas validé (libre).
- L'id du template ne change pas à la sauvegarde (fixé à la création/fork).
- Un template utilisateur peut être ré-ouvert et ré-édité (édition en place, puisqu'il est utilisateur).
- Supprimer un template utilisateur : `confirmationDialog` ; **avertir** si des instances l'utilisent (elles deviendraient orphelines → rendu placeholder). v1 : on autorise la suppression et les instances orphelines affichent le placeholder « configure-moi » (déjà géré par l'extension). (Nettoyage des instances orphelines = hors périmètre.)

## 8. Écritures `TemplateStore`

- `createUserTemplate(name:) -> String` : génère un id-slug unique, crée le dossier + un `index.html` scaffold minimal (fond + « Hello ») + un `manifest.json` par défaut (`sizes: ["small"]`, `refresh: 900`, `params: []`, `sources: []`) valide + le marqueur `.user`. Renvoie l'id.
- `forkTemplate(from:) -> String` : copie `index.html` + `manifest.json` du template source vers un nouvel id `<source>-copie` (unique), réécrit l'`id` du manifest copié, ajoute le marqueur `.user`. Renvoie l'id.
- `saveTemplate(id:html:manifestJSON:) throws` : valide le manifest (`TemplateManifest.validated`), écrit les deux fichiers atomiquement ; throw `ManifestError` si invalide (rien écrit).
- `deleteUserTemplate(id:)` : supprime le dossier si `isUserTemplate(id:)`, sinon no-op (les bundlés ne se suppriment pas).
- `isUserTemplate(id:) -> Bool` : présence du marqueur `.user`.

## 9. Sécurité

Le HTML utilisateur est rendu dans la même WebView confinée que tout template (preview 3b-1 + rendu Plan 1/2 : `bwasset://`, `file://` bloqué, symlink-safe). Un template utilisateur n'a aucun privilège supplémentaire. Les secrets restent une notion d'**instance** (3b-1) ; l'éditeur de template ne manipule pas de secrets. **Important** : l'export `.bwidget` (3c) devra exclure/soigner tout ce qui est sensible — mais un template ne contient pas de secret par construction (les secrets sont sur l'instance, Keychain).

## 10. Gestion d'erreurs

- Manifest invalide au save → refus + message (mapper `ManifestError` en texte FR : « refresh trop court », « type de source inconnu : X », « clé de param dupliquée », etc.).
- Manifest invalide pendant l'édition → preview gèle sur le dernier état valide + bandeau.
- CodeMirror qui ne charge pas (bundle manquant/corrompu) → l'éditeur affiche une erreur ; **fallback** possible vers un `TextEditor` natif monospace (décision au spike de CodeMirror ; le fallback n'est pas construit d'emblée, mais le pont est isolé pour le permettre).
- Slug/id : collision gérée par suffixe numérique.

## 11. Tests

- **Unit `TemplateStore`** (écritures) : `createUserTemplate` (dossier + scaffold valide + marqueur), `forkTemplate` (copie + nouvel id dans le manifest + marqueur), `saveTemplate` (écrit si valide, throw + rien écrit si manifest invalide), `deleteUserTemplate` (supprime utilisateur, no-op sur bundlé), `isUserTemplate`, unicité des id (collision → suffixe).
- **Unit `TemplateEditorModel`** : `validate()` (OK/erreur mappée), `previewContext()` (params = défauts du manifest édité, taille/thème), `save()` délègue à `TemplateStore` et propage l'erreur.
- **Spike CodeMirror** (première tâche) : preuve que CodeMirror bundlé charge dans la WKWebView, que le texte édité remonte à Swift et qu'on peut le ré-injecter — critère d'acceptation vérifié en réel (l'éditeur est une WebView, pas de test unitaire pur).
- **Vues** (`CodeEditorView`/`TemplateCodeEditorView`) : build + vérif réelle (Nouveau → éditer HTML → preview bouge → manifest invalide → refus au save → corriger → save → le template apparaît dans la Galerie et est instanciable).

## 12. Risques & inconnues

| Risque | Mitigation |
|---|---|
| **CodeMirror embarqué + pont Swift↔JS** (risque n°1) | Spike en 1re tâche ; pont isolé dans `CodeEditorBridge` ; fallback `TextEditor` natif possible si insoluble |
| Preview d'un template sans instance (pas de grants/secrets) | Params = défauts du manifest ; sources consent-required → `__denied` ; json/system/rss fetchées ; documenté |
| Manifest invalide pendant l'édition (pilote la preview) | Parse tolérant pour la preview (garde le dernier valide + bandeau) ; validation stricte seulement au save |
| Id/slug collisions | Suffixe numérique unique, testé |
| Instances orphelines après suppression d'un template | v1 : placeholder de l'extension (déjà là) + avertissement à la suppression ; nettoyage hors périmètre |
| Poids du bundle (assets CodeMirror) | Version figée minimale de CodeMirror, pas de CDN, bundlée comme les templates |

## 13. Hors périmètre (rappel)

Import/export `.bwidget`, UI de consentement, météo localisation courante (**3c**) ; distribution DMG/cask (**4**) ; autocomplétion/linting avancé dans l'éditeur ; nettoyage automatique des instances orphelines.
