# Better Widgets — Home Templates (Plan 4a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship 8 polished bundled templates (`weather`, `crypto`, `system`, `news`, `agenda`, `status`, `home`, `github`) that display real data through the existing providers, with a shared design language, and retire the 4 minimal demo templates.

**Architecture:** Each template is a self-contained directory `BetterWidgets/Resources/templates/<id>/` (`manifest.json` + `index.html`) auto-bundled via the existing `project.yml` folder glob and installed on first launch by `TemplateStore.installBundledTemplates`. `index.html` reads `window.BW = { params, data, size, theme, stale }` and renders **synchronously** from `data` (the RenderPipeline fetches the declared sources and injects them). All templates share one DA starter (tokens + helpers) established in Task 1; charts and icons are inline SVG (no CDN). Two test families back every template: manifest validation and a headless render smoke test.

**Tech Stack:** Swift 5.9 / XcodeGen / WidgetKit / WKWebView render engine; template content is HTML/CSS/vanilla-JS with inline SVG (Font Awesome solid paths, Catmull-Rom smoothed sparklines).

## Global Constraints

- **Template contract**: dir with `manifest.json` (validated by `TemplateManifest.validated`: `sizes` non-empty, `refresh >= 30`, unique param/source keys, source `type` ∈ `json`/`system`/`rss`/`calendar`/`weather`) + `index.html` reading `window.BW = { params, data, size, theme, stale }`.
- **Sizes → PNG**: `small` 170×170pt (340×340px @2x), `medium` 364×170pt (728×340px), `large` 364×382pt (728×764px).
- **Sandbox**: no external CDN/scripts/fonts/images. Everything inline. System fonts only (`-apple-system`, `"SF Pro Display"`). Icons + charts = inline SVG. `overflow:hidden`, fills 100%.
- **Themes**: render both; support via `@media (prefers-color-scheme:dark)` **and** `:root[data-theme]` set from `window.BW.theme`.
- **Robustness**: each template handles a missing source (`data.<key>` undefined), the `{"__denied": true}` marker (consent sources), and `window.BW.stale === true`, with a legible fallback.
- **Synchronous render**: templates render from `window.BW.data` in the inline script with no async work, so `didFinish` triggers the snapshot (no `window.BW.ready()` needed). Templates must NOT fetch — the pipeline fetches declared sources.
- **DA**: Material-editorial palette, tabular-nums for figures, ≥3 type sizes, smoothed SVG charts. Reuse the exact helper functions and Font Awesome ICON SVG strings already present in the repo at `dogfood/gallery.html` and `dogfood/dashboard/index.html` (both readable in the working tree) — do not reinvent them.
- **No AI attribution** in commits; author is the repo's local git identity.
- Reference design decisions and per-template data shapes: `docs/superpowers/specs/2026-07-05-better-widgets-home-templates-design.md`.

**Template-HTML convention for this plan:** the DA starter (Task 1) and the `weather` template (Task 1) are given as complete code and are the structural reference. For Tasks 2–8, the `manifest.json`, the `window.BW.data` fixture, the per-size display spec, and the tests are given in full; the `index.html` is built by the implementer from the Task-1 starter + the `weather` reference + the display spec (this is deliberate — the HTML is guided creative work, the contracts/tests are exact). Every `index.html` MUST begin from the Task-1 starter verbatim.

---

### Task 1: DA starter + `weather` template + shared render-test harness

**Files:**
- Create: `BetterWidgets/Resources/templates/weather/manifest.json`
- Create: `BetterWidgets/Resources/templates/weather/index.html`
- Create: `Tests/BundledTemplateTests.swift`

**Interfaces:**
- Produces (used by every later task):
  - The **DA starter** (the `<style>` reset+tokens and the `<script>` helper block in `weather/index.html`) — later templates copy it verbatim as their base.
  - `enum BundledTemplates { static let ids: [String]; static var dir: URL; static func manifest(_:) throws -> TemplateManifest; static func html(_:) throws -> String; static func defaultParams(_:) -> [String:String] }`
  - `@MainActor func assertRenders(_ id: String, data: [String: Any]) async throws` — renders the template for every declared size × light/dark, asserting exact PNG dimensions.

