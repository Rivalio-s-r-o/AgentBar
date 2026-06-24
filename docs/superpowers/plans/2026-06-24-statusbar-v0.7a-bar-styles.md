# StatusBar v0.7a — Přepínatelné styly lišty + význam % — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lišta umí 4 přepínatelné styly (A/B/C/D) a přepínač zbývající/vyčerpané %, volitelné v okně Nastavení; default = současné chování (styl A + zbývající %).

**Architecture:** Veškerá style-logika je v `StatusBarKit` (`MenuBarStyle` enum + rozšířený `MenuBarSegment` s polem `leading: Leading` + `MenuBarTitleBuilder.segments(for:style:showUsedPercent:)`); AppKit renderer jen mechanicky vykreslí segment podle `leading`. Prefs žijí v `PreferencesStore` (UserDefaults). Změna v Nastavení překreslí lištu přes explicitní `onAppearanceChanged` → `MenuBarController.applyAppearance()`.

**Tech Stack:** Swift 6 (strict concurrency), SwiftPM (knihovna `StatusBarKit` + executable `StatusBarApp`), AppKit (`NSStatusItem`), SwiftUI (`SettingsView`), Swift Testing (`@Test`/`#expect`).

## Global Constraints

- Swift 6 strict concurrency. Nepoužívat non-Sendable `static let` formátter (vytvářet lokálně).
- `StatusBarKit` zůstává pure — žádný `import AppKit`/`SwiftUI`/`Security`/síť.
- **Default chování beze změny:** styl A (`dotPercent`) + zbývající % (`showUsedPercent == false`) = bajt-za-bajt stejný výstup lišty jako v0.1–v0.6.
- `MenuBarSegment.init` má `leading: Leading = .providerDot` jako default → stávající volání `MenuBarSegment(providerId:text:level:)` i stávající `segments(for:)` volání kompilují a procházejí beze změny.
- `level` (barva) se **vždy** počítá z vyčerpaného % (`u.nearestLimitPercent`); přepínač `showUsedPercent` mění **jen zobrazené číslo**, ne barvu.
- `level(forPercent:)`: `<75 → .normal`, `75..<90 → .warning`, jinak `.critical` (beze změny).
- Status `.degraded` se v liště chová jako `.ok` (zobrazí číslo ze svých `windows`); jen `.unavailable` → `"—"`.
- Krátké štítky providerů (styl B): `claudeCode → "CC"`, `codex → "CX"`.
- České UI texty s diakritikou.
- Bundle verze → `0.7` (`Resources/Info.plist`, obě pole).
- TDD, časté commity, DRY, YAGNI.

---

### Task 1: Kit — `MenuBarStyle`, `MenuBarSegment.Leading`, builder

**Files:**
- Create: `Sources/StatusBarKit/Formatting/MenuBarStyle.swift`
- Modify: `Sources/StatusBarKit/Formatting/Formatting.swift` (rozšířit `MenuBarSegment` a `MenuBarTitleBuilder.segments`)
- Create (test): `Tests/StatusBarKitTests/MenuBarStyleTests.swift`

**Interfaces:**
- Consumes: `ProviderUsage` (`providerId: ProviderID`, `status: ProviderStatus`, `nearestLimitPercent: Int`), `UsageLevel.level(forPercent:)`, `ProviderID` (`.claudeCode`/`.codex`).
- Produces:
  - `public enum MenuBarStyle: String, Sendable, Equatable, Hashable, CaseIterable { case dotPercent, labelPercent, dotOnly, worst; var displayName: String }`
  - `public enum MenuBarSegment.Leading: Sendable, Equatable { case providerDot, levelDot, label(String), none }`
  - `MenuBarSegment` nově s `public let leading: Leading` a initem `init(providerId:leading:text:level:)` kde `leading` defaultuje na `.providerDot`.
  - `public static func MenuBarTitleBuilder.segments(for:style:showUsedPercent:) -> [MenuBarSegment]` (default `style: .dotPercent`, `showUsedPercent: false`).

