# Better Widgets — Lot de templates maison (Plan 4a) — Design

**Goal** : livrer **8 templates bundlés soignés** qui affichent de la **vraie donnée** via les providers
existants, avec une direction artistique cohérente, pour que l'app soit démontrable et utile dès la
première ouverture. La **distribution** (DMG notarisé + cask) est un sous-projet séparé (Plan 4b),
bloqué sur des actions Apple de Maxim — hors périmètre de ce spec.

**Aucune dépendance Apple** : la météo passe par open-meteo (`json`), pas WeatherKit. Ce lot se
construit et se teste entièrement maintenant.

## Contexte & existant

- Providers en place : `json` (HTTPS + HTTP privé), `system`, `rss`, `calendar` (EventKit), `weather` (WeatherKit, **non provisionné → on ne s'en sert pas ici**).
- 4 templates démo déjà bundlés dans `BetterWidgets/Resources/templates/` : `hello-clock`, `feed-list`, `agenda`, `weather-now`. Ils sont minimalistes → **à remplacer/refondre** aux standards DA ci-dessous.
- Contrat template : dossier `manifest.json` + `index.html` lisant `window.BW = { params, data, size, theme, stale }`. Validé par `TemplateManifest.validated` (sizes non vide, `refresh ≥ 30`, clés params/sources uniques, types de source connus).
- Rendu : WKWebView confinée → PNG clair + sombre @2x. **Pas de CDN** : tout inline (CSS/JS/SVG).

## Direction artistique (partagée par tous les templates)

Reprise du système déjà éprouvé sur le widget dashboard et la galerie du README :

- **Palette Material-éditoriale**, claire + sombre via `@media (prefers-color-scheme)` **et** `:root[data-theme]` piloté par `window.BW.theme`. Tokens : `--bg/--surface/--surface-2/--border/--text/--text-2/--text-3/--accent (#1A73E8) /--green/--orange/--red/--purple`, variantes sombres définies.
- **Police système** uniquement (`-apple-system`, `"SF Pro Display"`).
- **Icônes = SVG Font Awesome solid inlinés**, `fill:currentColor`, dimensionnés en CSS.
- **Graphiques = SVG inline lissé** (spline Catmull-Rom → bézier, `vector-effect:non-scaling-stroke`), jamais de lib externe.
- **Remplit 100 %** de la surface, `overflow:hidden`, hiérarchie typo nette (≥ 3 tailles), tabular-nums pour les chiffres.
- **Robustesse** : chaque template gère source absente/`__denied`/`stale` avec un état de repli lisible, et adapte la densité à `size.family`.

Chaque `index.html` reste **autonome** (pas de fichier partagé), mais suit ce même starter (reset + tokens + helpers `smooth()/spark()/icons`). Le spec ne factorise pas en assets communs : la duplication d'un starter court est acceptable et garde chaque template importable/éditable seul.

## Les 8 templates

Pour chacun : `id`, tailles, `refresh` (s), paramètres, sources, forme de data attendue, ce qui s'affiche, états de repli.

### 1. `weather` — Météo
- Tailles `small`, `medium`, `large` · refresh **900**
- Params : `lat` (déf. `43.6047`), `lon` (déf. `3.8742`), `place` (déf. `Montpellier`)
- Source `json` : `https://api.open-meteo.com/v1/forecast?latitude={{lat}}&longitude={{lon}}&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min,weather_code&timezone=auto&forecast_days=5`
- Affiche : temp actuelle + icône WMO + lieu (small) ; + prévision 4-5 jours (medium/large). Mapping `weather_code`→icône/label FR (déjà défini).
- Repli : « Météo indisponible ».

### 2. `crypto` — Crypto
- Tailles `small`, `medium` · refresh **300**
- Params : `ids` (déf. `bitcoin,ethereum`), `vs` (déf. `usd`), `chart_id` (déf. `bitcoin` — la courbe est tracée pour cet id ; la substitution `{{…}}` étant littérale, on ne peut pas extraire le 1er élément de `ids`)
- Sources `json` :
  - prix : `https://api.coingecko.com/api/v3/simple/price?ids={{ids}}&vs_currencies={{vs}}&include_24hr_change=true`
  - courbe : `https://api.coingecko.com/api/v3/coins/{{chart_id}}/market_chart?vs_currency={{vs}}&days=1`
- Affiche : prix + variation 24 h (▲ vert / ▼ rouge via icônes caret) + sparkline lissée.
- Note : API gratuite sans clé, ~throttle → refresh 300 s OK. Repli : « Cours indisponible ».

### 3. `system` — Système Mac
- Tailles `small`, `medium` · refresh **60**
- Params : aucun
- Source `system` : `{ datetime, uptime, memTotal, memFree, diskFree, … }`
- Affiche : anneaux/jauges RAM & disque, uptime, heure. Aucune config, marche hors-ligne.
- Repli : n/a (provider local toujours dispo).

### 4. `news` — Actus (RSS)
- Tailles `medium`, `large` · refresh **1800**
- Params : `feed` (déf. `https://www.lemonde.fr/rss/une.xml`), `title` (déf. « Actus »)
- Source `rss` : `{ items: [{ title, link, date }] }`
- Affiche : 3-5 derniers titres + date relative. Repli : « Aucun article ».

### 5. `agenda` — Agenda
- Tailles `medium`, `large` · refresh **900**
- Params : `days` (déf. `7`)
- Source `calendar` (EventKit, **consentement requis**) : `{ events: [{ title, start, end, allDay, calendarColor }] }`
- Affiche : prochains événements groupés par jour, pastille couleur. Gère `__denied` → « Autorise l'agenda ». Repli : « Rien à venir ».

### 6. `status` — Monitoring de services
- Tailles `medium`, `large` · refresh **120**
- Params : `url` (endpoint JSON de statut de l'utilisateur), `title` (déf. « Services »)
- Source `json` (peut être **HTTP privé** : LAN/Tailscale) → forme attendue documentée : tableau `[{ name, up, ms? }]` **ou** objet `{ services: [...] }`. Le template normalise les deux.
- Affiche : liste services + pastille verte/rouge (+ latence si fournie) + % up. Cas d'usage : uptime-kuma/status.json perso.
- Repli : « Endpoint injoignable » (badge `stale`).

### 7. `home` — Domotique (Home Assistant)
- Tailles `medium`, `large` · refresh **120**
- Params : `base` (ex. `homeassistant.local:8123`, **HTTP privé**), `entities` (liste d'entity_ids séparés par `,`)
- Source `json` → `http://{{base}}/api/states` avec `secret.Authorization: Bearer …` (**token long-lived en Keychain**). Filtre côté template sur `entities`.
- Affiche : tuiles température/humidité/énergie + états on/off (lumières). Showcase **http privé + secret Keychain + self-hosted**.
- Repli : `__denied`/erreur → « Connecte ton Home Assistant ».

### 8. `github` — GitHub
- Tailles `small`, `medium` · refresh **1800**
- Params : `owner` (déf. `my-monkeys`), `repo` (déf. `better-widgets`)
- Source `json` : `https://api.github.com/repos/{{owner}}/{{repo}}` — `secret.Authorization: Bearer …` **optionnel** (public marche sans, 60 req/h ; avec token 5000/h).
- Affiche : ⭐ stars, forks, issues ouvertes, dernier push. Showcase **secret Keychain optionnel + API publique**.
- Repli : « Repo introuvable ».

## Récap sources / features couvertes

| Template | Provider | Config user | Feature vitrine |
|---|---|---|---|
| weather | json | non (défauts) | fetch https |
| crypto | json | non (défauts) | https + sparkline |
| system | system | non | provider système |
| news | rss | flux | provider rss |
| agenda | calendar | consentement | EventKit + permission |
| status | json | endpoint | **http privé** |
| home | json | base+entities+**secret** | **http privé + Keychain** |
| github | json | owner/repo (+secret opt.) | **Keychain optionnel** |

Ensemble : 4 des 5 providers sont démontrés en tant que tels (`json`, `system`, `rss`, `calendar`) ; le 5ᵉ (`weather`/WeatherKit) est volontairement remplacé par open-meteo via `json` (aucun provisioning Apple requis). S'ajoutent : http-privé, secrets Keychain (obligatoire `home`, optionnel `github`), et consentement (`agenda`).

## Fitness / Transport (hors périmètre)
Restent des **démos-vitrine du README** uniquement : pas de provider web simple (Apple Health = HealthKit non exposé au web ; transport = pas d'API générique). Documenté comme tel, pas re-livré en template.

## Tests
- **Validation manifest** : un test par nouveau template asserte `TemplateManifest.validated(from:)` OK (réutilise le pattern `ManifestTests`).
- **Rendu sans erreur** : un test qui, pour chaque template bundlé, injecte un `window.BW` mocké (data d'exemple par source) dans `RenderEngine` et vérifie qu'un PNG non vide est produit et qu'aucune erreur JS n'est levée (étend `RenderEngineTests`).
- **Bootstrap** : `installBundledTemplates` installe bien les 8 (assert la liste).
- **Fixtures** : un `window.BW` d'exemple par template (data réaliste) sert et aux tests et à l'aperçu.
- Pas de test réseau live (les fetchs réels ne sont pas testés en CI ; les providers ont déjà leurs tests unitaires mockés).

## Vérification visuelle
Avant de clore : rendre les 8 templates (clair + sombre, chaque taille) via le harnais navigateur (comme fait pour le dashboard/galerie), avec data d'exemple, et valider à l'œil. Puis vérif réelle d'au moins 1-2 templates dans l'app posée sur le bureau (action Maxim, comme d'habitude).

## Hors périmètre (→ Plan 4b distribution)
- Cert Developer ID, notarisation `notarytool`, staple, DMG, tap/cask Homebrew.
- Provisionnement WeatherKit (pas nécessaire ici).
- Un éventuel template `weather` sur le provider `weather` (WeatherKit) le jour où c'est provisionné.

## Non-goals
- Pas de nouveau provider de données (on se limite aux 5 existants).
- Pas de refonte de l'éditeur/de l'app — uniquement le contenu (templates) + tests associés.
- Pas de fitness/transport en templates réels.