- [ ] **Step 1: Write `weather/manifest.json`**

```json
{
  "id": "weather",
  "name": "Météo",
  "version": "1.0.0",
  "sizes": ["small", "medium", "large"],
  "refresh": 900,
  "params": [
    { "key": "lat", "type": "string", "label": "Latitude", "default": "43.6047" },
    { "key": "lon", "type": "string", "label": "Longitude", "default": "3.8742" },
    { "key": "place", "type": "string", "label": "Lieu", "default": "Montpellier" }
  ],
  "sources": [
    { "key": "wx", "type": "json",
      "config": { "url": "https://api.open-meteo.com/v1/forecast?latitude={{lat}}&longitude={{lon}}&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min,weather_code&timezone=auto&forecast_days=5" } }
  ]
}
```

- [ ] **Step 2: Write `weather/index.html`** — the reference template. It MUST contain, in order: (a) the DA **starter `<style>`** = reset (`*{margin:0;box-sizing:border-box}`, `html,body{width:100%;height:100%;overflow:hidden;font-family:-apple-system,"SF Pro Display",sans-serif}`) + the light/dark `:root` token vars (`--bg/--surface/--surface-2/--border/--text/--text-2/--text-3/--accent/--green/--orange/--red/--purple/--track`) with the `@media (prefers-color-scheme:dark)` and `:root[data-theme="dark"]`/`[data-theme="light"]` overrides — copy these token blocks verbatim from `dogfood/dashboard/index.html`; (b) the DA **starter `<script>` helpers** = `esc`, `pad2`, tabular-num formatting, the `ICON` map (copy the needed Font Awesome SVG strings from `dogfood/dashboard/index.html` / `dogfood/gallery.html`), `wxIcon(code)` + `wxColor(code)` (copy from `dogfood/dashboard/index.html`), and `pointsOf/smooth/spark` (copy from `dogfood/gallery.html`); (c) a `render(bw)` that reads `bw.size.family`/`bw.theme`, sets `document.documentElement.dataset.theme`, and paints. Display:
  - **small**: `place`, big current temp (`data.wx.current.temperature_2m` rounded) + `wxIcon(weather_code)`, WMO label.
  - **medium/large**: the above + a 4-day forecast row from `data.wx.daily` (`time`, `temperature_2m_max`, `weather_code`) with per-day icon + high/low.
  - Fallback when `data.wx` or `data.wx.current` is undefined: centered muted “Météo indisponible”. Add the `stale` dot marker (fixed top-right) when `bw.stale`.
  End with `if (window.BW) render(window.BW);`.

- [ ] **Step 3: Write the harness `Tests/BundledTemplateTests.swift`**