- [ ] **Step 1: Napiš `MenuBarStyle.swift` (selže test kompilací — typ ještě neexistuje)**

Create `Sources/StatusBarKit/Formatting/MenuBarStyle.swift`:

```swift
import Foundation

public enum MenuBarStyle: String, Sendable, Equatable, Hashable, CaseIterable {
    case dotPercent      // A — barevná tečka providera + %
    case labelPercent    // B — písmenný štítek (CC/CX) + %
    case dotOnly         // C — jen tečka obarvená podle stavu
    case worst           // D — jediné číslo = nejnižší zbývající napříč providery

    public var displayName: String {
        switch self {
        case .dotPercent:   return "Tečka + %"
        case .labelPercent: return "Štítek + %"
        case .dotOnly:      return "Jen tečka"
        case .worst:        return "Nejkritičtější"
        }
    }
}
```

- [ ] **Step 2: Rozšiř `MenuBarSegment` v `Formatting.swift`**

Nahraď stávající definici `MenuBarSegment` v `Sources/StatusBarKit/Formatting/Formatting.swift` tímto (přidává `Leading` a `leading` s defaultem `.providerDot`):

```swift
public struct MenuBarSegment: Sendable, Equatable {
    public enum Leading: Sendable, Equatable {
        case providerDot          // tečka v barvě providera
        case levelDot             // tečka v barvě stavu (level)
        case label(String)        // písmenný štítek v barvě stavu
        case none                 // bez prefixu
    }
    public let providerId: ProviderID; public let leading: Leading
    public let text: String; public let level: UsageLevel
    public init(providerId: ProviderID, leading: Leading = .providerDot, text: String, level: UsageLevel) {
        self.providerId = providerId; self.leading = leading; self.text = text; self.level = level
    }
}
```

- [ ] **Step 3: Přepiš `MenuBarTitleBuilder.segments` v `Formatting.swift`**

Nahraď stávající `enum MenuBarTitleBuilder { ... }` tímto:

```swift
public enum MenuBarTitleBuilder {
    static func shortLabel(_ id: ProviderID) -> String {
        switch id { case .claudeCode: return "CC"; case .codex: return "CX" }
    }

    private static func displayable(_ u: ProviderUsage) -> Bool {
        if case .unavailable = u.status { return false }; return true
    }

    /// Segment pro styly A/B (per provider, tečka providera nebo štítek).
    private static func perProvider(_ u: ProviderUsage, label: Bool, showUsedPercent: Bool) -> MenuBarSegment {
        let leading: MenuBarSegment.Leading = label ? .label(shortLabel(u.providerId)) : .providerDot
        if case .unavailable = u.status {
            return MenuBarSegment(providerId: u.providerId, leading: leading, text: "—", level: .normal)
        }
        let used = u.nearestLimitPercent
        let shown = showUsedPercent ? used : max(0, 100 - used)
        return MenuBarSegment(providerId: u.providerId, leading: leading,
                              text: "\(shown)%", level: UsageLevel.level(forPercent: used))
    }

    public static func segments(for usages: [ProviderUsage],
                                style: MenuBarStyle = .dotPercent,
                                showUsedPercent: Bool = false) -> [MenuBarSegment] {
        switch style {
        case .dotPercent:
            return usages.map { perProvider($0, label: false, showUsedPercent: showUsedPercent) }
        case .labelPercent:
            return usages.map { perProvider($0, label: true, showUsedPercent: showUsedPercent) }
        case .dotOnly:
            return usages.map { u in
                let level = displayable(u) ? UsageLevel.level(forPercent: u.nearestLimitPercent) : .normal
                return MenuBarSegment(providerId: u.providerId, leading: .levelDot, text: "", level: level)
            }
        case .worst:
            let pool = usages.filter(displayable)
            if let worst = pool.max(by: { $0.nearestLimitPercent < $1.nearestLimitPercent }) {
                let used = worst.nearestLimitPercent
                let shown = showUsedPercent ? used : max(0, 100 - used)
                return [MenuBarSegment(providerId: worst.providerId, leading: .providerDot,
                                       text: "\(shown)%", level: UsageLevel.level(forPercent: used))]
            }
            if usages.isEmpty { return [] }
            return [MenuBarSegment(providerId: usages[0].providerId, leading: .none, text: "—", level: .normal)]
        }
    }
}
```

