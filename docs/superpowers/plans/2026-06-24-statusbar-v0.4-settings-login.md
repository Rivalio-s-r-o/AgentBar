# StatusBar v0.4 — Okno Nastavení + spouštět při přihlášení Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Přidat okno Nastavení (samostatné `NSWindow` se SwiftUI obsahem) s přepínačem „Spouštět při přihlášení" (`SMAppService`) a přesunout do něj notifikační předvolby z v0.3; popover dostane tlačítko „Nastavení…".

**Architecture:** Vše app-level (`StatusBarApp`): `LaunchAtLogin` (obal `SMAppService`), `SettingsView` (SwiftUI), `SettingsWindowController` (`NSWindow`), napojení v `PopoverView`/`MenuBarController`/`AppDelegate`. `StatusBarKit` se nemění; notifikační předvolby dál drží testovaný `PreferencesStore` přes stejné `@AppStorage(PreferenceKeys.*)` klíče.

**Tech Stack:** Swift 6, SwiftPM, AppKit/SwiftUI, ServiceManagement. macOS 14+. Navazuje na v0.3 (`main` na `7fd18f2`; větev `feat/v0.4-settings-login`).

## Global Constraints
- macOS 14+, Swift 6. App je postavená na holém `NSApplication` (`main.swift`), `.accessory` policy — žádný SwiftUI App lifecycle (proto `NSWindow`, ne `Settings {}` scéna).
- **`SMAppService`/`ServiceManagement` a `NSWindow` jen v app targetu.** `StatusBarKit` se nemění (žádná regrese 43 testů).
- **Notifikační `@AppStorage` klíče musí zůstat `PreferenceKeys.notificationsEnabled` / `.remainingThresholdPercent`** (sdílené s `PreferencesStore`, který čte koordinátor v0.3) — jen se přesouvá UI z popoveru do okna Nastavení.
- **Launch-at-login se během implementace/smoke NEZAPÍNÁ** (žádný zásah do uživatelových Login Items). Přepínač čte reálný `SMAppService.mainApp.status`.
- Verifikace = `swift build` čistý (vč. app targetu) + `swift test` 43/43 + launch smoke (app nespadne). Vizuál okna a reálný login = manuál uživatele (zdokumentováno).
- Žádné nové unit testy (feature je systémová app-integrace; nelze bezpečně/deterministicky unit-testovat bez side-efektů). Commit po každém tasku.

---

### Task 1: `LaunchAtLogin` + `SettingsView` + `SettingsWindowController`

**Files:**
- Create: `Sources/StatusBarApp/LaunchAtLogin.swift`
- Create: `Sources/StatusBarApp/SettingsView.swift`
- Create: `Sources/StatusBarApp/SettingsWindowController.swift`

**Interfaces:**
- Produces: `enum LaunchAtLogin { static var isEnabled: Bool; static func setEnabled(_:) }`; `struct SettingsView: View { var onRequestNotificationPermission: () -> Void }`; `@MainActor final class SettingsWindowController { init(onRequestNotificationPermission:); func show() }`.

- [ ] **Step 1: Create `Sources/StatusBarApp/LaunchAtLogin.swift`**

```swift
import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ on: Bool) {
        do {
            if on {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            // tiše ignoruj — stav přepínače se srovná podle reálného status
        }
    }
}
```

- [ ] **Step 2: Create `Sources/StatusBarApp/SettingsView.swift`**

```swift
import SwiftUI
import StatusBarKit

struct SettingsView: View {
    var onRequestNotificationPermission: () -> Void = {}

    @AppStorage(PreferenceKeys.notificationsEnabled) private var notifsEnabled = false
    @AppStorage(PreferenceKeys.remainingThresholdPercent) private var threshold = 10
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    private var verze: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nastavení").font(.title3).fontWeight(.semibold)

            Toggle("Spouštět při přihlášení", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    LaunchAtLogin.setEnabled(on)
                    launchAtLogin = LaunchAtLogin.isEnabled   // srovnej podle reálného stavu
                }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Upozornění").font(.headline)
                Toggle("Upozornit, když klesnou zbývající limity", isOn: $notifsEnabled)
                    .onChange(of: notifsEnabled) { _, isOn in
                        if isOn { onRequestNotificationPermission() }
                    }
                HStack {
                    Text("Práh (zbývá ≤)").foregroundStyle(.secondary)
                    Picker("", selection: $threshold) {
                        ForEach([5, 10, 15, 20], id: \.self) { Text("\($0) %").tag($0) }
                    }.labelsHidden().frame(width: 80)
                    Spacer()
                }
            }

            Spacer()
            HStack { Spacer(); Text("StatusBar \(verze)").font(.caption2).foregroundStyle(.tertiary) }
        }
        .padding(20)
        .frame(width: 360, height: 260)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }
}
```

