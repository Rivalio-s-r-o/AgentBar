#!/usr/bin/env bash
set -euo pipefail
CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/StatusBarApp"
APP="StatusBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/StatusBar"
codesign --force --sign - "$APP"   # ad-hoc podpis, jinak Gatekeeper blokuje
echo "Hotovo: $APP"