```swift
import XCTest
// Core sources are compiled directly into the test target (no module import).

enum BundledTemplates {
    static let ids = ["weather", "crypto", "system", "news", "agenda", "status", "home", "github"]

    /// Source-tree templates dir, resolved from this file's path so tests read the real
    /// bundled templates without adding them to the test bundle's resources.
    static var dir: URL {
        URL(fileURLWithPath: #filePath)          // …/Tests/BundledTemplateTests.swift
            .deletingLastPathComponent()          // …/Tests
            .deletingLastPathComponent()          // repo root
            .appendingPathComponent("BetterWidgets/Resources/templates")
    }
    static func manifest(_ id: String) throws -> TemplateManifest {
        try TemplateManifest.validated(from: Data(contentsOf: dir.appendingPathComponent("\(id)/manifest.json")))
    }
    static func html(_ id: String) throws -> String {
        try String(contentsOf: dir.appendingPathComponent("\(id)/index.html"), encoding: .utf8)
    }
    static func defaultParams(_ m: TemplateManifest) -> [String: String] {
        var p: [String: String] = [:]
        for spec in m.params { if let d = spec.default { p[spec.key] = d } }
        return p
    }
}

final class BundledTemplateTests: XCTestCase {

    /// Renders `id` for every declared size × light/dark, asserting exact @2x dimensions.
    @MainActor
    func assertRenders(_ id: String, data: [String: Any]) async throws {
        let manifest = try BundledTemplates.manifest(id)
        let html = try BundledTemplates.html(id)
        let dir = BundledTemplates.dir.appendingPathComponent(id)
        let params = BundledTemplates.defaultParams(manifest)
        for size in manifest.sizes {
            for theme in [Theme.light, .dark] {
                let ctx = RenderContext(params: params, data: data, size: size, theme: theme, stale: false)
                let png = try await RenderEngine().render(html: html, baseURL: dir, context: ctx)
                let rep = try XCTUnwrap(NSBitmapImageRep(data: png), "\(id) \(size) \(theme) produced no PNG")
                XCTAssertEqual(rep.pixelsWide, Int(size.pointSize.width * 2), "\(id) \(size) width")
                XCTAssertEqual(rep.pixelsHigh, Int(size.pointSize.height * 2), "\(id) \(size) height")
            }
        }
    }

    func testWeatherManifestValid() throws {
        let m = try BundledTemplates.manifest("weather")
        XCTAssertEqual(m.id, "weather")
        XCTAssertEqual(m.sources.first?.type, "json")
    }

    @MainActor
    func testWeatherRenders() async throws {
        let data: [String: Any] = ["wx": [
            "current": ["temperature_2m": 21.4, "weather_code": 1],
            "daily": [
                "time": ["2026-07-05", "2026-07-06", "2026-07-07", "2026-07-08", "2026-07-09"],
                "temperature_2m_max": [27.0, 29.0, 25.0, 22.0, 24.0],
                "temperature_2m_min": [15.0, 16.0, 14.0, 13.0, 14.0],
                "weather_code": [0, 1, 2, 61, 3]
            ]
        ]]
        try await assertRenders("weather", data: data)
    }
}
```

- [ ] **Step 4: Generate + run the tests**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS,arch=arm64' -only-testing:BetterWidgetsTests/BundledTemplateTests`
Expected: `TEST SUCCEEDED`, `testWeatherManifestValid` + `testWeatherRenders` pass (weather renders at 340×340, 728×340, 728×764 in both themes).

- [ ] **Step 5: Visual check (browser)** — render `weather` at each size × theme with the fixture data via the same iframe/`srcdoc` harness used in `dogfood/gallery.html` (or a headless Chrome screenshot), and eyeball legibility. Fix any layout overflow.

- [ ] **Step 6: Commit**

```bash
git add BetterWidgets/Resources/templates/weather Tests/BundledTemplateTests.swift
git commit -m "feat(templates): weather (open-meteo) + shared render-test harness"
```

---

### Task 2: `crypto` template

**Files:**
- Create: `BetterWidgets/Resources/templates/crypto/{manifest.json,index.html}`
- Modify: `Tests/BundledTemplateTests.swift` (add `testCryptoManifestValid`, `testCryptoRenders`)

**Interfaces:** Consumes the Task-1 starter + `assertRenders`. Produces nothing new.

- [ ] **Step 1: `crypto/manifest.json`**

```json
{
  "id": "crypto", "name": "Crypto", "version": "1.0.0",
  "sizes": ["small", "medium"], "refresh": 300,
  "params": [
    { "key": "ids", "type": "string", "label": "Cryptos (ids CoinGecko)", "default": "bitcoin,ethereum" },
    { "key": "vs", "type": "string", "label": "Devise", "default": "usd" },
    { "key": "chart_id", "type": "string", "label": "Courbe (id)", "default": "bitcoin" }
  ],
  "sources": [
    { "key": "price", "type": "json",
      "config": { "url": "https://api.coingecko.com/api/v3/simple/price?ids={{ids}}&vs_currencies={{vs}}&include_24hr_change=true" } },
    { "key": "chart", "type": "json",
      "config": { "url": "https://api.coingecko.com/api/v3/coins/{{chart_id}}/market_chart?vs_currency={{vs}}&days=1" } }
  ]
}
```

