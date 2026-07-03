# Better Widgets

App macOS barre de menus qui rend des templates HTML/CSS/JS en PNG clair/sombre et les affiche
comme de **vrais widgets système WidgetKit** (bureau / centre de notifications). Le moteur de
rendu (WKWebView offscreen) est pensé pour rester portable vers iOS en v2.

Statut : **Plan 1 — fondations**, branche `feat/fondations`. Pipeline bout-en-bout prouvé :
lancer l'app rend le template de démo « Horloge » (`hello-clock`) en PNG dans l'App Group, et
l'extension widget est enregistrée auprès du système. Pas encore de galerie/éditeur (Plan 3), pas
de providers weather/calendar/rss (Plan 2), pas de distribution (Plan 4).

Design complet : [`docs/superpowers/specs/2026-07-03-better-widgets-design.md`](docs/superpowers/specs/2026-07-03-better-widgets-design.md).
Plan d'implémentation : [`docs/superpowers/plans/2026-07-03-better-widgets-fondations.md`](docs/superpowers/plans/2026-07-03-better-widgets-fondations.md).

## Prérequis

- Xcode 27 (macOS 14+ SDK), Swift 5.9
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Un compte Apple Developer avec le Team ID `5C67TFSJ2B` (nécessaire pour le code signing
  automatique de l'app, de l'extension widget et de l'App Group)

## Commandes

```bash
xcodegen generate                          # (re)génère BetterWidgets.xcodeproj depuis project.yml
xcodebuild build -project BetterWidgets.xcodeproj -scheme BetterWidgets \
  -destination 'platform=macOS' -quiet     # build app + extension

xcodegen generate && xcodebuild test -project BetterWidgets.xcodeproj -scheme BetterWidgets \
  -destination 'platform=macOS' -quiet     # suite de tests (30 tests)

./scripts/smoke.sh                         # smoke E2E : build, lance l'app, vérifie que
                                            # ≥2 PNG apparaissent dans l'App Group
```

`scripts/smoke.sh` tue toute instance déjà lancée (`BetterWidgets`, sans espace — c'est le nom du
process, pas `CFBundleDisplayName`), attend qu'elle soit bien terminée, vide le dossier de rendus
de l'App Group, relance l'app à neuf et poll jusqu'à 60 s pour voir apparaître les 2 PNG (clair +
sombre) de l'instance de démo.

## Architecture (résumé)

App SwiftUI (`MenuBarExtra`, login item) = composition root : bootstrap des templates bundlés,
scheduler qui déclenche le rendu HTML→PNG (WKWebView offscreen, clair+sombre, @2x) via les
providers de données (`json`/`system` en v1), écrit dans un **App Group** partagé
(`5C67TFSJ2B.betterwidgets`), et appelle `WidgetCenter.reloadTimelines`. L'extension WidgetKit
(3 kinds `bw.small`/`bw.medium`/`bw.large`) est **passive** : elle lit les PNG dans l'App Group et
les affiche, rien de plus. Détails et conventions : [`CLAUDE.md`](CLAUDE.md).
