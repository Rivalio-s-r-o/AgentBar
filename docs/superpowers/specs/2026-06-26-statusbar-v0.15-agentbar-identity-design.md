# StatusBar v0.15 — AgentBar identita & polish

- **Datum:** 2026-06-26
- **Stav:** Návrh (odsouhlasen uživatelem; název a ikona vybrány).
- **Motivace:** Proud B z optimalizačního auditu — z „StatusBar" (pracovní název) udělat kvalitní pojmenovaný macOS doplněk: **název AgentBar**, **ikona**, **„O aplikaci"**, **přístupnost**.
- **Verze:** 0.15.0. Větev `feat/v0.15-agentbar-identity`. Baseline 174 testů.

## 1. Přehled
Čtyři polish prvky identity. **Žádná změna chování dat ani existujícího UI** (jen názvy/ikona/About/a11y popisky).

### Rozhodnutí (odsouhlasena)
- **Název: AgentBar** (jasně „stavová lišta pro AI agenty"; zachovává „Bar").
- **Přejmenování JEN zobrazované** — `CFBundleIdentifier cz.rivalio.statusbar` **ZACHOVÁN** (jinak ztráta nastavení + keychain „Always Allow" re-prompt + rozbitý stabilní podpis). Interní názvy targetů (StatusBarApp/StatusBarKit) i podpisový cert („StatusBar Dev", vázán na bundle ID) **beze změny**. GitHub repo název řeší proud C.
- **Ikona = uživatelovo logo** (lesklý dvoutónový burn bar na modro-fialovém gradientu; zdroj `~/Downloads/export/StatusBar-D2-*.png`, 1024 master). `.icns` ověřeno buildovatelné (sips + iconutil).
- **„O aplikaci" = nativní `NSApp.orderFrontStandardAboutPanel`** (ne vlastní okno).

### Ne-cíle (YAGNI)
- Přejmenování GitHub repa / interních targetů / bundle ID. Žádné nové featury. Vlastní About okno.

## 2. Architektura

| Komponenta | Změna | Test |
|---|---|---|
| `Resources/Info.plist` | `CFBundleName`/`CFBundleExecutable` = AgentBar; `CFBundleIconFile` = AppIcon; verze 0.15.0; bundle id BEZE ZMĚNY | — |
| `Resources/AppIcon/AppIcon-1024.png` (nový) | zdrojové logo (1024 master) do repa | — |
| `scripts/make-icon.sh` (nový) | sips 1024→všechny velikosti + iconutil → `Resources/AppIcon.icns` | — |
| `Resources/AppIcon.icns` (nový, generovaný+commitnutý) | hotová ikona pro make-app.sh | — |
| `scripts/make-app.sh` | `APP=AgentBar.app`, binárka → `MacOS/AgentBar`, **`mkdir Contents/Resources` + kopie `AppIcon.icns`**; cert „StatusBar Dev" beze změny | — |
| App `Localizable.strings` (en+cs) | `menubar.fallback`/`settings.version`/`window.settings.title` → AgentBar; nový `settings.about` | parity |
| `SettingsView` | tlačítko/řádek „O aplikaci…" → `onAbout` callback | build/smoke |
| `SettingsWindowController` + `AppDelegate` | `onAbout` → `NSApp.orderFrontStandardAboutPanel(options:)` (AgentBar, verze, credits=GitHub) | build/smoke |
| `MenuBarController.render` | `statusItem.button?.setAccessibilityLabel(...)` ze stavu (VoiceOver) | build/smoke |
| `PopoverView` | dekorativní bary/tečky `.accessibilityHidden(true)`; řádky oken `.accessibilityElement(children:.combine)` | build/smoke |

### 2.1 Ikona — pipeline
- Zdroj: 1024×1024 PNG (uživatelovo logo) → `Resources/AppIcon/AppIcon-1024.png`.
- `scripts/make-icon.sh`: vytvoří `AppIcon.iconset` (16/32/64/128/256/512/1024 přes `sips -z`), namapuje na `icon_NxN[@2x].png`, `iconutil -c icns` → `Resources/AppIcon.icns`. Idempotentní (přepíše).
- `make-app.sh` přidá: `mkdir -p "$APP/Contents/Resources"; cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"` (PŘED codesign — `Contents/Resources` je standardní místo, NErozbíjí codesign na rozdíl od bundle root).
- Info.plist `CFBundleIconFile = AppIcon`.

### 2.2 „O aplikaci"
- `SettingsView`: nový `var onAbout: () -> Void = {}`; tlačítko „O aplikaci…" (klíč `settings.about`) ve footeru.
- `AppDelegate`: `onAbout` → `NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "AgentBar", .applicationVersion: <CFBundleShortVersionString>, .credits: NSAttributedString("github.com/Rivalio-s-r-o/StatusBar")])`. Aktivovat app (`NSApp.activate()`).
- `SettingsWindowController` protáhne `onAbout` do `SettingsView`.

### 2.3 Přístupnost
- **Status item:** v `render` po vykreslení `statusItem.button?.setAccessibilityLabel("AgentBar — " + a11yStatus(visible))` kde `a11yStatus` = per-provider „Claude 73 % zbývá" join „, " (z viditelných/filtrovaných usages; jednořádkové). Reuse formátu `menubar.tooltip.ok` bez newlinů.
- **Popover:** `TimelineBarView`/`BurnBarView`/`FreshnessDot` = dekorativní → `.accessibilityHidden(true)` (čísla jsou v Text). Každý řádek okna ve `windowsList` → `.accessibilityElement(children: .combine)` (VoiceOver přečte „Session, 73 % zbývá, reset za 25m" jako jeden prvek).

## 3. Verifikace a meze
- **Auto:** existujících 174 testů projde (žádná Kit změna; App-only). Parity en==cs (Kit+App). `swift build` 0 warningů + `swift test`.
- **GAP (uživatel):** AgentBar.app má v Finderu ikonu; název „AgentBar" v liště fallbacku / titulku Nastavení / About panelu; „O aplikaci" otevře nativní panel; VoiceOver na liště řekne stav; nastavení/klíčenka/podpis přežily (bundle id stejný).
- **Build .app:** `make-icon.sh` + `make-app.sh` → AgentBar.app s ikonou, podepsáno „StatusBar Dev", spustitelné.

## 4. Rizika
- **R1 (nízké) — kopie `AppIcon.icns` do `Contents/Resources` vs codesign:** standardní místo (ne bundle root) → bezpečné; ověřit `codesign --verify` po buildu.
- **R2 (nízké) — `CFBundleExecutable` rename:** musí PŘESNĚ sedět s názvem binárky v `MacOS/` (AgentBar) jinak app nespustí. Hlídá make-app.sh + smoke.
- **R3 (nízké) — bundle id zachován:** ověřit, že Info.plist `CFBundleIdentifier` zůstal `cz.rivalio.statusbar` (jinak ztráta nastavení/keychain). Explicitní kontrola v plánu.
- **R4 (nízké) — `setAccessibilityLabel` Swift 6 @MainActor:** volá se z `render` (@MainActor) → OK.
- **R5 (nízké) — About panel credits NSAttributedString** musí mít validní atributy; jednoduchý text stačí.