- [ ] **Step 3: Create `Sources/StatusBarApp/SettingsWindowController.swift`**

```swift
import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let onRequestNotificationPermission: () -> Void

    init(onRequestNotificationPermission: @escaping () -> Void = {}) {
        self.onRequestNotificationPermission = onRequestNotificationPermission
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            w.title = "StatusBar — Nastavení"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(
                rootView: SettingsView(onRequestNotificationPermission: onRequestNotificationPermission))
            w.center()
            window = w
        }
        // F1: NSApp.activate(ignoringOtherApps:) je od macOS 14 deprecated → warning.
        // Nové NSApp.activate() + orderFrontRegardless() spolehlivě vynese okno i u .accessory appky.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
```

- [ ] **Step 4: Build.** `swift build` → Expected: **Build complete**, čistý (nové typy zatím nikým nepoužité — to je OK, zkompilují se). `swift test` → 43/43 (žádná změna v `StatusBarKit`).
- [ ] **Step 5: Commit.**

```bash
git add Sources/StatusBarApp/LaunchAtLogin.swift Sources/StatusBarApp/SettingsView.swift Sources/StatusBarApp/SettingsWindowController.swift
git commit -m "feat: LaunchAtLogin + SettingsView + SettingsWindowController (plocha Nastavení)"
```

**Verify success (Task 1):** `swift build` čistý; `swift test` 43/43.
**On failure:** Pokud linker hlásí chybějící `ServiceManagement` → přidej do app targetu v `Package.swift` `linkerSettings: [.linkedFramework("ServiceManagement")]` (na Apple platformách bývá auto-link přes `import`, takže typicky netřeba). Jiná compile chyba → přečti hlášení, oprav podle skutečnosti, ZASTAV při nejasnosti.

---

### Task 2: Napojení — popover „Nastavení…", `MenuBarController`, `AppDelegate`, verze 0.4