- [ ] **Step 4: Napiš testy v `MenuBarStyleTests.swift`**

Create `Tests/StatusBarKitTests/MenuBarStyleTests.swift`:

```swift
import Testing
import Foundation
@testable import StatusBarKit

private func usage(_ id: ProviderID, used: Double, status: ProviderStatus = .ok) -> ProviderUsage {
    ProviderUsage(providerId: id, displayName: id == .claudeCode ? "Claude Code" : "Codex", planLabel: nil,
        windows: [UsageWindow(kind: .rolling5h, usedFraction: used, resetAt: nil)],
        status: status, lastUpdated: Date())
}

// data: Claude 42 % vyčerpáno (58 zbývá), Codex 92 % vyčerpáno (8 zbývá)
private let cc = { usage(.claudeCode, used: 0.42) }()
private let cx = { usage(.codex, used: 0.92) }()

@Test func stylAZbývající() {
    let s = MenuBarTitleBuilder.segments(for: [cc, cx], style: .dotPercent, showUsedPercent: false)
    #expect(s == [
        MenuBarSegment(providerId: .claudeCode, leading: .providerDot, text: "58%", level: .normal),
        MenuBarSegment(providerId: .codex, leading: .providerDot, text: "8%", level: .critical),
    ])
}

@Test func stylAVyčerpané() {
    let s = MenuBarTitleBuilder.segments(for: [cc, cx], style: .dotPercent, showUsedPercent: true)
    #expect(s[0] == MenuBarSegment(providerId: .claudeCode, leading: .providerDot, text: "42%", level: .normal))
    #expect(s[1] == MenuBarSegment(providerId: .codex, leading: .providerDot, text: "92%", level: .critical))
}

@Test func stylBŠtítek() {
    let s = MenuBarTitleBuilder.segments(for: [cc, cx], style: .labelPercent, showUsedPercent: false)
    #expect(s[0] == MenuBarSegment(providerId: .claudeCode, leading: .label("CC"), text: "58%", level: .normal))
    #expect(s[1] == MenuBarSegment(providerId: .codex, leading: .label("CX"), text: "8%", level: .critical))
}

@Test func stylCJenTečka() {
    let s = MenuBarTitleBuilder.segments(for: [cc, cx], style: .dotOnly, showUsedPercent: false)
    #expect(s == [
        MenuBarSegment(providerId: .claudeCode, leading: .levelDot, text: "", level: .normal),
        MenuBarSegment(providerId: .codex, leading: .levelDot, text: "", level: .critical),
    ])
}

@Test func stylDNejkritičtější() {
    // Codex je horší (8 zbývá) → jediný segment Codexu
    let s = MenuBarTitleBuilder.segments(for: [cc, cx], style: .worst, showUsedPercent: false)
    #expect(s == [MenuBarSegment(providerId: .codex, leading: .providerDot, text: "8%", level: .critical)])
}

@Test func stylDVyčerpané() {
    let s = MenuBarTitleBuilder.segments(for: [cc, cx], style: .worst, showUsedPercent: true)
    #expect(s == [MenuBarSegment(providerId: .codex, leading: .providerDot, text: "92%", level: .critical)])
}

@Test func stylDPřeskočíNedostupné() {
    let down = usage(.codex, used: 0, status: .unavailable("x"))
    // Codex nedostupný → worst je Claude (jediný zobrazitelný)
    let s = MenuBarTitleBuilder.segments(for: [cc, down], style: .worst, showUsedPercent: false)
    #expect(s == [MenuBarSegment(providerId: .claudeCode, leading: .providerDot, text: "58%", level: .normal)])
}

@Test func stylDVšeNedostupné() {
    let a = usage(.claudeCode, used: 0, status: .unavailable("x"))
    let b = usage(.codex, used: 0, status: .unavailable("y"))
    let s = MenuBarTitleBuilder.segments(for: [a, b], style: .worst, showUsedPercent: false)
    #expect(s == [MenuBarSegment(providerId: .claudeCode, leading: .none, text: "—", level: .normal)])
}

@Test func prázdnýVstup() {
    #expect(MenuBarTitleBuilder.segments(for: [], style: .worst).isEmpty)
    #expect(MenuBarTitleBuilder.segments(for: [], style: .dotPercent).isEmpty)
}

@Test func nedostupnýStylB() {
    let down = usage(.claudeCode, used: 0, status: .unavailable("x"))
    let s = MenuBarTitleBuilder.segments(for: [down], style: .labelPercent)
    #expect(s[0] == MenuBarSegment(providerId: .claudeCode, leading: .label("CC"), text: "—", level: .normal))
}

@Test func menuBarStyleRawValueAFallback() {
    #expect(MenuBarStyle(rawValue: "dotPercent") == .dotPercent)
    #expect(MenuBarStyle(rawValue: "worst") == .worst)
    #expect(MenuBarStyle(rawValue: "nesmysl") == nil)               // fallback řeší PreferencesStore
    #expect(MenuBarStyle.allCases.count == 4)
    #expect(MenuBarStyle.dotPercent.displayName == "Tečka + %")
    #expect(MenuBarStyle.worst.displayName == "Nejkritičtější")
}
```

