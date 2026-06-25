# StatusBar v0.11 — Burn bar (grafický burn-rate v liště) — Implementační plán

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Nový volitelný styl lišty `.burnBar` — dvoubarevný „buffered" proužek (teď + projekce do resetu) per provider.

**Architecture:** Čistá logika v `StatusBarKit` (výběr okna, BurnBar model — unit-testované); kreslení `NSImage` v `StatusBarApp` (`BurnBarRenderer`, kód ověřený PNG renderem). Nový case stylu = opt-in, výchozí beze změny.

**Tech Stack:** Swift 6, SwiftPM, AppKit (NSImage/NSBezierPath), Swift Testing (volné `@Test` → vždy plný `swift test`).

## Global Constraints
- **Nulová regrese:** výchozí styl `.dotPercent` i ostatní styly beze změny. `usedPercent` refaktor MUSÍ zachovat identické číslo (existující testy = pojistka). Při ne-`.burnBar` stylu `render` nastaví `button.image = nil`.
- **Lokalizace:** `bundle: Bundle? = nil` → `?? .module`. Nový klíč `style.burnBar` do en i cs. Parity test `kitKlíčeEnACsShodné` musí zůstat zelený.
- **Verze:** 0.11.0 (oba klíče Info.plist).
- **Bezpečnost:** žádná síť/FS/systémové zápisy navíc; jen kreslení do obrázku z už dostupných dat.
- **Testy:** vždy plný `swift test`. Baseline 152, build 0 warningů. NEspouštět GUI `.app`.

---

### Task 1: Kit — ProviderUsage.selectedWindow(for:) + refaktor usedPercent

**Files:**
- Modify: `Sources/StatusBarKit/Models/ProviderUsage.swift`
- Test: `Tests/StatusBarKitTests/SelectedWindowTests.swift`

**Interfaces:**
- Produces: `public func selectedWindow(for source: BarWindowSource) -> UsageWindow?`. `usedPercent(for:)` na něj deleguje (chování beze změny).

- [ ] **Step 1: Napsat test** `Tests/StatusBarKitTests/SelectedWindowTests.swift`:

```swift
import Testing
import Foundation
@testable import StatusBarKit

private func u(_ windows: [UsageWindow]) -> ProviderUsage {
    ProviderUsage(providerId: .claudeCode, displayName: "C", planLabel: nil,
                  windows: windows, status: .ok, lastUpdated: Date())
}
private func w(_ kind: WindowKind, _ used: Double) -> UsageWindow {
    UsageWindow(kind: kind, usedFraction: used, resetAt: Date().addingTimeInterval(3600))
}

@Test func selectedWindowAuto() {
    let p = u([w(.rolling5h, 0.3), w(.weekly(scope: nil), 0.7)])
    #expect(p.selectedWindow(for: .auto)?.usedFraction == 0.7)   // max
}
@Test func selectedWindowSession() {
    let p = u([w(.rolling5h, 0.3), w(.weekly(scope: nil), 0.7)])
    #expect(p.selectedWindow(for: .session)?.kind == .rolling5h)
    // fallback na max když chybí rolling5h
    let p2 = u([w(.weekly(scope: nil), 0.6), w(.weekly(scope: "Sonnet"), 0.9)])
    #expect(p2.selectedWindow(for: .session)?.usedFraction == 0.9)
}
@Test func selectedWindowWeekly() {
    let p = u([w(.rolling5h, 0.9), w(.weekly(scope: nil), 0.4), w(.weekly(scope: "Opus"), 0.8)])
    #expect(p.selectedWindow(for: .weekly)?.usedFraction == 0.4)   // preferuje weekly_all (scope nil)
    let p2 = u([w(.rolling5h, 0.9), w(.weekly(scope: "Opus"), 0.8), w(.weekly(scope: "Sonnet"), 0.5)])
    #expect(p2.selectedWindow(for: .weekly)?.usedFraction == 0.8)  // nejhorší scoped weekly
}
@Test func selectedWindowPrazdne() {
    let p = u([])
    #expect(p.selectedWindow(for: .auto) == nil)
}
@Test func usedPercentBezeZmeny() {
    // refaktor nesmí změnit číslo
    let p = u([w(.rolling5h, 0.3), w(.weekly(scope: nil), 0.72)])
    #expect(p.usedPercent(for: .auto) == 72)
    #expect(p.usedPercent(for: .session) == 30)
    #expect(p.usedPercent(for: .weekly) == 72)
    #expect(u([]).usedPercent(for: .auto) == 0)
}
```