**Files:**
- Modify: `Sources/StatusBarApp/PopoverView.swift` (odebrat inline notif sekci, přidat tlačítko „Nastavení…")
- Modify: `Sources/StatusBarApp/MenuBarController.swift` (`onOpenSettings` místo `onRequestNotificationPermission`)
- Modify: `Sources/StatusBarApp/AppDelegate.swift` (držet `SettingsWindowController`, předat `onOpenSettings`)
- Modify: `Resources/Info.plist` (verze 0.4)

**Interfaces:**
- Consumes: `SettingsWindowController`, `NotificationService`.

- [ ] **Step 1: Modify `PopoverView.swift` — props (odebrat notif, přidat `onOpenSettings`).**

Najdi přesně (`old_string`):

```swift
struct PopoverView: View {
    @ObservedObject var store: UsageStore
    let onRefresh: () -> Void
    let onQuit: () -> Void
    var onRequestNotificationPermission: () -> Void = {}

    @AppStorage(PreferenceKeys.notificationsEnabled) private var notifsEnabled = false
    @AppStorage(PreferenceKeys.remainingThresholdPercent) private var threshold = 10

    private var dnesCelkem: Decimal {
```

a nahraď (`new_string`):

```swift
struct PopoverView: View {
    @ObservedObject var store: UsageStore
    let onRefresh: () -> Void
    let onQuit: () -> Void
    var onOpenSettings: () -> Void = {}

    private var dnesCelkem: Decimal {
```

- [ ] **Step 2: Modify `PopoverView.swift` — patička: tlačítko „Nastavení…" místo notif sekce.**

Najdi přesně (`old_string`):

```swift
            if store.orderedUsages.isEmpty { Divider() }   // jinak už divider dává ForEach za poslední kartou
            HStack(spacing: 6) {
                Toggle(isOn: $notifsEnabled) {
                    Text("Upozornit při zbývajících ≤").font(.caption)
                }.toggleStyle(.switch).controlSize(.mini)
                Picker("", selection: $threshold) {
                    ForEach([5, 10, 15, 20], id: \.self) { Text("\($0) %").tag($0) }
                }.labelsHidden().frame(width: 72)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .onChange(of: notifsEnabled) { _, isOn in
                if isOn { onRequestNotificationPermission() }
            }
            HStack { Spacer(); Button("Konec", action: onQuit).buttonStyle(.borderless).font(.caption) }
                .padding(.horizontal, 14).padding(.vertical, 8)
        }.frame(width: 320)
```

a nahraď (`new_string`):

```swift
            if store.orderedUsages.isEmpty { Divider() }   // jinak už divider dává ForEach za poslední kartou
            HStack {
                Button("Nastavení…", action: onOpenSettings).buttonStyle(.borderless).font(.caption)
                Spacer()
                Button("Konec", action: onQuit).buttonStyle(.borderless).font(.caption)
            }.padding(.horizontal, 14).padding(.vertical, 8)
        }.frame(width: 320)
```

- [ ] **Step 3: Modify `MenuBarController.swift` — param `onOpenSettings`.**

Najdi přesně (`old_string`):

```swift
    private let onRequestNotificationPermission: () -> Void
    init(store: UsageStore, onClick: @escaping () -> Void,
         onRequestNotificationPermission: @escaping () -> Void = {}) {
        self.store = store
        self.onRefresh = onClick
        self.onRequestNotificationPermission = onRequestNotificationPermission
        render(store.orderedUsages)
```

a nahraď (`new_string`):

```swift
    private let onOpenSettings: () -> Void
    init(store: UsageStore, onClick: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void = {}) {
        self.store = store
        self.onRefresh = onClick
        self.onOpenSettings = onOpenSettings
        render(store.orderedUsages)
```

- [ ] **Step 4: Modify `MenuBarController.swift` — předat `onOpenSettings` do `PopoverView`.**

Najdi přesně (`old_string`):

```swift
        let hosting = NSHostingController(rootView:
            PopoverView(store: store, onRefresh: onClick, onQuit: { NSApp.terminate(nil) },
                        onRequestNotificationPermission: onRequestNotificationPermission))
```

a nahraď (`new_string`):

```swift
        let hosting = NSHostingController(rootView:
            PopoverView(store: store, onRefresh: onClick, onQuit: { NSApp.terminate(nil) },
                        onOpenSettings: onOpenSettings))
```

- [ ] **Step 5: Modify `AppDelegate.swift` — držet `SettingsWindowController`.**

Najdi přesně (`old_string`):

```swift
    private var lastAlerted: Set<AlertKey> = []
    private var coordinator: RefreshCoordinator!
    private var menuBar: MenuBarController!
    private var timer: Timer?
```

a nahraď (`new_string`):

```swift
    private var lastAlerted: Set<AlertKey> = []
    private var coordinator: RefreshCoordinator!
    private var menuBar: MenuBarController!
    private var settings: SettingsWindowController!
    private var timer: Timer?
```

- [ ] **Step 6: Modify `AppDelegate.swift` — vytvořit controller + předat `onOpenSettings`.**

Najdi přesně (`old_string`):

```swift
        menuBar = MenuBarController(store: store, onClick: { [weak self] in
            Task { await self?.coordinator.refreshNow() }
        }, onRequestNotificationPermission: { [weak self] in
            self?.notifier.requestAuthorizationIfNeeded()
        })
```

a nahraď (`new_string`):

```swift
        settings = SettingsWindowController(onRequestNotificationPermission: { [weak self] in
            self?.notifier.requestAuthorizationIfNeeded()
        })
        menuBar = MenuBarController(store: store, onClick: { [weak self] in
            Task { await self?.coordinator.refreshNow() }
        }, onOpenSettings: { [weak self] in
            self?.settings.show()
        })
```

- [ ] **Step 7: Modify `Resources/Info.plist` — verze 0.4.**

Najdi přesně (`old_string`):

```
  <key>CFBundleVersion</key><string>0.3</string>
  <key>CFBundleShortVersionString</key><string>0.3</string>
```

a nahraď (`new_string`):

```
  <key>CFBundleVersion</key><string>0.4</string>
  <key>CFBundleShortVersionString</key><string>0.4</string>
```

- [ ] **Step 8: Build + smoke.** `swift test` → 43/43. `swift build` → čistý (vč. app targetu; `NotificationService.requestAuthorizationIfNeeded` je teď volán přes `SettingsWindowController`, ne přes popover). `./scripts/make-app.sh debug && open StatusBar.app` → app naběhne bez pádu; v popoveru je dole „Nastavení…" + „Konec" (žádný inline notif přepínač). (Otevření okna + login = manuál uživatele.)
- [ ] **Step 9: Commit.**

```bash
git add Sources/StatusBarApp/PopoverView.swift Sources/StatusBarApp/MenuBarController.swift Sources/StatusBarApp/AppDelegate.swift Resources/Info.plist
git commit -m "feat: popover tlačítko Nastavení… + napojení okna Nastavení + verze 0.4"
```

**Verify success (Task 2):** `swift build` čistý; app naběhne; popover má „Nastavení…".
**On failure:** kterýkoli `old_string` nesedí → přečti reálný soubor a aplikuj princip. ZASTAV, neimprovizuj.

---

## Guardrails
- **Zakázané:** nezapínat login item autonomně (`LaunchAtLogin.setEnabled(true)` nevolat při testu/smoke); neměnit `StatusBarKit`; nepushovat (merge jen lokálně, push na souhlas uživatele).
- **Stop podmínky:** `old_string` nesedí → ZASTAV; 43 testů začne padat → ZASTAV (regrese kit).
- **Kill criteria:** Pokud app target po Task 1/2 nezkompiluje (SwiftUI/ServiceManagement) do 2 pokusů, NEBO app spadne při startu → STOP, zanech report.

## Rollback & Recovery
Aditivní, na větvi `feat/v0.4-settings-login`. Zahodit: `git checkout main && git branch -D feat/v0.4-settings-login`. Per-task: `git revert <commit>`.

## Verifikační gap (důležité)
- **Reálné spuštění při přihlášení** se ověří až odhlášením/přihlášením; launch-at-login je navíc plně spolehlivé jen pro **podepsanou app v `/Applications`** (dev build z projektu macOS nemusí ctít). Ověří uživatel.
- **Vizuál okna Nastavení** + jeho otevření z popoveru = manuál uživatele (build ověří kompilaci; runtime otevření je standardní `NSWindow`).

## Audit Trail (plan-forge AUDIT, 2026-06-24)
- **Lenses:** 1 red-team, 2 security (čisté — login item je user-initiated, žádné secrets), 3 assumptions, 4 dependencies, 5 alternatives, 6 cheap-executor, 7 goal-fit.
- **Findings:** F1 (MED) `NSApp.activate(ignoringOtherApps:)` deprecated na macOS 14 → fixed (`NSApp.activate()` + `orderFrontRegardless()`). Ostatní lenses bez CRIT/HIGH.
- **Tabletop dry run:** prošel — rename `onRequestNotificationPermission`→`onOpenSettings` se promítá konzistentně: PopoverView (Step 1/2 odebere notif sekci + props), MenuBarController (Step 3/4 param+předání), AppDelegate (Step 5/6 drží controller, notif povolení teď přes SettingsWindowController). Žádná visící reference. `requestAuthorizationIfNeeded` zůstává zapojené (přes Settings).
- **Assumptions k ověření v buildu:** ServiceManagement auto-link přes `import` (jinak `.linkedFramework`); `SMAppService.mainApp.status/register/unregister` a `NSApp.activate()` (macOS 14) API názvy.
- **Decisions (autonomně, rozsah vybrán uživatelem):** NSWindow ne Settings-scéna; SMAppService ne legacy; notif předvolby přesunout; login item NEzapínat autonomně; merge bez push (čeká na uživatele).

## Hotová definice v0.4
- Popover má tlačítko „Nastavení…" (místo inline notif přepínače) → otevře okno Nastavení.
- Okno Nastavení: přepínač „Spouštět při přihlášení" + sekce Upozornění (zapnuto + práh) + verze.
- `swift build` čistý vč. app targetu; `swift test` 43/43; app naběhne bez pádu; default chování beze změny; login item se autonomně nezapíná.

## Mimo v0.4 (další fáze)
- **v0.5:** přepínatelné styly lišty (B/C/D) + přepínatelné zbývající/vyčerpané %, líný sken today; OpenAI API (až Admin klíč). Drobnosti z review: `gpt-5.x` komentář, Codex scanner negativní test.