- [ ] **Step 5: Spusť testy — všechny musí projít (vč. stávajících Formatting testů beze změny)**

Run: `swift test`
Expected: PASS, vč. `segmentyStyluA` a `segmentNedostupný` ve `FormattingTests.swift` (default `leading = .providerDot` → stará rovnost platí). Celkem o ~11 testů víc než předtím.

- [ ] **Step 6: Ověř, že `swift build` je čistý (Kit i App se stále kompilují)**

Run: `swift build`
Expected: Build complete (žádné warningy/chyby; `MenuBarController` zatím volá `segments(for:)` se starou signaturou — díky default args to kompiluje).

- [ ] **Step 7: Commit**

```bash
git add Sources/StatusBarKit/Formatting/MenuBarStyle.swift Sources/StatusBarKit/Formatting/Formatting.swift Tests/StatusBarKitTests/MenuBarStyleTests.swift
git commit -m "feat: MenuBarStyle + Leading + segments(for:style:showUsedPercent:)"
```

---

### Task 2: Kit — `PreferencesStore` (barStyle + showUsedPercent)

**Files:**
- Modify: `Sources/StatusBarKit/Preferences/PreferencesStore.swift`
- Modify (test): `Tests/StatusBarKitTests/PreferencesStoreTests.swift`

**Interfaces:**
- Consumes: `MenuBarStyle` (z Tasku 1).
- Produces:
  - `PreferenceKeys.barStyle = "barStyle"`, `PreferenceKeys.showUsedPercent = "showUsedPercent"`.
  - `PreferencesStore.barStyle: MenuBarStyle` (get s fallbackem na `.dotPercent`, set ukládá `rawValue`).
  - `PreferencesStore.showUsedPercent: Bool` (default false).

- [ ] **Step 1: Napiš failing testy v `PreferencesStoreTests.swift`**

Přidej do `Tests/StatusBarKitTests/PreferencesStoreTests.swift` (na konec souboru):