- [ ] **Step 2: Spustit** `swift test` → FAIL (selectedWindow neexistuje).

- [ ] **Step 3: Implementace** — v `ProviderUsage` přidat (a refaktorovat `usedPercent`):

```swift
    /// Okno, které lišta zobrazuje pro daný zdroj (mirror logiky usedPercent). nil = žádné okno.
    public func selectedWindow(for source: BarWindowSource) -> UsageWindow? {
        func nearest() -> UsageWindow? { windows.max(by: { $0.usedFraction < $1.usedFraction }) }
        switch source {
        case .auto:
            return nearest()
        case .session:
            return windows.first(where: { $0.kind == .rolling5h }) ?? nearest()
        case .weekly:
            if let all = windows.first(where: { if case .weekly(let s) = $0.kind { return s == nil }; return false }) { return all }
            let weeklies = windows.filter { if case .weekly = $0.kind { return true }; return false }
            return weeklies.max(by: { $0.usedFraction < $1.usedFraction }) ?? nearest()
        }
    }
```

A NAHRADIT tělo `usedPercent(for:)` (celá metoda z řádků ~53–74) tímto:

```swift
    /// Used % okna zvoleného lištou. Chybí-li okno, 0.
    public func usedPercent(for source: BarWindowSource) -> Int {
        Int(((selectedWindow(for: source)?.usedFraction ?? 0) * 100).rounded())
    }
```

(Properties `nearestLimitFraction`/`nearestLimitPercent` PONECHAT — používá je tooltip.)

- [ ] **Step 4: Spustit** `swift test` → PASS (nové + VŠECHNY existující `usedPercent`/segments testy beze změny). Baseline 152 + 6 = 158.
- [ ] **Step 5: Commit** `feat: ProviderUsage.selectedWindow(for:) + usedPercent deleguje (DRY)`.

---

### Task 2: Kit — BurnBar model + BurnBarBuilder

**Files:**
- Create: `Sources/StatusBarKit/Formatting/BurnBar.swift`
- Test: `Tests/StatusBarKitTests/BurnBarTests.swift`

**Interfaces:**
- Consumes: `ProviderUsage.selectedWindow(for:)` (Task 1), `BurnRateCalculator.project` (v0.10), `UsageLevel`.
- Produces: `public struct BurnBar { used, projected: Double; overLimit: Bool; level: UsageLevel }`, `public enum BurnBarBuilder { static func bar(for:source:now:) -> BurnBar? }`.

- [ ] **Step 1: Napsat test** `Tests/StatusBarKitTests/BurnBarTests.swift`:

```swift
import Testing
import Foundation
@testable import StatusBarKit

private func usage(_ kind: WindowKind, used: Double, resetIn: TimeInterval, now: Date) -> ProviderUsage {
    ProviderUsage(providerId: .claudeCode, displayName: "C", planLabel: nil,
                  windows: [UsageWindow(kind: kind, usedFraction: used, resetAt: now.addingTimeInterval(resetIn))],
                  status: .ok, lastUpdated: now)
}

@Test func burnBarProjekce() {
    let now = Date()
    // 5h, uplynula 1h (20 %), used 0.5 → projected 2.5 → clamp 1.0, overLimit, red
    let p = usage(.rolling5h, used: 0.5, resetIn: 4*3600, now: now)
    let b = BurnBarBuilder.bar(for: p, source: .auto, now: now)!
    #expect(b.used == 0.5)
    #expect(b.projected == 1.0)        // clamp na 1.0
    #expect(b.overLimit == true)
    #expect(b.level == .critical)
}

@Test func burnBarMirnaProjekce() {
    let now = Date()
    // 5h, uplynulo 50 %, used 0.25 → projected 0.5, neexhausting, green
    let p = usage(.rolling5h, used: 0.25, resetIn: 2.5*3600, now: now)
    let b = BurnBarBuilder.bar(for: p, source: .auto, now: now)!
    #expect(b.used == 0.25)
    #expect(abs(b.projected - 0.5) < 0.001)
    #expect(b.overLimit == false)
    #expect(b.level == .normal)
}

@Test func burnBarBezProjekce() {
    let now = Date()
    // příliš brzy (elapsedFraction < 0.02) → projekce nil → projected == used
    let p = usage(.rolling5h, used: 0.1, resetIn: 5*3600 - 60, now: now)
    let b = BurnBarBuilder.bar(for: p, source: .auto, now: now)!
    #expect(b.projected == b.used)
    #expect(b.overLimit == false)
}

@Test func burnBarNilBezOkna() {
    let now = Date()
    let p = ProviderUsage(providerId: .codex, displayName: "X", planLabel: nil,
                          windows: [], status: .ok, lastUpdated: now)
    #expect(BurnBarBuilder.bar(for: p, source: .auto, now: now) == nil)
}

@Test func burnBarUsedClamp() {
    let now = Date()
    let p = usage(.rolling5h, used: 1.2, resetIn: 3600, now: now)   // přes 100 %
    let b = BurnBarBuilder.bar(for: p, source: .auto, now: now)!
    #expect(b.used == 1.0)             // clamp
    #expect(b.level == .critical)
}
```

- [ ] **Step 2: Spustit** `swift test` → FAIL.

- [ ] **Step 3: Implementace** `Sources/StatusBarKit/Formatting/BurnBar.swift`:

```swift
import Foundation

/// Model dvoubarevného burn proužku v liště. Frakce 0..1 (clamp pro kreslení).
public struct BurnBar: Sendable, Equatable {
    public let used: Double          // vyčerpáno teď (0..1)
    public let projected: Double     // projekce do resetu (0..1, vždy >= used)
    public let overLimit: Bool       // surová projekce > 1.0 → limit padne před resetem
    public let level: UsageLevel     // barva dle max(used, projected)
    public init(used: Double, projected: Double, overLimit: Bool, level: UsageLevel) {
        self.used = used; self.projected = projected; self.overLimit = overLimit; self.level = level
    }
}

public enum BurnBarBuilder {
    public static func bar(for usage: ProviderUsage, source: BarWindowSource, now: Date) -> BurnBar? {
        guard let w = usage.selectedWindow(for: source) else { return nil }
        let used = min(1.0, max(0, w.usedFraction))
        let projRaw = BurnRateCalculator.project(window: w, now: now)?.projectedFractionAtReset
        let projected = projRaw.map { min(1.0, max($0, used)) } ?? used
        let overLimit = (projRaw ?? 0) > 1.0
        let level = UsageLevel.level(forPercent: Int((max(used, projected) * 100).rounded()))
        return BurnBar(used: used, projected: projected, overLimit: overLimit, level: level)
    }
}
```

- [ ] **Step 4: Spustit** `swift test` → PASS (158 + 5 = 163).
- [ ] **Step 5: Commit** `feat: BurnBar model + BurnBarBuilder (Kit, teď+projekce per okno)`.

---

### Task 3: Kit — MenuBarStyle.burnBar + lokalizace

**Files:**
- Modify: `Sources/StatusBarKit/Formatting/MenuBarStyle.swift`, `Sources/StatusBarKit/Resources/en.lproj/Localizable.strings`, `cs.lproj/Localizable.strings`
- Test: `Tests/StatusBarKitTests/BurnBarStyleTests.swift`

