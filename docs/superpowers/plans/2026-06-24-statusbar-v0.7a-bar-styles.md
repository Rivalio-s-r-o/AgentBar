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
- **Sdílený kontrakt prefs (F4):** UI (`@AppStorage` v `SettingsView`) a Kit (`PreferencesStore`) čtou/píšou TYTÉŽ klíče — obě strany VŽDY přes konstanty `PreferenceKeys.*` (žádné string-literály). Encoding musí sednout: `barStyle` = `rawValue` String, `showUsedPercent` = `Bool`. Obě strany běží nad `UserDefaults.standard` (`@AppStorage` default i `PreferencesStore()` v `AppDelegate` bez argumentu).
- Bundle verze → `0.7` (`Resources/Info.plist`, obě pole).
- **Testy jsou volné `@Test func` bez `@Suite`/typu (F1):** `swift test --filter <NázevSouboru>` NEMATCHNE nic → ověřuj VŽDY plným `swift test`, nikdy ne `--filter` na jméno souboru.
- TDD, časté commity, DRY, YAGNI.

## Guardrails

- **Zakázané akce:** neměnit chování při defaultních prefs (styl A + zbývající %); nesahat na `~/.claude`/`~/.codex`; `StatusBarKit` nesmí dostat `import AppKit`/`SwiftUI`/`Security`/síť; nepřejmenovávat/neměnit encoding stávajících `PreferenceKeys` (rozbilo by uložené prefs uživatele).
- **Žádná nevratná operace** — featura jen přidává kód + dvě UserDefaults klíče; rollback = `git revert`/`git checkout`.
- **Stop podmínky:** selže-li ověření kroku, postupuj dle „On failure" daného kroku; nikdy neimprovizuj náhradní API.
- **Kill criterion (F3, schváleno CP2):** když Task 1 Kit unit testy nejdou zezelenat ani po 2 pokusech implementera, NEBO `@AppStorage<MenuBarStyle>` i String-rawValue fallback (viz Task 3 Step 2) oba selžou kompilací → ZASTAV celý plán a nahlas uživateli; nepokračuj na další tasky.

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

> **Pozn. (F6):** `pool.max(by: { $0.nearestLimitPercent < $1.nearestLimitPercent })` při shodě (oba providery stejně vyčerpané) vrací **prvního** v pořadí (Swift `max(by:)` neaktualizuje výsledek na ne-rostoucí porovnání) — deterministické, Claude před Codexem. Testy používají rozdílná % (42 vs 92), takže tie-break neovlivní rovnosti.

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

Run: `swift test`
Expected: FAIL — kompilace celého test targetu selže: `value of type 'PreferencesStore' has no member 'barStyle'`.
(Pozn. F1: NEpoužívej `--filter NázevSouboru` — testy jsou volné `@Test func` bez typu, filtr by nematchnul nic a vrátil falešný PASS.)

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

Run: `swift test`
Expected: PASS — celý balík zelený, vč. 5 testů v `PreferencesStoreTests.swift` (2 stávající + 3 nové).

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

> **Pozn. (F3) — předpoklad ověřený buildem (Step 6):** `@AppStorage` s `MenuBarStyle` funguje, protože je to `RawRepresentable` s `RawValue == String` (SwiftUI má `init(wrappedValue:_:)` pro tento případ; tentýž soubor už `@AppStorage` s default hodnotami používá pro `Bool`/`Int`). **Pokud `swift build` v Step 6 selže na `@AppStorage<MenuBarStyle>`**, použij fallback: `@AppStorage(PreferenceKeys.barStyle) private var barStyleRaw: String = MenuBarStyle.dotPercent.rawValue`, v Pickeru taguj `String` (`.tag(s.rawValue)` přes `ForEach(MenuBarStyle.allCases…)`) a v `onChange` volej `onAppearanceChanged()`. `PreferencesStore.barStyle` čte stejný String klíč, takže Kit zůstává beze změny. Selže-li i fallback kompilací → kill criterion (sekce Guardrails).

(c) Vlož novou sekci do `body` **bezprostředně za blok `Toggle("Spouštět při přihlášení")` včetně jeho `.onChange(of: launchAtLogin){…}`** a **před stávající `Divider()`** (který odděluje sekci Upozornění). Vkládaný blok začíná vlastním `Divider()`, takže výsledně budou dva oddělovače: launch → `Divider` → „Zobrazení lišty" → stávající `Divider` → „Upozornění":

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

