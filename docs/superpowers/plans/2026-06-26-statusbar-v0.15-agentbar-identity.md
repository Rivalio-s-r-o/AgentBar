# StatusBar v0.15 — AgentBar identita & polish — Implementační plán

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps `- [ ]`.

**Goal:** Z „StatusBar" udělat pojmenovaný macOS doplněk **AgentBar**: ikona aplikace, přejmenování (jen zobrazované), „O aplikaci" panel, přístupnost.

**Architecture:** Čistě App/bundling vrstva. Zdrojové logo + `make-icon.sh` (sips/iconutil) → `.icns`; `make-app.sh` ho vloží + přejmenuje bundle; About přes nativní panel; a11y popisky na liště + popoveru. Bundle id zachován.

**Tech Stack:** AppKit (NSApplication about panel, NSStatusItem accessibility), SwiftUI (.accessibility*), bash (sips, iconutil, codesign), Swift 6.

## Global Constraints
- **`CFBundleIdentifier = cz.rivalio.statusbar` ZACHOVÁN** (jinak ztráta nastavení + keychain „Always Allow" re-prompt + rozbitý podpis). Podpisový cert „StatusBar Dev" + interní target názvy (StatusBarApp/StatusBarKit) BEZE ZMĚNY.
- **Žádná změna chování dat ani existujícího UI** — jen názvy/ikona/About/a11y. Existujících **174 testů** projde (App-only). Parity en==cs.
- **Verze 0.15.0**. Build 0 warningů. NEspouštět GUI app (jen build + make-app.sh).
- Zobrazovaný název všude: **AgentBar**.

---

### Task 1: Ikona — zdroj do repa + make-icon.sh + AppIcon.icns

**Files:**
- Create: `Resources/AppIcon/AppIcon-1024.png` (zkopírováno z `~/Downloads/export/StatusBar-D2-1024.png`)
- Create: `scripts/make-icon.sh`
- Create: `Resources/AppIcon.icns` (vygenerováno)

- [ ] **Step 1:** Zkopírovat master logo do repa:
```bash
mkdir -p Resources/AppIcon
cp ~/Downloads/export/StatusBar-D2-1024.png Resources/AppIcon/AppIcon-1024.png
file Resources/AppIcon/AppIcon-1024.png   # → PNG image data, 1024 x 1024
```

- [ ] **Step 2:** Vytvořit `scripts/make-icon.sh`:
```bash
#!/usr/bin/env bash
# Vygeneruje Resources/AppIcon.icns z 1024px masteru (sips + iconutil). Idempotentní.
set -euo pipefail
SRC="Resources/AppIcon/AppIcon-1024.png"
IS="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$IS"
gen() { sips -z "$1" "$1" "$SRC" --out "$IS/$2" >/dev/null; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
gen 1024 icon_512x512@2x.png
iconutil -c icns "$IS" -o Resources/AppIcon.icns
echo "Hotovo: Resources/AppIcon.icns"
```

- [ ] **Step 3:** Spustit + ověřit:
```bash
chmod +x scripts/make-icon.sh
./scripts/make-icon.sh
file Resources/AppIcon.icns   # → Mac OS X icon
```
Expected: `Resources/AppIcon.icns` vznikl, typ „Mac OS X icon".

- [ ] **Step 4:** Commit:
```bash
git add Resources/AppIcon/AppIcon-1024.png scripts/make-icon.sh Resources/AppIcon.icns
git commit -m "feat: ikona aplikace (logo → AppIcon.icns přes make-icon.sh)"
```

**Pozn.:** `.icns` je binární, commitnutá (make-app.sh ji jen kopíruje, build nevyžaduje iconutil). `.gitignore` má `*.app` ale NE `*.icns` ani `Resources/` → commitne se.

---

### Task 2: Bundle rename na AgentBar + vložení ikony (Info.plist + make-app.sh)

**Files:**
- Modify: `Resources/Info.plist`
- Modify: `scripts/make-app.sh`

- [ ] **Step 1:** Upravit `Resources/Info.plist` (PlistBuddy):
```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleName AgentBar" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable AgentBar" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" Resources/Info.plist
# bundle id, verze ZATÍM beze změny (verzi bumpne Task 5)
```
Ověřit:
```bash
/usr/libexec/PlistBuddy -c "Print" Resources/Info.plist
```
Expected: `CFBundleName = AgentBar`, `CFBundleExecutable = AgentBar`, `CFBundleIconFile = AppIcon`, **`CFBundleIdentifier = cz.rivalio.statusbar` (NEZMĚNĚN)**.

- [ ] **Step 2:** Upravit `scripts/make-app.sh` — NAHRADIT řádky `APP="StatusBar.app"` … `cp "$BIN_DIR/StatusBarApp" "$APP/Contents/MacOS/StatusBar"`:
```bash
APP="AgentBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN_DIR/StatusBarApp" "$APP/Contents/MacOS/AgentBar"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
```
(`CFBundleExecutable = AgentBar` MUSÍ sedět s `MacOS/AgentBar`. Codesign blok a `SIGN_ID` grep na „StatusBar Dev" ZŮSTÁVÁ beze změny — cert je vázán na bundle id, ne název. Echo hlášky „Hotovo: $APP" se aktualizují automaticky přes `$APP`.)

- [ ] **Step 3:** Postavit a ověřit:
```bash
./scripts/make-icon.sh
./scripts/make-app.sh
ls -d AgentBar.app
/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" AgentBar.app/Contents/Info.plist   # cz.rivalio.statusbar
codesign --verify --deep --strict AgentBar.app && echo "podpis OK"
ls AgentBar.app/Contents/Resources/AppIcon.icns
rm -rf StatusBar.app   # starý bundle (gitignored)
```
Expected: AgentBar.app existuje, bundle id zachován, podpis validní, ikona v Contents/Resources.

- [ ] **Step 4:** Commit:
```bash
git add Resources/Info.plist scripts/make-app.sh
git commit -m "feat: bundle rename StatusBar→AgentBar (display-only, bundle id zachován) + ikona do .app"
```

---

### Task 3: UI texty AgentBar + „O aplikaci" panel

**Files:**
- Modify: `Sources/StatusBarApp/Resources/en.lproj/Localizable.strings`, `cs.lproj/Localizable.strings`
- Modify: `Sources/StatusBarApp/SettingsView.swift`, `SettingsWindowController.swift`, `AppDelegate.swift`

**Interfaces:**
- Produces: `SettingsView.onAbout: () -> Void`; `SettingsWindowController` přidá `onAbout` param; `AppDelegate.showAbout()`.

- [ ] **Step 1:** App `en.lproj/Localizable.strings` — NAHRADIT hodnoty + přidat klíč:
```
"settings.version" = "AgentBar %@";
"menubar.fallback" = "AgentBar";
"window.settings.title" = "AgentBar — Settings";
"settings.about" = "About AgentBar…";
```
A `cs.lproj/Localizable.strings`:
```
"settings.version" = "AgentBar %@";
"menubar.fallback" = "AgentBar";
"window.settings.title" = "AgentBar — Nastavení";
"settings.about" = "O aplikaci AgentBar…";
```
(POZN.: `settings.version`/`menubar.fallback`/`window.settings.title` už existují — měníš HODNOTU; `settings.about` je NOVÝ klíč v obou jazycích.)

- [ ] **Step 2:** `SettingsView` — přidat `var onAbout: () -> Void = {}` (k ostatním callbackům) a footer tlačítko. NAJÍT konec `body` VStacku (za sekcí „Aktualizace", před `.controlSize(.small)`) a přidat footer:
```swift
            HStack {
                Button(String(localized: "settings.about", bundle: .module)) { onAbout() }
                    .buttonStyle(.link)
                Spacer()
            }.padding(.top, 2)
```

- [ ] **Step 3:** `SettingsWindowController` — přidat `onAbout` param a protáhnout do `SettingsView`. V `init` přidat `private let onAbout: () -> Void` + param `onAbout: @escaping () -> Void = {}` → `self.onAbout = onAbout`; v `SettingsView(...)` přidat `onAbout: onAbout`.

- [ ] **Step 4:** `AppDelegate` — přidat `showAbout()` a předat do settings:
```swift
    private func showAbout() {
        NSApp.activate()
        let credits = NSAttributedString(
            string: "github.com/Rivalio-s-r-o/StatusBar",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor])
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "AgentBar",
            .applicationVersion: version,
            .credits: credits,
        ])
    }
```
V `settings = SettingsWindowController(...)` přidat argument `onAbout: { [weak self] in self?.showAbout() }`.

- [ ] **Step 5:** Build + test:
```bash
swift build -c debug    # 0 errors, 0 warnings
swift test              # 174 PASS
```
Parity:
```bash
diff <(grep -oE '^"[^"]+"' Sources/StatusBarApp/Resources/en.lproj/Localizable.strings | sort) <(grep -oE '^"[^"]+"' Sources/StatusBarApp/Resources/cs.lproj/Localizable.strings | sort)
```
Expected: prázdný (parity OK).

- [ ] **Step 6:** Commit:
```bash
git add Sources/StatusBarApp/Resources Sources/StatusBarApp/SettingsView.swift Sources/StatusBarApp/SettingsWindowController.swift Sources/StatusBarApp/AppDelegate.swift
git commit -m "feat: UI texty AgentBar + O aplikaci (nativní about panel)"
```

**Pozn. reviewerovi:** `NSApp.orderFrontStandardAboutPanel(options:)` použije `CFBundleIconFile` z Info.plist (ale za běhu z `Bundle.main` SwiftPM exe — ikona se v panelu ukáže jen u nabundlované .app, ne při `swift run`; OK). `.applicationName` přebije CFBundleName.

---

### Task 4: Přístupnost — status item label + popover a11y

**Files:**
- Modify: `Sources/StatusBarApp/MenuBarController.swift`, `Sources/StatusBarApp/PopoverView.swift`

- [ ] **Step 1:** `MenuBarController` — přidat a11y label do `render`. V metodě `render(_ allUsages:)`, na KONCI (za `statusItem.button?.toolTip = toolTipText(usages)`), přidat:
```swift
        statusItem.button?.setAccessibilityLabel(a11yLabel(usages))
```
A přidat helper:
```swift
    private func a11yLabel(_ usages: [ProviderUsage]) -> String {
        let parts = usages.compactMap { u -> String? in
            guard case .ok = u.status else { return nil }
            return String(format: NSLocalizedString("menubar.tooltip.ok", bundle: .module, comment: ""),
                          u.displayName, max(0, 100 - u.nearestLimitPercent))
        }
        let body = parts.isEmpty ? NSLocalizedString("menubar.fallback", bundle: .module, comment: "") : parts.joined(separator: ", ")
        return "AgentBar — \(body)"
    }
```
(reuse `menubar.tooltip.ok` = „%@: %lld%% zbývá", join „, " na jeden řádek pro VoiceOver.)

- [ ] **Step 2:** `PopoverView` — skrýt dekorativní prvky před VoiceOverem a sloučit řádky oken. V `FreshnessDot.body`, přidat `.accessibilityHidden(true)` na `Circle()`. V `windowsList`, přidat `.accessibilityHidden(true)` na `TimelineBarView(...)`, a obalit celý per-okno `VStack` modifikátorem `.accessibilityElement(children: .combine)`:
```swift
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) { … }            // label + % + reset (beze změny)
                TimelineBarView(bar: …).accessibilityHidden(true)
                paceRow(w)
            }
            .accessibilityElement(children: .combine)
```

- [ ] **Step 3:** Build + test:
```bash
swift build -c debug    # 0 errors, 0 warnings
swift test              # 174 PASS
```

- [ ] **Step 4:** Commit:
```bash
git add Sources/StatusBarApp/MenuBarController.swift Sources/StatusBarApp/PopoverView.swift
git commit -m "a11y: VoiceOver popisek lišty + sloučené řádky oken v popoveru"
```

---

### Task 5: Finalizace — verze 0.15.0 + plný test + build .app

**Files:**
- Modify: `Resources/Info.plist`

- [ ] **Step 1:** Bump verze:
```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.15.0" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 0.15.0" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist   # 0.15.0
```

- [ ] **Step 2:** Plný test + release build:
```bash
swift test                  # 174 PASS
swift build -c release      # 0 errors, 0 warnings
```

- [ ] **Step 3:** Commit:
```bash
git add Resources/Info.plist
git commit -m "chore: verze 0.15.0 (AgentBar identita)"
```

**Pozn.:** Finální `./scripts/make-app.sh` (→ AgentBar.app s ikonou) + manuální ověření (ikona v Finderu, About panel, VoiceOver, nastavení/klíčenka přežily) dělá orchestrátor/uživatel po finálním review.

---

## Self-Review (orchestrátor)
- **Spec coverage:** ikona (T1+T2), rename (T2+T3 texty), About (T3), a11y (T4), verze (T5). ✓
- **Bundle id zachován:** explicitně neměněn (T2 Step 1 komentář + T2 Step 3 kontrola). ✓
- **Placeholdery:** žádné — kód/příkazy doslovně. ✓
- **Type consistency:** `onAbout` (T3 napříč SettingsView/Controller/AppDelegate), `a11yLabel` (T4). ✓
- **Parity:** `settings.about` přidán do en i cs (T3). ✓
