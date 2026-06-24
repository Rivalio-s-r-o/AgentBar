# StatusBar v0.4 — Okno Nastavení + spouštět při přihlášení

- **Datum:** 2026-06-24
- **Stav:** Návrh (rozsah vybrán uživatelem; designová rozhodnutí dokumentována)
- **Navazuje na:** v0.1–v0.3. Celkový spec: `2026-06-23-statusbar-usage-monitor-design.md`.

## 1. Přehled

v0.4 přidává **okno Nastavení** (samostatné `NSWindow` se SwiftUI obsahem) a přepínač
**„Spouštět při přihlášení"** (`SMAppService`). Předvolby notifikací z v0.3 (zapnuto +
práh) se **přesunou** z popoveru do okna Nastavení; popover místo nich dostane tlačítko
**„Nastavení…"**. Lišta i logika spotřeby/limitů/dnešních tokenů se nemění.

### Cíle
- Tlačítko **„Nastavení…"** v popoveru otevře okno Nastavení.
- Okno Nastavení: přepínač **Spouštět při přihlášení**, sekce **Upozornění** (zapnuto + práh, přesunuto z v0.3), údaj o verzi.
- **Spouštět při přihlášení** přes `SMAppService.mainApp` (register/unregister), stav přepínače = reálný `status == .enabled`.

### Ne-cíle (mimo rozsah v0.4)
- Přepínatelné styly lišty (B/C/D) — samostatná fáze (v0.5).
- OpenAI API útrata (odloženo — chybí Admin klíč).
- Líný sken today (v0.5), drobnosti z review.

## 2. Klíčová rozhodnutí (dokumentovaná)

1. **Okno = `NSWindow` + `NSHostingController(SettingsView)`**, NE SwiftUI `Settings` scéna — app je postavená na holém `NSApplication` (`main.swift`), bez SwiftUI App lifecycle, takže `Settings {}` scéna není k dispozici. App zůstává `.accessory` (bez Dock ikony); okno se ukáže přes `NSApp.activate(ignoringOtherApps:)` + `makeKeyAndOrderFront`.
2. **Jedna instance okna** (drží `SettingsWindowController`, `isReleasedWhenClosed = false`); opakované „Nastavení…" jen vynese existující okno dopředu.
3. **Notifikační předvolby se přesunou** do okna Nastavení (stejné `@AppStorage(PreferenceKeys.*)` klíče → chování beze změny, jen jiné místo v UI). Popover ztratí inline přepínač, dostane tlačítko „Nastavení…".
4. **Launch-at-login = `SMAppService.mainApp`.** Přepínač čte `status == .enabled`; při zapnutí `register()`, při vypnutí `unregister()`. Chyby se tiše ignorují a přepínač se srovná podle reálného `status`.
5. **Verze bundlu → 0.4.**

## 3. Architektura

| Komponenta | Vrstva | Odpovědnost |
|---|---|---|
| `LaunchAtLogin` | StatusBarApp | Obal nad `SMAppService.mainApp`: `isEnabled: Bool`, `setEnabled(_:)` (register/unregister, chyby ignoruje). |
| `SettingsView` | StatusBarApp | SwiftUI: toggle „Spouštět při přihlášení" (přes `LaunchAtLogin`, `@State` + `.onAppear` refresh), sekce „Upozornění" (toggle + práh přes `@AppStorage(PreferenceKeys.*)`, povolení přes injektovaný closure), verze. |
| `SettingsWindowController` | StatusBarApp | Drží jedno `NSWindow` s `NSHostingController(SettingsView)`; `show()` ho vytvoří (jednou) a vynese dopředu. |
| `PopoverView` (změna) | StatusBarApp | Místo notifikační sekce → tlačítko „Nastavení…" (`onOpenSettings`). |
| `MenuBarController` (změna) | StatusBarApp | Param `onOpenSettings` (místo `onRequestNotificationPermission`) → předá do `PopoverView`. |
| `AppDelegate` (změna) | StatusBarApp | Drží `SettingsWindowController(onRequestNotificationPermission:)`; `onOpenSettings: { settings.show() }` předá do `MenuBarController`. |

Vše app-level (AppKit/SwiftUI/ServiceManagement). `StatusBarKit` se nemění. Existující `PreferencesStore` (testovaný) drží notifikační předvolby dál.

## 4. Datový tok
1. Klik na ikonu → popover; klik „Nastavení…" → `onOpenSettings` → `SettingsWindowController.show()`.
2. V okně: přepínač launch-at-login volá `LaunchAtLogin.setEnabled`; notifikační toggle/práh píší do `@AppStorage` (stejné klíče jako `PreferencesStore` čte koordinátor v0.3); zapnutí notifikací vyvolá `requestAuthorizationIfNeeded` (injektovaný closure z `AppDelegate`).
3. Zbytek (refresh, vyhodnocení alertů z v0.3) beze změny.

## 5. Verifikace a její meze (důležité — autonomní běh)
- **Plně ověřitelné:** `swift build` čistý (vč. app targetu — chytne compile chyby SwiftUI/AppKit/ServiceManagement), `swift test` 43/43 (žádná změna v `StatusBarKit`), app se spustí bez pádu, default chování beze změny.
- **GAP (ověří uživatel):** vizuál okna Nastavení; **skutečné spuštění při přihlášení** (vyžaduje odhlášení/přihlášení). Navíc launch-at-login je plně spolehlivé jen pro **podepsanou app v `/Applications`**; u dev buildu z projektu se login item zaregistruje, ale macOS ho nemusí ctít / po přesnutí appky zneplatní.
- **Bezpečnost běhu:** během vývoje/smoke se **NEzapíná** login item (žádný zásah do uživatelových Login Items); přepínač zůstává v reálném (vypnutém) stavu.

## 6. Testování
- Žádné nové unit testy (feature je čistě app-level systémová integrace; `SMAppService`/`NSWindow` nelze bezpečně/deterministicky unit-testovat bez side-efektů a bundlu). Notifikační předvolby pokrývá existující `PreferencesStoreTests`.
- Ověření = clean build (vč. app targetu) + launch smoke (app nespadne) + manuální kontrola uživatelem (okno + login).

## 7. Fázování (tasky)
1. `LaunchAtLogin` + `SettingsView` + `SettingsWindowController` (nová plocha Nastavení). Build-verified.
2. Napojení: `PopoverView` (tlačítko „Nastavení…", odebrání inline notif sekce), `MenuBarController` (`onOpenSettings`), `AppDelegate` (drží controller, předá closure), verze 0.4. Build + smoke.

## 8. Rizika
- **R1 (střední):** launch-at-login u dev buildu nemusí reálně fungovat (signing/umístění) → mitigace: kód korektní, jasně zdokumentovaný caveat, uživatel ověří; pro reálné použití app do `/Applications`.
- **R2 (nízké):** `.accessory` app a zobrazení okna → `NSApp.activate` + `makeKeyAndOrderFront` (běžný pattern menu bar appek).
- **R3 (nízké):** přesun notif. předvoleb → stejné `@AppStorage` klíče, žádná migrace, koordinátor čte beze změny.
- **R4 (nízké):** nízká unit-test pokrytost → kompenzováno clean buildem app targetu + smoke; jádro (PreferencesStore, AlertEvaluator) už pokryté z v0.3.