- [ ] **Step 1: Přidat klíč** na konec Kit `en.lproj/Localizable.strings`:
```
"style.burnBar" = "Burn bar";
```
A Kit `cs.lproj/Localizable.strings`:
```
"style.burnBar" = "Burn pruh";
```

- [ ] **Step 2:** V `MenuBarStyle.swift` přidat case `burnBar` (za `worst`) a větev v `displayName`:
```swift
    case burnBar         // E — dvoubarevný proužek teď+projekce
```
```swift
        case .burnBar:      return NSLocalizedString("style.burnBar", bundle: b, comment: "")
```

- [ ] **Step 3: Napsat test** `Tests/StatusBarKitTests/BurnBarStyleTests.swift`:
```swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func burnBarStyleVAllCases() {
    #expect(MenuBarStyle.allCases.contains(.burnBar))
    #expect(MenuBarStyle(rawValue: "burnBar") == .burnBar)
}
@Test func burnBarStyleDisplayName() {
    #expect(MenuBarStyle.burnBar.displayName(bundle: L10n.bundle("en")) == "Burn bar")
    #expect(MenuBarStyle.burnBar.displayName(bundle: L10n.bundle("cs")) == "Burn pruh")
}
```

- [ ] **Step 4: Spustit** `swift test` → PASS (163 + 2 = 165; `kitKlíčeEnACsShodné` zelený). Build 0 warningů (POZOR: `switch` nad `MenuBarStyle` jinde v Kitu? `segments` ve Formatting.swift má `switch style` — přidání case si vyžádá ošetření).
- [ ] **Step 5:** Pokud `swift build` hlásí non-exhaustive switch ve `Formatting.swift` `MenuBarTitleBuilder.segments`, přidej tam `case .burnBar:` který se chová jako `.dotPercent` (textový fallback — burnBar se kreslí obrázkem v App, ale Kit `segments` musí být exhaustivní):
```swift
        case .dotPercent, .burnBar:
            return usages.map { perProvider($0, label: false, showUsedPercent: showUsedPercent, source: source) }
```
(tj. sloučit s `.dotPercent` větví). Znovu `swift test`.
- [ ] **Step 6: Commit** `feat: MenuBarStyle.burnBar case + style.burnBar lokalizace`.

---

### Task 4: App — BurnBarRenderer (NSImage, kód ověřený PNG renderem)

**Files:**
- Create: `Sources/StatusBarApp/BurnBarRenderer.swift`

**Interfaces:**
- Consumes: `BurnBar`, `UsageLevel` (Kit).
- Produces: `enum BurnBarRenderer { struct Group { let dot: NSColor; let bar: BurnBar?; let percent: Int? }; static func image(groups: [Group]) -> NSImage }`.

- [ ] **Step 1: Implementace** `Sources/StatusBarApp/BurnBarRenderer.swift` (kód níže je ověřený PNG renderem — opiš věrně):

