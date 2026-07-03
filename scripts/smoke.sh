#!/usr/bin/env bash
# Smoke E2E: build, launch, assert fresh renders exist in the App Group container.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
xcodebuild build -project BetterWidgets.xcodeproj -scheme BetterWidgets \
  -destination 'platform=macOS' -quiet

APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/BetterWidgets-*/Build/Products/Debug/*.app | head -1)
CONTAINER="$HOME/Library/Group Containers/5C67TFSJ2B.betterwidgets/Store"

pkill -x "BetterWidgets" 2>/dev/null || true
# Wait for the old process to actually die before relaunching — `open` right after
# `pkill` races Launch Services and can fail with -600 (procNotFound) mid-teardown.
for i in $(seq 1 10); do
  pgrep -x "BetterWidgets" >/dev/null 2>&1 || break
  sleep 0.5
done
rm -rf "$CONTAINER/renders"
open "$APP"

for i in $(seq 1 30); do
  count=$(ls "$CONTAINER/renders/" 2>/dev/null | grep -c '\.png$' || true)
  if [ "${count:-0}" -ge 2 ]; then
    echo "✅ smoke OK — $count render(s) in $CONTAINER/renders"
    exit 0
  fi
  sleep 2
done

echo "❌ smoke FAILED — no renders after 60s" >&2
exit 1