- [ ] **Step 7: Postav `.app` artefakt a předej uživateli (NEspouštět GUI)**

Run: `bash scripts/make-app.sh`
Expected: skript doběhne s exit 0 a vyrobí `.app` bundle (ověř `echo $?` == 0 a existenci výsledné `.app` cesty, kterou skript vypíše / je v repo konvenci).
**Brána (mechanická, agent):** jediný automatický gate je Step 6 (`swift build && swift test` zelené) + tento Step 7 (make-app.sh exit 0). **Agent NESMÍ spouštět výslednou `.app`** (GUI proces by visel / nelze headless ověřit) — jen ji postaví a nahlásí cestu.
**Vizuální ověření (uživatel, GAP):** uživatel spustí `.app` a potvrdí: lišta naběhne ve stylu A se zbývajícími % (jako dřív); v Nastavení je sekce „Zobrazení lišty" se 4 styly + přepínač Zbývající/Vyčerpané; změna se okamžitě projeví v liště.
On failure: selže-li `make-app.sh` (exit ≠ 0), nahlas výstup skriptu a ZASTAV — neimprovizuj ruční sestavení bundlu.

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

## Rollback & Recovery
Featura je čistě aditivní (nový kód + 2 UserDefaults klíče, žádná migrace dat). Rollback = `git revert` příslušných commitů nebo `git checkout main -- <soubory>`. Uložené prefs `barStyle`/`showUsedPercent` jsou neškodné i bez kódu (ignorované). Žádná nevratná operace.

## Risk Register
| ID | Severity | Likelihood | Risk | Mitigace (krok) | Resolution |
|----|----------|------------|------|-----------------|------------|
| F1 | MED | H | `--filter NázevSouboru` nematchne volné `@Test func` → falešný PASS | plný `swift test` (T2 S2/S4) + Global Constraint | fixed |
| F2 | MED | M | agent spustí GUI `.app` → visí/nemechanické | brána = `swift build && swift test`; S7 jen postaví+předá, NEspouští (T3 S7) | fixed |
| F3 | MED | L | `@AppStorage<MenuBarStyle>` se nezkompiluje | verify-in-build (T3 S6) + String-rawValue fallback (T3 S2b) + kill criterion | fixed (mitigated) |
| F4 | LOW | M | rozjetý encoding/klíče @AppStorage↔PreferencesStore | Global Constraint: přes `PreferenceKeys.*`, rawValue/Bool, `.standard` | fixed |
| F5 | LOW | M | vágní umístění UI sekce | přesná kotva (T3 S2c) | fixed |
| F6 | LOW | L | `max(by:)` tie-break nezmíněn | poznámka v T1 (první vyhrává) | fixed |

## Audit Trail
- **Lenses applied:** 1 red-team, 2 security (N/A — žádné secrets/síť/destruktivní operace; jen zápis vlastních UI prefs do UserDefaults), 3 assumptions, 4 dependencies, 5 alternatives, 6 cheap-executor, 7 goal-fit.
- **Alternativy (lens 5):** (a) style-logika ve `MenuBarTitleBuilder` + `Leading`, renderer mechanický *(zvoleno — plně unit-testovatelné v Kitu)*; (b) `switch MenuBarStyle` přímo v AppKit rendereru (logika by nebyla testovatelná); (c) builder vrací hotový plain string (ztráta per-segment barev). Volba (a) ze specu potvrzena.
- **Findings:** 0 CRIT, 0 HIGH, 3 MED (F1–F3), 3 LOW (F4–F6) → všech 6 fixnuto.
- **Re-audit po hardeningu (R*):** none (fallback F3 ani upřesnění nezavedly nový defekt).
- **Tabletop dry run:** PASSED — build zelený po každém tasku (default args + aditivní změny); existující `FormattingTests` projdou díky default `leading=.providerDot`; `settings`-před-`menuBar` ordering OK (closure čte `menuBar` až za běhu); identifikátory (`applyAppearance`, `onAppearanceChanged`, `segments(for:style:showUsedPercent:)`, `MenuBarSegment.Leading`) konzistentní napříč tasky.
- **Rozhodnutí uživatele (CP2):** 1A opravit vše F1–F6; 2A důvěřovat `@AppStorage<enum>` + zdokumentovat String fallback; 3A kill criterion aktivní.
- **K hlídání během exekuce:** jediný reálný neznámý je kompilace `@AppStorage<MenuBarStyle>` (T3 S6) — má fallback i kill criterion.