```swift
import AppKit
import StatusBarKit

enum BurnBarRenderer {
    struct Group { let dot: NSColor; let bar: BurnBar?; let percent: Int? }

    private static func hue(_ level: UsageLevel) -> NSColor {
        switch level {
        case .normal: return .systemGreen
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    static func image(groups: [Group]) -> NSImage {
        let H: CGFloat = 18, dotR: CGFloat = 3
        let barW: CGFloat = 52, barH: CGFloat = 9, barR: CGFloat = 3
        let gap1: CGFloat = 5, gap2: CGFloat = 4, groupGap: CGFloat = 12, pad: CGFloat = 2
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

        func pctString(_ g: Group) -> String { g.percent.map { "\($0)%" } ?? "—" }
        func textWidth(_ g: Group) -> CGFloat { (pctString(g) as NSString).size(withAttributes: [.font: font]).width }
        func groupWidth(_ g: Group) -> CGFloat { dotR*2 + gap1 + barW + gap2 + textWidth(g) }
        let total = pad*2 + groups.map(groupWidth).reduce(0, +) + groupGap*CGFloat(max(0, groups.count - 1))

        let img = NSImage(size: NSSize(width: max(total, 1), height: H), flipped: false) { _ in
            var x = pad
            for (i, g) in groups.enumerated() {
                if i > 0 { x += groupGap }
                let midY = H/2
                // dot
                let dotRect = NSRect(x: x, y: midY - dotR, width: dotR*2, height: dotR*2)
                (g.bar == nil ? g.dot.withAlphaComponent(0.4) : g.dot).setFill()
                NSBezierPath(ovalIn: dotRect).fill()
                x += dotR*2 + gap1
                // bar
                let barRect = NSRect(x: x, y: midY - barH/2, width: barW, height: barH)
                let track = NSBezierPath(roundedRect: barRect, xRadius: barR, yRadius: barR)
                if let bar = g.bar {
                    NSColor.labelColor.withAlphaComponent(0.14).setFill(); track.fill()
                    NSGraphicsContext.saveGraphicsState(); track.addClip()
                    if bar.projected > bar.used {
                        let pr = NSRect(x: barRect.minX + barW*CGFloat(bar.used), y: barRect.minY,
                                        width: barW*CGFloat(bar.projected - bar.used), height: barH)
                        (bar.overLimit ? NSColor.systemRed.withAlphaComponent(0.42) : hue(bar.level).withAlphaComponent(0.38)).setFill()
                        NSBezierPath(rect: pr).fill()
                    }
                    let ur = NSRect(x: barRect.minX, y: barRect.minY, width: barW*CGFloat(min(1.0, bar.used)), height: barH)
                    hue(bar.level).setFill(); NSBezierPath(rect: ur).fill()
                    if bar.overLimit {
                        let cap = NSRect(x: barRect.maxX - 3, y: barRect.minY, width: 3, height: barH)
                        NSColor.systemRed.setFill(); NSBezierPath(rect: cap).fill()
                    }
                    NSGraphicsContext.restoreGraphicsState()
                    hue(bar.level).withAlphaComponent(0.55).setStroke()
                    let border = NSBezierPath(roundedRect: barRect.insetBy(dx: 0.3, dy: 0.3), xRadius: barR, yRadius: barR)
                    border.lineWidth = 0.6; border.stroke()
                } else {
                    NSColor.labelColor.withAlphaComponent(0.10).setFill(); track.fill()
                }
                x += barW + gap2
                // pct
                let pct = pctString(g) as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
                let sz = pct.size(withAttributes: attrs)
                pct.draw(at: NSPoint(x: x, y: midY - sz.height/2), withAttributes: attrs)
                x += sz.width
            }
            return true
        }
        img.isTemplate = false
        return img
    }
}
```

- [ ] **Step 2: Build** `swift build -c debug` → 0 errors, 0 warnings.
- [ ] **Step 3: Commit** `feat: BurnBarRenderer — kompozitní NSImage dvoubarevného proužku`.

---

### Task 5: App — MenuBarController větev pro .burnBar

**Files:**
- Modify: `Sources/StatusBarApp/MenuBarController.swift`

- [ ] **Step 1:** V `render(_ usages:)`, na ZAČÁTKU metody (před stavbou `attributedTitle`), přidat větev a vyčištění image:

```swift
        if prefs.barStyle == .burnBar { renderBurnBar(usages); return }
        statusItem.button?.image = nil   // jiný styl → zruš případný obrázek
```

- [ ] **Step 2:** Vyčlenit tooltip do helperu (DRY — používá burnBar i textová cesta). Stávající `statusItem.button?.toolTip = usages.map { … }.joined(...)` na konci `render` NAHRADIT voláním `statusItem.button?.toolTip = toolTipText(usages)` a přidat metodu:

```swift
    private func toolTipText(_ usages: [ProviderUsage]) -> String {
        usages.map { u -> String in
            switch u.status {
            case .ok: return String(format: NSLocalizedString("menubar.tooltip.ok", bundle: .module, comment: ""), u.displayName, max(0, 100 - u.nearestLimitPercent))
            case .degraded(let m): return String(format: NSLocalizedString("menubar.tooltip.degraded", bundle: .module, comment: ""), u.displayName, m)
            case .unavailable(let m): return String(format: NSLocalizedString("menubar.tooltip.unavailable", bundle: .module, comment: ""), u.displayName, m)
            }
        }.joined(separator: "\n")
    }
```

- [ ] **Step 3:** Přidat `renderBurnBar`:

```swift
    private func renderBurnBar(_ usages: [ProviderUsage]) {
        let groups: [BurnBarRenderer.Group] = usages.map { u in
            if case .unavailable = u.status {
                return BurnBarRenderer.Group(dot: dotColor(u.providerId), bar: nil, percent: nil)
            }
            let bar = BurnBarBuilder.bar(for: u, source: prefs.barWindowSource, now: Date())
            return BurnBarRenderer.Group(dot: dotColor(u.providerId), bar: bar,
                                         percent: bar.map { Int(($0.used * 100).rounded()) })
        }
        if groups.isEmpty {
            statusItem.button?.image = nil
            statusItem.button?.attributedTitle = NSAttributedString(string: NSLocalizedString("menubar.fallback", bundle: .module, comment: ""))
        } else {
            statusItem.button?.attributedTitle = NSAttributedString(string: "")
            statusItem.button?.image = BurnBarRenderer.image(groups: groups)
        }
        statusItem.button?.toolTip = toolTipText(usages)
    }
```

- [ ] **Step 4: Build** `swift build -c debug` → 0 errors, 0 warnings.
- [ ] **Step 5: Smoke** `swift test` → 165 PASS (Kit nedotčené).
- [ ] **Step 6: Commit** `feat: MenuBarController kreslí burn bar pro styl .burnBar (+ tooltip DRY)`.

**Pozn. reviewerovi:** `dotColor(_:)` už v MenuBarController existuje (NSColor provider barvy). Při `.burnBar` se `attributedTitle` nastaví na prázdný a místo něj `image`; při návratu na jiný styl `render` nastaví `image = nil` (Step 1). Ověř, že obě cesty nastavují tooltip.

---

### Task 6: Finalizace — verze 0.11.0 + plný test + PNG smoke

**Files:**
- Modify: `Resources/Info.plist`

- [ ] **Step 1: Ověřit parity** (Kit i App en==cs prázdný diff — stejné příkazy jako v0.10 Task 8).
- [ ] **Step 2: Bump verze** `Resources/Info.plist` → 0.11.0 (PlistBuddy oba klíče), ověřit Print.
- [ ] **Step 3: Plný test** `swift test` → zelené (165), zaznamenat počet.
- [ ] **Step 4: Release build** `swift build -c release` → 0 errors, 0 warnings.
- [ ] **Step 5: Commit** `chore: verze 0.11.0 (burn bar styl)`.

**Pozn.:** Finální vizuální PNG smoke (render z reálných hodnot) + spuštění lišty dělá ORCHESTRÁTOR po finálním review, ne implementer.

---

## Self-Review (orchestrátor)
- **Spec coverage:** selectedWindow+usedPercent (T1), BurnBar (T2), styl+lokalizace (T3), renderer (T4), MenuBarController (T5), verze (T6). ✓
- **Type consistency:** `selectedWindow`→`BurnBarBuilder`→`BurnBar`→`BurnBarRenderer.Group`→`MenuBarController`. ✓
- **Regrese:** usedPercent refaktor pojištěn existujícími testy; ne-burnBar cesta čistí image; segments exhaustivní switch. ✓
