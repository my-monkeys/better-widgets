---
name: create-better-widget
description: Génère un widget Better Widgets (template HTML → widget macOS natif) à partir d'une description en langage naturel. Sortie = manifest.json + index.html prêts à importer.
---

# Créer un widget Better Widgets avec une IA

Ce fichier est un **skill portable** : colle-le dans Claude, Gemini, Codex, ChatGPT — ou dépose-le
dans `.claude/skills/create-better-widget/SKILL.md` — puis demande *« crée-moi un widget qui affiche X »*.
L'assistant produit un **template Better Widgets** que tu importes dans l'app.

## Ce que tu (l'IA) dois produire

Un template = **deux fichiers** :

- **`manifest.json`** — déclare l'identité, les tailles, la fréquence, les paramètres et les sources de données.
- **`index.html`** — un document HTML autonome qui lit `window.BW` et dessine l'écran.

À la fin, propose aussi de **l'empaqueter en `.bwidget`** (voir plus bas) pour l'import en un fichier.

## `manifest.json`

```json
{
  "id": "mon-widget",
  "name": "Mon widget",
  "version": "1.0.0",
  "sizes": ["small", "medium", "large"],
  "refresh": 60,
  "params": [
    { "key": "ville", "type": "string", "label": "Ville", "default": "Montpellier" }
  ],
  "sources": [
    { "key": "wx", "type": "json",
      "config": { "url": "https://api.open-meteo.com/v1/forecast?latitude=43.6&longitude=3.9&current=temperature_2m" } }
  ]
}
```

| Champ      | Règle |
|------------|-------|
| `id`       | identifiant unique en kebab-case |
| `sizes`    | ≥ 1 valeur parmi `small` / `medium` / `large` |
| `refresh`  | intervalle de rafraîchissement en secondes, **minimum 30** |
| `params`   | paramètres réglables par l'utilisateur. `type` ∈ `string` / `number` / `color` / `url`. `default` optionnel |
| `sources`  | données à récupérer avant le rendu. `type` ∈ `json` / `system` / `rss` / `calendar` / `weather`. Chaque `key` devient `window.BW.data.<key>` |

**Substitution** : dans une URL ou une config de source, `{{ville}}` est remplacé par la valeur du paramètre.

**Secrets d'API** (source `json`) : mets une clé `"secret.Authorization": "Bearer …"` dans `config` — l'utilisateur
saisit la valeur, elle est stockée dans le **Keychain** et injectée en en-tête `Authorization` au fetch.
Un en-tête non secret se déclare `"header.X-Api-Key": "…"`. **Ne mets jamais de secret en clair dans le manifest.**

### Les types de sources

| `type`     | Fournit dans `window.BW.data.<key>` |
|------------|--------------------------------------|
| `json`     | le JSON parsé d'un `GET`. HTTPS partout ; HTTP accepté uniquement vers réseau privé/local (LAN, Tailscale, `localhost`, `.local`) |
| `system`   | `{ datetime, uptime, memTotal, memFree, diskFree, … }` (infos machine) |
| `rss`      | `{ items: [{ title, link, date }] }` |
| `calendar` | `{ events: [{ title, start, end, … }] }` (consentement requis) |
| `weather`  | `{ temperature, condition, … }` par ville ou position (consentement requis) |

## `index.html` — le contrat `window.BW`

Avant le rendu, l'app injecte `window.BW` :

```js
window.BW = {
  params: { ville: "Montpellier" },   // valeurs des paramètres
  data:   { wx: { current: { temperature_2m: 24 } } },  // un objet par source (clé = source.key)
  size:   { w: 170, h: 170, family: "small" },  // dimensions en points + famille
  theme:  "light",                    // "light" | "dark" (le moteur rend les deux)
  stale:  false                       // true si la dernière récupération a échoué
}
```

Exemple minimal complet :

