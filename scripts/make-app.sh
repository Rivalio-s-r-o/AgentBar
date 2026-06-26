#!/usr/bin/env bash
set -euo pipefail
CONFIG="${1:-release}"
swift build -c "$CONFIG"                                   # POZOR: --show-bin-path sám NESTAVÍ → nejdřív reálně postav
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="AgentBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN_DIR/StatusBarApp" "$APP/Contents/MacOS/AgentBar"   # CFBundleExecutable=AgentBar musí sedět
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Stabilní podpis: pokud existuje code-signing identity "StatusBar Dev", podepiš jí
# (designated requirement vázán na cert → keychain "Always Allow" vydrží napříč rebuildy).
# Jinak fallback na ad-hoc (klíčenka se pak ptá po každém buildu) — spusť scripts/setup-signing.sh.
SIGN_ID="$(security find-identity -p codesigning 2>/dev/null | awk '/"StatusBar Dev"/{print $2; exit}')"
if [ -n "${SIGN_ID:-}" ]; then
  codesign --force --sign "$SIGN_ID" "$APP"
  echo "Hotovo: $APP (podepsáno: StatusBar Dev)"
else
  echo "⚠ Identity 'StatusBar Dev' nenalezena → ad-hoc podpis (klíčenka se bude ptát po každém buildu)."
  echo "  Konec opakovaných promptů: spusť ./scripts/setup-signing.sh"
  codesign --force --sign - "$APP"
  echo "Hotovo: $APP (ad-hoc)"
fi
# POZN. lokalizace (v0.9c): SwiftPM resource bundly (StatusBar_StatusBarKit/App.bundle s .lproj)
# se NEkopírují do .app — Bundle.module je najde přes fallback na absolutní cestu do $BIN_DIR
# ("$CONFIG" build je tady reálně postavil). .app tedy spoléhá na existující .build na tomto stroji
# (lokální dev build). Kopírovat bundly do kořene .app rozbíjí codesign (unsealed contents);
# pro distribuci mimo tento stroj by bylo potřeba je vložit do Contents/Resources + upravit resolving.