- [ ] **Step 2: `crypto/index.html`** — from the starter. Display (reuse the crypto tile design in `dogfood/gallery.html`): per coin in `data.price` (`{ "bitcoin": {"usd":67432,"usd_24h_change":2.4}, … }`), show ticker + price (tabular) + 24h change with caret-up(green)/caret-down(red) ICON. Sparkline from `data.chart.prices` (array of `[ts, price]`) via `spark(prices, 'var(--orange)')` for the `chart_id` coin. **small** = the `chart_id` coin only (price + change + sparkline). **medium** = up to 2 coins side by side, sparkline under the `chart_id` one. Fallback when `data.price` undefined: “Cours indisponible”.

- [ ] **Step 3: Add tests** to `BundledTemplateTests.swift`:

```swift
func testCryptoManifestValid() throws {
    let m = try BundledTemplates.manifest("crypto")
    XCTAssertEqual(m.sources.count, 2)
    XCTAssertEqual(Set(m.sources.map { $0.key }), ["price", "chart"])
}

@MainActor
func testCryptoRenders() async throws {
    let prices: [Double] = (0..<48).map { 66000 + Double($0) * 40 }
    let data: [String: Any] = [
        "price": ["bitcoin": ["usd": 67432, "usd_24h_change": 2.4],
                  "ethereum": ["usd": 3518, "usd_24h_change": -1.1]],
        "chart": ["prices": prices.map { [1_700_000_000_000.0, $0] }]
    ]
    try await assertRenders("crypto", data: data)
}
```

- [ ] **Step 4: Run** `-only-testing:BetterWidgetsTests/BundledTemplateTests` → PASS. **Step 5: Visual check** (both sizes × themes). **Step 6: Commit** `feat(templates): crypto (CoinGecko)`.

---

### Task 3: `system` template

**Files:** Create `templates/system/{manifest.json,index.html}`; modify `BundledTemplateTests.swift`.

- [ ] **Step 1: `system/manifest.json`**

```json
{
  "id": "system", "name": "Système", "version": "1.0.0",
  "sizes": ["small", "medium"], "refresh": 60,
  "params": [],
  "sources": [ { "key": "sys", "type": "system" } ]
}
```

- [ ] **Step 2: `system/index.html`** — from the starter. `data.sys` = `{ datetime, uptime, memTotal, memFree, diskFree, … }` (see `SystemDataProvider`; confirm exact keys by reading `BetterWidgets/Core/Data/SystemDataProvider.swift`). Display: RAM used ring (`(memTotal-memFree)/memTotal`) + disk free, uptime (format seconds → `Nj Nh` / `Nh Nm`), current time. Reuse the `ring(pct,color,r)` helper from `dogfood/gallery.html`. **small** = one ring (RAM) + uptime. **medium** = RAM + disk rings side by side + uptime + clock. No fallback needed (local provider always present), but guard `data.sys` undefined defensively.

- [ ] **Step 3: Add tests**

```swift
func testSystemManifestValid() throws {
    let m = try BundledTemplates.manifest("system")
    XCTAssertEqual(m.sources.first?.type, "system")
    XCTAssertTrue(m.params.isEmpty)
}

@MainActor
func testSystemRenders() async throws {
    let data: [String: Any] = ["sys": [
        "datetime": "2026-07-05T14:30:00", "uptime": 275400.0,
        "memTotal": 17_179_869_184.0, "memFree": 5_368_709_120.0, "diskFree": 210_000_000_000.0
    ]]
    try await assertRenders("system", data: data)
}
```

- [ ] **Step 4: Run → PASS. Step 5: Visual check. Step 6: Commit** `feat(templates): system (Mac stats)`.

---

### Task 4: `news` template

**Files:** Create `templates/news/{manifest.json,index.html}`; modify `BundledTemplateTests.swift`.

- [ ] **Step 1: `news/manifest.json`**