```swift
@Test func defaultStyluAVýznamu() {
    let (ud, suite) = freshDefaults()
    defer { ud.removePersistentDomain(forName: suite) }
    let store = PreferencesStore(defaults: ud)
    #expect(store.barStyle == .dotPercent)
    #expect(store.showUsedPercent == false)
}

@Test func uloženíStyluAVýznamu() {
    let (ud, suite) = freshDefaults()
    defer { ud.removePersistentDomain(forName: suite) }
    let store = PreferencesStore(defaults: ud)
    store.barStyle = .worst
    store.showUsedPercent = true
    let reread = PreferencesStore(defaults: ud)
    #expect(reread.barStyle == .worst)
    #expect(reread.showUsedPercent == true)
}

@Test func neznámýStylFallbackNaA() {
    let (ud, suite) = freshDefaults()
    defer { ud.removePersistentDomain(forName: suite) }
    ud.set("nesmysl-z-budoucnosti", forKey: PreferenceKeys.barStyle)
    let store = PreferencesStore(defaults: ud)
    #expect(store.barStyle == .dotPercent)
}
```

- [ ] **Step 2: Spusť testy — musí selhat (vlastnosti ještě neexistují)**

Run: `swift test --filter PreferencesStoreTests`
Expected: FAIL (kompilace: `value of type 'PreferencesStore' has no member 'barStyle'`).

- [ ] **Step 3: Rozšiř `PreferencesStore.swift`**

V `Sources/StatusBarKit/Preferences/PreferencesStore.swift` přidej do `enum PreferenceKeys` dva klíče:

```swift
    public static let barStyle = "barStyle"
    public static let showUsedPercent = "showUsedPercent"
```

a do `struct PreferencesStore` (za `remainingThresholdPercent`) tyto vlastnosti:

```swift
    public var barStyle: MenuBarStyle {
        get { MenuBarStyle(rawValue: defaults.string(forKey: PreferenceKeys.barStyle) ?? "") ?? .dotPercent }
        nonmutating set { defaults.set(newValue.rawValue, forKey: PreferenceKeys.barStyle) }
    }
    public var showUsedPercent: Bool {
        get { defaults.bool(forKey: PreferenceKeys.showUsedPercent) }   // default false
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.showUsedPercent) }
    }
```

- [ ] **Step 4: Spusť testy — musí projít**

Run: `swift test --filter PreferencesStoreTests`
Expected: PASS (5 testů — 2 stávající + 3 nové).

- [ ] **Step 5: Ověř celý balík**

Run: `swift test`
Expected: PASS (vše).

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusBarKit/Preferences/PreferencesStore.swift Tests/StatusBarKitTests/PreferencesStoreTests.swift
git commit -m "feat: PreferencesStore.barStyle + showUsedPercent (fallback na A)"
```

---

### Task 3: App — renderer podle `Leading`, Nastavení, wiring, verze

**Files:**
- Modify: `Sources/StatusBarApp/MenuBarController.swift` (init `prefs:`, render podle `leading`, `applyAppearance()`)
- Modify: `Sources/StatusBarApp/SettingsView.swift` (sekce „Zobrazení lišty" + `onAppearanceChanged`)
- Modify: `Sources/StatusBarApp/SettingsWindowController.swift` (předat `onAppearanceChanged`)
- Modify: `Sources/StatusBarApp/AppDelegate.swift` (předat `prefs` do `MenuBarController`, napojit `onAppearanceChanged`)
- Modify: `Resources/Info.plist` (verze 0.7)

**Interfaces:**
- Consumes: `PreferencesStore.barStyle`, `PreferencesStore.showUsedPercent`, `MenuBarTitleBuilder.segments(for:style:showUsedPercent:)`, `MenuBarSegment.Leading`, `MenuBarStyle.allCases`/`displayName`.
- Produces: `MenuBarController.init(store:prefs:onClick:onOpenSettings:)`, `MenuBarController.applyAppearance()`, `SettingsView(onRequestNotificationPermission:onAppearanceChanged:)`, `SettingsWindowController(onRequestNotificationPermission:onAppearanceChanged:)`.

> **Pozn.:** App vrstva nemá unit testy (AppKit/SwiftUI). Ověření = čistý `swift build` + manuální smoke (vizuál ověří uživatel). Stejný vzor jako v0.4/v0.6.

- [ ] **Step 1: `MenuBarController` — přidej `prefs`, render podle `leading`, `applyAppearance()`**

V `Sources/StatusBarApp/MenuBarController.swift`:

(a) Přidej uloženou vlastnost za `private let store: UsageStore`:

```swift
    private let prefs: PreferencesStore