```html
<!doctype html><meta charset="utf-8">
<style>
  html,body{margin:0;width:100%;height:100%;overflow:hidden;
    font-family:-apple-system,"SF Pro Display",sans-serif;background:#fff;color:#111}
  @media (prefers-color-scheme:dark){body{background:#111;color:#fff}}
  .wrap{width:100%;height:100%;display:grid;place-items:center}
  .t{font-size:46px;font-weight:700;letter-spacing:-.02em}
</style>
<div class="wrap" id="root"></div>
<script>
  const { data, params } = window.BW;
  const wx = data.wx || {};
  const root = document.getElementById("root");
  if (wx.current === undefined) {
    root.innerHTML = '<div style="opacity:.5;font-size:13px">Météo indisponible</div>';
  } else {
    root.innerHTML =
      '<div style="text-align:center">' +
      '<div class="t">' + Math.round(wx.current.temperature_2m) + '°</div>' +
      '<div style="opacity:.6;font-size:13px">' + params.ville + '</div></div>';
  }
</script>
```

## Règles impératives (sandbox de rendu)

Le template est rendu dans une **WKWebView confinée** puis capturé en PNG. Donc :

1. **Tout est inline dans `index.html`** : CSS, JS, icônes, polices. **Aucun CDN, aucun `<script src>` externe,
   aucune police web, aucune image distante.** Le seul accès réseau autorisé est le fetch des `sources` déclarées.
2. **Polices système uniquement** : `-apple-system`, `"SF Pro Display"`, `system-ui`.
3. **Icônes = SVG inline** (les tracés Font Awesome / Lucide collés en `<svg>` marchent très bien ; utilise `fill:currentColor`).
4. **Graphiques = SVG inline** que tu calcules toi-même depuis les données (pas de Chart.js). Pour des courbes
   jolies, lisse-les (spline Catmull-Rom → bézier) plutôt que des segments droits.
5. **Remplis 100 % de la surface**, `overflow:hidden`, jamais de scroll.
6. **Adapte-toi à la taille** : lis `window.BW.size.family` et change la densité (moins d'infos en `small`).
7. **Gère les deux thèmes** : `@media (prefers-color-scheme:dark)` (le moteur bascule l'apparence de la WebView),
   idéalement double par un sélecteur `:root[data-theme="dark"]` piloté depuis `window.BW.theme`.
8. **Sois robuste** : une source peut être absente (`undefined`) si le fetch a échoué ; affiche un état de repli.
   `window.BW.stale === true` signale un rendu avec des données périmées.

### Tailles de référence (points, rendu @2x)

| famille  | largeur × hauteur |
|----------|-------------------|
| `small`  | 170 × 170 |
| `medium` | 364 × 170 |
| `large`  | 364 × 382 |

## Empaqueter en `.bwidget` (optionnel)

Un `.bwidget` est un **conteneur JSON** que l'app importe en un fichier. Format :

```json
{
  "format": "bwidget/1",
  "entries": [
    { "path": "manifest.json", "data": "<contenu base64 du manifest.json>" },
    { "path": "index.html",    "data": "<contenu base64 de l'index.html>" }
  ]
}
```

Encode chaque fichier en base64 standard. (Assets optionnels : `assets/<nom>` — chemins relatifs uniquement,
pas de `..` ni de chemin absolu.)

## Processus recommandé

1. Comprends ce que l'utilisateur veut afficher et d'où viennent les données (API JSON ? système ? RSS ?).
2. Écris le `manifest.json` (tailles utiles, `refresh` réaliste, paramètres, sources).
3. Écris l'`index.html` autonome qui lit `window.BW` et rend proprement en clair **et** en sombre, pour chaque
   taille déclarée, avec un état de repli si les données manquent.
4. Propose le `.bwidget` empaqueté prêt à importer.

Objectif : un widget **lisible d'un coup d'œil**, sobre, avec une hiérarchie typographique nette — pas un tableau
de bord surchargé. Un widget montre **une** chose bien.