```json
{
  "id": "news", "name": "Actus", "version": "1.0.0",
  "sizes": ["medium", "large"], "refresh": 1800,
  "params": [
    { "key": "feed", "type": "url", "label": "Flux RSS", "default": "https://www.lemonde.fr/rss/une.xml" },
    { "key": "title", "type": "string", "label": "Titre", "default": "Actus" }
  ],
  "sources": [ { "key": "rss", "type": "rss", "config": { "url": "{{feed}}" } } ]
}
```

- [ ] **Step 2: `news/index.html`** — from the starter. `data.rss` = `{ items: [{ title, link, date }] }` (confirm shape by reading `BetterWidgets/Core/Data/RSSDataProvider.swift`). Header = `params.title`. List 3 (medium) / 5 (large) latest items: title (2-line clamp) + relative date. Fallback when `data.rss.items` empty/undefined: “Aucun article”.

- [ ] **Step 3: Add tests**

```swift
func testNewsManifestValid() throws {
    let m = try BundledTemplates.manifest("news")
    XCTAssertEqual(m.sources.first?.type, "rss")
    XCTAssertEqual(m.sizes, [.medium, .large])
}

@MainActor
func testNewsRenders() async throws {
    let data: [String: Any] = ["rss": ["items": [
        ["title": "Un titre d'actualité assez long pour tester le clamp", "link": "https://x", "date": "2026-07-05T09:00:00Z"],
        ["title": "Deuxième article", "link": "https://y", "date": "2026-07-05T08:00:00Z"],
        ["title": "Troisième", "link": "https://z", "date": "2026-07-04T20:00:00Z"]
    ]]]
    try await assertRenders("news", data: data)
}
```

- [ ] **Step 4: Run → PASS. Step 5: Visual check. Step 6: Commit** `feat(templates): news (RSS)`.

---

### Task 5: `agenda` template (rewrite in place)

**Files:** Overwrite `templates/agenda/{manifest.json,index.html}` (the id `agenda` already exists as a demo — replace its contents); modify `BundledTemplateTests.swift`.

- [ ] **Step 1: `agenda/manifest.json`**

```json
{
  "id": "agenda", "name": "Agenda", "version": "1.0.0",
  "sizes": ["medium", "large"], "refresh": 900,
  "params": [ { "key": "days", "type": "number", "label": "Jours", "default": "7" } ],
  "sources": [ { "key": "cal", "type": "calendar", "config": { "days": "{{days}}" } } ]
}
```

- [ ] **Step 2: `agenda/index.html`** — from the starter. `data.cal` = `{ events: [{ title, start, end, allDay, calendarColor }] }` (confirm by reading `BetterWidgets/Core/Data/CalendarDataProvider.swift`). Reuse the agenda-slide design from `dogfood/dashboard/index.html` (day headers “AUJOURD’HUI/DEMAIN/…”, colored dot, time, title, location). **`calendar` is consent-gated**: when `data.cal.__denied === true`, show “Autorise l'agenda dans Better Widgets”. Empty events → “Rien à venir”. medium = next 2-3 events; large = grouped-by-day list.

- [ ] **Step 3: Add tests** (cover the render AND the denied path)

```swift
func testAgendaManifestValid() throws {
    let m = try BundledTemplates.manifest("agenda")
    XCTAssertEqual(m.sources.first?.type, "calendar")
    XCTAssertTrue(m.sources.first?.requiresConsent ?? false)
}

@MainActor
func testAgendaRenders() async throws {
    let data: [String: Any] = ["cal": ["events": [
        ["title": "Sport", "start": "2026-07-07T12:00:00+02:00", "end": "2026-07-07T13:00:00+02:00", "allDay": false, "calendarColor": "green"],
        ["title": "Concert", "start": "2026-07-07T20:00:00+02:00", "end": "2026-07-07T23:00:00+02:00", "allDay": false, "calendarColor": "blue"]
    ]]]
    try await assertRenders("agenda", data: data)
}

@MainActor
func testAgendaRendersDenied() async throws {
    try await assertRenders("agenda", data: ["cal": ["__denied": true]])
}
```