```

(b) Změň init signaturu a tělo (přidá `prefs:` parametr; zbytek beze změny):

```swift
    init(store: UsageStore, prefs: PreferencesStore, onClick: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void = {}) {
        self.store = store
        self.prefs = prefs
        self.onRefresh = onClick
        self.onOpenSettings = onOpenSettings
        render(store.orderedUsages)
        cancellable = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.render(self.store.orderedUsages)
            }
        }
        popover.behavior = .transient
        let hosting = NSHostingController(rootView:
            PopoverView(store: store, onRefresh: onClick, onQuit: { NSApp.terminate(nil) },
                        onOpenSettings: onOpenSettings))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
    }

    /// Překreslí lištu po změně stylu/významu % v Nastavení.
    func applyAppearance() { render(store.orderedUsages) }
```

(c) Nahraď tělo `render(_:)` (smyčka přes segmenty čte styl z prefs a větví podle `leading`):

```swift
    private func render(_ usages: [ProviderUsage]) {
        let segs = MenuBarTitleBuilder.segments(for: usages,
                                                style: prefs.barStyle,
                                                showUsedPercent: prefs.showUsedPercent)
        let title = NSMutableAttributedString()
        for (i, s) in segs.enumerated() {
            if i > 0 { title.append(NSAttributedString(string: "  ")) }
            switch s.leading {
            case .providerDot:
                title.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: dotColor(s.providerId), .font: NSFont.systemFont(ofSize: 9)]))
            case .levelDot:
                title.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: levelColor(s.level), .font: NSFont.systemFont(ofSize: 9)]))
            case .label(let txt):
                title.append(NSAttributedString(string: "\(txt) ", attributes: [.foregroundColor: levelColor(s.level), .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)]))
            case .none:
                break
            }
            if !s.text.isEmpty {
                title.append(NSAttributedString(string: s.text, attributes: [.foregroundColor: levelColor(s.level), .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)]))
            }
        }
        if segs.isEmpty { title.append(NSAttributedString(string: "StatusBar")) }
        statusItem.button?.attributedTitle = title
        statusItem.button?.toolTip = usages.map { u -> String in
            switch u.status {
            case .ok: return "\(u.displayName): \(max(0, 100 - u.nearestLimitPercent)) % zbývá"
            case .degraded(let m): return "\(u.displayName): ⚠︎ \(m)"
            case .unavailable(let m): return "\(u.displayName): — \(m)"
            }
        }.joined(separator: "\n")
    }
```

- [ ] **Step 2: `SettingsView` — sekce „Zobrazení lišty" + `onAppearanceChanged`**

V `Sources/StatusBarApp/SettingsView.swift`:

(a) Přidej parametr za `onRequestNotificationPermission`:

```swift
    var onAppearanceChanged: () -> Void = {}
```

(b) Přidej `@AppStorage` vlastnosti za `threshold`:

```swift
    @AppStorage(PreferenceKeys.barStyle) private var barStyle: MenuBarStyle = .dotPercent
    @AppStorage(PreferenceKeys.showUsedPercent) private var showUsedPercent = false
```

(c) Vlož novou sekci do `body` mezi blok „Spouštět při přihlášení" a první `Divider()` (tj. před sekci Upozornění přidej sekci + Divider):

```swift
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Zobrazení lišty").font(.headline)
                HStack {
                    Text("Styl").foregroundStyle(.secondary)
                    Picker("", selection: $barStyle) {
                        ForEach(MenuBarStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }.labelsHidden().frame(width: 160)
                    Spacer()
                }
                .onChange(of: barStyle) { _, _ in onAppearanceChanged() }
                HStack {
                    Text("Číslo ukazuje").foregroundStyle(.secondary)
                    Picker("", selection: $showUsedPercent) {
                        Text("Zbývající").tag(false)
                        Text("Vyčerpané").tag(true)
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 180)
                    Spacer()
                }
                .onChange(of: showUsedPercent) { _, _ in onAppearanceChanged() }
            }
