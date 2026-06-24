#!/usr/bin/env bash
set -euo pipefail
CONFIG="${1:-release}"
swift build -c "$CONFIG"                                   # POZOR: --show-bin-path sám NESTAVÍ → nejdřív reálně postav
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="StatusBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN_DIR/StatusBarApp" "$APP/Contents/MacOS/StatusBar"
codesign --force --sign - "$APP"   # ad-hoc podpis, jinak Gatekeeper blokuje
echo "Hotovo: $APP"
# POZN. lokalizace (v0.9c): SwiftPM resource bundly (StatusBar_StatusBarKit/App.bundle s .lproj)
# se NEkopírují do .app — Bundle.module je najde přes fallback na absolutní cestu do $BIN_DIR
# ("$CONFIG" build je tady reálně postavil). .app tedy spoléhá na existující .build na tomto stroji
# (lokální dev build). Kopírovat bundly do kořene .app rozbíjí codesign (unsealed contents);
# pro distribuci mimo tento stroj by bylo potřeba je vložit do Contents/Resources + upravit resolving.