- [ ] **Step 4: Run → PASS. Step 5: Visual check (incl. denied state). Step 6: Commit** `feat(templates): agenda (EventKit) rewrite`.

---

### Task 6: `status` template

**Files:** Create `templates/status/{manifest.json,index.html}`; modify `BundledTemplateTests.swift`.

- [ ] **Step 1: `status/manifest.json`**

```json
{
  "id": "status", "name": "Services", "version": "1.0.0",
  "sizes": ["medium", "large"], "refresh": 120,
  "params": [
    { "key": "url", "type": "url", "label": "Endpoint statut (JSON)", "default": "http://homeserver.local:3001/api/status" },
    { "key": "title", "type": "string", "label": "Titre", "default": "Services" }
  ],
  "sources": [ { "key": "svc", "type": "json", "config": { "url": "{{url}}" } } ]
}
```

- [ ] **Step 2: `status/index.html`** — from the starter. Normalize `data.svc` to a list: accept either a top-level array `[{name, up, ms?}]` OR `{ services: [...] }` (`const list = Array.isArray(data.svc) ? data.svc : (data.svc && data.svc.services) || []`). Reuse the monitoring tile from `dogfood/gallery.html`: per service a green/red dot (`up` truthy → green, else red), name, latency `ms` (right-aligned, tabular) when present; header `params.title` + `% up` (share of `up`). Fallback / `stale`: “Endpoint injoignable” + the stale dot. This source is HTTP → relies on the private-host allowance (LAN/Tailscale).

- [ ] **Step 3: Add tests** (both accepted shapes)

```swift
func testStatusManifestValid() throws {
    let m = try BundledTemplates.manifest("status")
    XCTAssertEqual(m.sources.first?.type, "json")
}

@MainActor
func testStatusRendersArrayShape() async throws {
    let data: [String: Any] = ["svc": [
        ["name": "api", "up": true, "ms": 142],
        ["name": "db", "up": true, "ms": 4],
        ["name": "worker", "up": false]
    ]]
    try await assertRenders("status", data: data)
}

@MainActor
func testStatusRendersObjectShape() async throws {
    let data: [String: Any] = ["svc": ["services": [["name": "web", "up": true, "ms": 30]]]]
    try await assertRenders("status", data: data)
}
```

- [ ] **Step 4: Run → PASS. Step 5: Visual check. Step 6: Commit** `feat(templates): status (self-hosted monitoring, private HTTP)`.

---

### Task 7: `home` template (Home Assistant)

**Files:** Create `templates/home/{manifest.json,index.html}`; modify `BundledTemplateTests.swift`.

- [ ] **Step 1: `home/manifest.json`** — note the `secret.Authorization` config key (resolved from Keychain to a request header by the pipeline; never stored in plaintext):

```json
{
  "id": "home", "name": "Maison", "version": "1.0.0",
  "sizes": ["medium", "large"], "refresh": 120,
  "params": [
    { "key": "base", "type": "string", "label": "Hôte Home Assistant", "default": "homeassistant.local:8123" },
    { "key": "entities", "type": "string", "label": "Entités (ids séparés par ,)", "default": "sensor.temperature,sensor.humidity" }
  ],
  "sources": [
    { "key": "ha", "type": "json",
      "config": { "url": "http://{{base}}/api/states", "secret.Authorization": "Bearer <token>" } }
  ]
}
```

- [ ] **Step 2: `home/index.html`** — from the starter. `data.ha` = the HA `/api/states` array `[{ entity_id, state, attributes:{ unit_of_measurement, friendly_name, … } }]`. Filter to `params.entities.split(',')`. Reuse the home tiles from `dogfood/gallery.html`: value tiles (temp/humidity/energy by unit) + on/off chips (states `on`/`off`). Header `Maison`. Fallback when `data.ha` undefined/`__denied`/error: “Connecte ton Home Assistant”. HTTP (LAN) → private-host allowance; secret via Keychain.

- [ ] **Step 3: Add tests**