```

(d) Zvyš výšku okna (přidaná sekce se nesmí oříznout): změň `.frame(width: 360, height: 260)` na:

```swift
        .frame(width: 360, height: 360)
```

- [ ] **Step 3: `SettingsWindowController` — předat `onAppearanceChanged`**

V `Sources/StatusBarApp/SettingsWindowController.swift`:

(a) Přidej uloženou vlastnost a parametr initu:

```swift
    private let onRequestNotificationPermission: () -> Void
    private let onAppearanceChanged: () -> Void

    init(onRequestNotificationPermission: @escaping () -> Void = {},
         onAppearanceChanged: @escaping () -> Void = {}) {
        self.onRequestNotificationPermission = onRequestNotificationPermission
        self.onAppearanceChanged = onAppearanceChanged
    }
```

(b) V `show()` změň výšku okna a předej closure do `SettingsView`:

```swift
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            w.title = "StatusBar — Nastavení"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(
                rootView: SettingsView(onRequestNotificationPermission: onRequestNotificationPermission,
                                       onAppearanceChanged: onAppearanceChanged))
```

- [ ] **Step 4: `AppDelegate` — předej `prefs` a napoj `onAppearanceChanged`**

V `Sources/StatusBarApp/AppDelegate.swift`:

(a) Změň vytvoření `settings` (přidá `onAppearanceChanged`, který překreslí lištu):

```swift
        settings = SettingsWindowController(onRequestNotificationPermission: { [weak self] in
            self?.notifier.requestAuthorizationIfNeeded()
        }, onAppearanceChanged: { [weak self] in
            self?.menuBar?.applyAppearance()
        })
```

(b) Změň vytvoření `menuBar` (přidá `prefs:`):

```swift
        menuBar = MenuBarController(store: store, prefs: prefs, onClick: { [weak self] in
            Task { await self?.coordinator.refreshNow(includeToday: true) }
        }, onOpenSettings: { [weak self] in
            self?.settings.show()
        })
```

- [ ] **Step 5: Bump verze v `Info.plist`**

V `Resources/Info.plist` změň obě pole na `0.7`:

```xml
  <key>CFBundleVersion</key><string>0.7</string>
  <key>CFBundleShortVersionString</key><string>0.7</string>
```

- [ ] **Step 6: Ověř čistý build + testy**

Run: `swift build && swift test`
Expected: Build complete; všechny testy PASS.

- [ ] **Step 7: Smoke — postav .app a spusť (vizuál ověří uživatel)**

Run: `bash scripts/make-app.sh` (pokud existuje) a spusť výslednou `.app`.
Expected: lišta naběhne ve stylu A se zbývajícími % (jako dřív). V okně Nastavení je sekce „Zobrazení lišty" se 4 styly a přepínačem Zbývající/Vyčerpané; změna se okamžitě projeví v liště.
Pozn.: vizuální potvrzení je na uživateli; agent ověří jen čistý build a běh bez pádu.

- [ ] **Step 8: Commit**

```bash
git add Sources/StatusBarApp/MenuBarController.swift Sources/StatusBarApp/SettingsView.swift Sources/StatusBarApp/SettingsWindowController.swift Sources/StatusBarApp/AppDelegate.swift Resources/Info.plist
git commit -m "feat: styly lišty v Nastavení + render podle Leading + verze 0.7"
```

---

## Verifikace (po všech taskách)
- `swift build` čistý (Kit + App), `swift test` zelený (stávající + ~14 nových testů).
- Default chování (žádný uložený pref) = styl A + zbývající % = bajt-za-bajt jako v0.6.
- GAP (ověří uživatel): vizuál stylů B/C/D a okamžité překreslení po změně v Nastavení.