```swift
func testHomeManifestValid() throws {
    let m = try BundledTemplates.manifest("home")
    let cfg = try XCTUnwrap(m.sources.first?.config)
    XCTAssertNotNil(cfg["secret.Authorization"])
    XCTAssertTrue((cfg["url"] ?? "").hasPrefix("http://"))
}

@MainActor
func testHomeRenders() async throws {
    let data: [String: Any] = ["ha": [
        ["entity_id": "sensor.temperature", "state": "21.5", "attributes": ["unit_of_measurement": "°C", "friendly_name": "Salon"]],
        ["entity_id": "sensor.humidity", "state": "48", "attributes": ["unit_of_measurement": "%", "friendly_name": "Humidité"]],
        ["entity_id": "light.living", "state": "on", "attributes": ["friendly_name": "Salon"]]
    ]]
    try await assertRenders("home", data: data)
}
```

- [ ] **Step 4: Run → PASS. Step 5: Visual check. Step 6: Commit** `feat(templates): home (Home Assistant, private HTTP + Keychain secret)`.

---

### Task 8: `github` template

**Files:** Create `templates/github/{manifest.json,index.html}`; modify `BundledTemplateTests.swift`.

- [ ] **Step 1: `github/manifest.json`** — `secret.Authorization` is OPTIONAL (public repos work unauthenticated); include it so the user can raise the rate limit:

```json
{
  "id": "github", "name": "GitHub", "version": "1.0.0",
  "sizes": ["small", "medium"], "refresh": 1800,
  "params": [
    { "key": "owner", "type": "string", "label": "Owner", "default": "my-monkeys" },
    { "key": "repo", "type": "string", "label": "Repo", "default": "better-widgets" }
  ],
  "sources": [
    { "key": "gh", "type": "json", "config": { "url": "https://api.github.com/repos/{{owner}}/{{repo}}" } }
  ]
}
```

- [ ] **Step 2: `github/index.html`** — from the starter. `data.gh` = the repo object (`full_name`, `stargazers_count`, `forks_count`, `open_issues_count`, `pushed_at`, `description`). Display: repo name + ⭐ stars (tabular) + forks + open issues; **medium** adds description (clamped) + relative “pushed” time. Use inline FA icons (star/code-fork/circle-dot). Fallback when `data.gh` undefined or `data.gh.message` present (GitHub error body): “Repo introuvable”.

- [ ] **Step 3: Add tests**

```swift
func testGithubManifestValid() throws {
    let m = try BundledTemplates.manifest("github")
    XCTAssertTrue((m.sources.first?.config?["url"] ?? "").hasPrefix("https://api.github.com/"))
}

@MainActor
func testGithubRenders() async throws {
    let data: [String: Any] = ["gh": [
        "full_name": "my-monkeys/better-widgets", "stargazers_count": 42, "forks_count": 3,
        "open_issues_count": 5, "pushed_at": "2026-07-05T10:00:00Z", "description": "Widgets macOS depuis du HTML"
    ]]
    try await assertRenders("github", data: data)
}
```

- [ ] **Step 4: Run → PASS. Step 5: Visual check. Step 6: Commit** `feat(templates): github (API, optional Keychain secret)`.

---

### Task 9: Retire demo templates + repoint default instance + bootstrap test

**Files:**
- Delete: `BetterWidgets/Resources/templates/{hello-clock,feed-list,weather-now}/`
- Modify: `BetterWidgets/App/AppState.swift:47` (demo instance `templateId`)
- Modify: `CLAUDE.md` (template mentions ~line 129, 146-147)
- Modify: `Tests/BundledTemplateTests.swift` (bootstrap test)

**Interfaces:** Consumes `BundledTemplates.ids` (the 8 new ids).

- [ ] **Step 1: Write the failing bootstrap test** in `BundledTemplateTests.swift`:

```swift
func testExactlyTheEightTemplatesAreBundled() throws {
    let dirs = (try? FileManager.default.contentsOfDirectory(at: BundledTemplates.dir, includingPropertiesForKeys: [.isDirectoryKey]))?
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .map { $0.lastPathComponent } ?? []
    XCTAssertEqual(Set(dirs), Set(BundledTemplates.ids), "bundled template dirs must be exactly the 8 ids")
    for id in BundledTemplates.ids { XCTAssertEqual(try BundledTemplates.manifest(id).id, id, "\(id) manifest.id mismatch") }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test … -only-testing:BetterWidgetsTests/BundledTemplateTests/testExactlyTheEightTemplatesAreBundled`
Expected: FAIL — extra dirs `hello-clock`, `feed-list`, `weather-now` still present.

- [ ] **Step 3: Delete the three demo dirs**

```bash
git rm -r BetterWidgets/Resources/templates/hello-clock BetterWidgets/Resources/templates/feed-list BetterWidgets/Resources/templates/weather-now
```

- [ ] **Step 4: Repoint the default demo instance** — in `BetterWidgets/App/AppState.swift`, the line creating the first-launch demo instance currently reads `templateId: "hello-clock"` / name `"Horloge"`. Change to the offline-safe `system` template:

```swift
let demo = WidgetInstance(id: UUID(), name: "Système", templateId: "system",
```

(keep the rest of that initializer identical; read the surrounding lines first to preserve the signature).

- [ ] **Step 5: Update `CLAUDE.md`** — replace the demo-template references (the `hello-clock` bootstrap mention ~L129 and the "Trois templates démo bundlés … `feed-list`/`agenda`/`weather-now`" passage ~L146-147) with a one-line note that the app ships 8 home templates (`weather`, `crypto`, `system`, `news`, `agenda`, `status`, `home`, `github`).

- [ ] **Step 6: Run to verify it passes**

Run: `xcodegen generate && xcodebuild test … -only-testing:BetterWidgetsTests/BundledTemplateTests`
Expected: `testExactlyTheEightTemplatesAreBundled` + all per-template tests PASS.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "chore(templates): retire demo templates, default to system, bootstrap test"
```

---

### Task 10: Full-suite regression + whole-set visual verification

**Files:** none (verification only).

- [ ] **Step 1: Full test suite**

Run: `xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets -destination 'platform=macOS,arch=arm64'`
Expected: `** TEST SUCCEEDED **` — all prior tests (AppState, SharedStore, Render, Manifest, …) still green after the template changes. If `AppStateTests`/`SharedStoreTests` still reference a self-created `hello-clock` fixture, that's fine (they build their own dir and don't depend on the bundled one) — confirm they pass; do NOT delete those fixtures.

- [ ] **Step 2: Whole-set contact sheet** — build a `dogfood/templates-contact.html` (mirroring `dogfood/gallery.html`) that renders all 8 bundled templates at each declared size in light AND dark from the test fixtures, screenshot via headless Chrome @2x, and eyeball: no overflow, legible hierarchy, icons/charts present, fallback states correct. Fix any issues in the offending template (re-run its render test after).

- [ ] **Step 3: Real-app spot check (Maxim)** — note in the final report that placing 1-2 of the new templates as desktop widgets from a fresh build is the remaining human verification (as with prior plans).

- [ ] **Step 4: Commit** any visual fixes; otherwise nothing to commit for this task.

---

## Notes for the executor

- **Data-shape confirmation**: Tasks 3/4/5 tell you to read `SystemDataProvider.swift` / `RSSDataProvider.swift` / `CalendarDataProvider.swift` to confirm exact `data.<key>` shapes before writing the template + fixture. Do that — the fixtures in the tests must match the real provider output, or the render test passes but the live widget shows the fallback.
- **Reuse, don't reinvent**: `dogfood/gallery.html` and `dogfood/dashboard/index.html` (in the working tree) already contain the exact token blocks, the Font Awesome `ICON` SVG strings, `wxIcon`/`wxColor`, `pointsOf/smooth/spark`, and `ring`. Copy them; keep every template visually consistent.
- **Fitness/transport** are intentionally NOT templates (no web provider) — they remain README demos only.
- **Distribution (Plan 4b)** — DMG/notarization/cask — is out of scope and blocked on Maxim's Apple portal steps.
