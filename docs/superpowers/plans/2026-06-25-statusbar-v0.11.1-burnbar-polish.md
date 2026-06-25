# StatusBar v0.11.1 — Burn bar polish (toggle %, kratší bar, burn v popoveru)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps `- [ ]`.

**Goal:** 3 úpravy burn baru dle zpětné vazby uživatele: (1) v liště má `%` ctít přepínač Zbývající/Vyčerpané; (2) bar v liště zúžit ~o 1/3; (3) burn dvoubarevný proužek i v popoveru (per okno).

**Verze:** 0.11.1. Větev `feat/v0.11.1-burnbar-polish`. Baseline 164 testů.

## Rozhodnutí (z explicitního zadání uživatele)
- **D1 — `%` v liště ctí `showUsedPercent`** (jako ostatní styly): default `false` → ZBÝVAJÍCÍ % (100−used); `true` → vyčerpané. Bug: dnes hardcoded used%, toggle bez efektu.
- **D2 — `barW` 52 → 35** (~o 1/3 kratší).
- **D3 — popover: nahradit fuel-gauge `ProgressView` dvoubarevným burn proužkem** per okno (used plné + projekce světlejší + overLimit červená). Text „X% zbývá" + reset nad barem ZŮSTÁVÁ. Burn projekce per KONKRÉTNÍ okno (ne přes selectedWindow).

## Global Constraints
- Nulová regrese ostatních stylů a featur. `showUsedPercent` se čte z `prefs`. Build 0 warningů, plný `swift test`. NEspouštět GUI.

---

### Task 1: Kit — BurnBarBuilder.bar(forWindow:now:) (per okno) + DRY

**Files:** Modify `Sources/StatusBarKit/Formatting/BurnBar.swift`; Test `Tests/StatusBarKitTests/BurnBarWindowTests.swift`

**Interfaces:** Produces `BurnBarBuilder.bar(forWindow w: UsageWindow, now: Date) -> BurnBar` (non-optional). `bar(for:source:now:)` na něj deleguje.

- [ ] **Step 1: Test** `Tests/StatusBarKitTests/BurnBarWindowTests.swift`:
```swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func barForWindowProjekce() {
    let now = Date()
    let w = UsageWindow(kind: .rolling5h, usedFraction: 0.5, resetAt: now.addingTimeInterval(4*3600))
    let b = BurnBarBuilder.bar(forWindow: w, now: now)
    #expect(b.used == 0.5)
    #expect(b.projected == 1.0)   // proj 2.5 → clamp 1.0
    #expect(b.overLimit == true)
    #expect(b.level == .critical)
}
@Test func barForWindowBezProjekce() {
    let now = Date()
    let w = UsageWindow(kind: .weekly(scope: nil), usedFraction: 0.3, resetAt: nil)  // reset nil → bez projekce
    let b = BurnBarBuilder.bar(forWindow: w, now: now)
    #expect(b.used == 0.3)
    #expect(b.projected == 0.3)
    #expect(b.overLimit == false)
}
@Test func barForSourceDeleguje() {
    let now = Date()
    let u = ProviderUsage(providerId: .claudeCode, displayName: "C", planLabel: nil,
        windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.25, resetAt: now.addingTimeInterval(2.5*3600))],
        status: .ok, lastUpdated: now)
    let viaSource = BurnBarBuilder.bar(for: u, source: .auto, now: now)
    let viaWindow = BurnBarBuilder.bar(forWindow: u.windows[0], now: now)
    #expect(viaSource == viaWindow)   // delegace → stejný výsledek
}
```

- [ ] **Step 2:** `swift test` → FAIL.
- [ ] **Step 3: Implementace** — v `BurnBar.swift` přidat `bar(forWindow:now:)` a refaktorovat `bar(for:source:now:)`:
```swift
    public static func bar(forWindow w: UsageWindow, now: Date) -> BurnBar {
        let used = min(1.0, max(0, w.usedFraction))
        let projRaw = BurnRateCalculator.project(window: w, now: now)?.projectedFractionAtReset
        let projected = projRaw.map { min(1.0, max($0, used)) } ?? used
        let overLimit = (projRaw ?? 0) > 1.0
        let level = UsageLevel.level(forPercent: Int((max(used, projected) * 100).rounded()))
        return BurnBar(used: used, projected: projected, overLimit: overLimit, level: level)
    }

    public static func bar(for usage: ProviderUsage, source: BarWindowSource, now: Date) -> BurnBar? {
        guard let w = usage.selectedWindow(for: source) else { return nil }
        return bar(forWindow: w, now: now)
    }
```
(odstraň starou duplicitní logiku v `bar(for:source:now:)`).

- [ ] **Step 4:** `swift test` → PASS (164 + 3 = 167; existující BurnBarTests beze změny — delegace zachovává výsledek).
- [ ] **Step 5: Commit** `feat: BurnBarBuilder.bar(forWindow:now:) per okno + DRY delegace`.

---

### Task 2: App — lišta: % ctí showUsedPercent + kratší bar

**Files:** Modify `Sources/StatusBarApp/MenuBarController.swift`, `Sources/StatusBarApp/BurnBarRenderer.swift`

- [ ] **Step 1:** V `BurnBarRenderer.swift` změnit `let barW: CGFloat = 52` → `let barW: CGFloat = 35`.
- [ ] **Step 2:** V `MenuBarController.renderBurnBar`, řádek s `percent:` upravit tak, aby ctil `prefs.showUsedPercent`:
```swift
            let bar = BurnBarBuilder.bar(for: u, source: prefs.barWindowSource, now: Date())
            let pct: Int? = bar.map { b in
                let used = Int((b.used * 100).rounded())
                return prefs.showUsedPercent ? used : max(0, 100 - used)
            }
            return BurnBarRenderer.Group(dot: dotColor(u.providerId), bar: bar, percent: pct)
```
- [ ] **Step 3: Build** `swift build -c debug` → 0 warningů. `swift test` 167 PASS.
- [ ] **Step 4: Commit** `feat: lišta burnBar % ctí showUsedPercent + bar kratší (52→35)`.

**Pozn.:** Default `showUsedPercent=false` → bar nově ukazuje ZBÝVAJÍCÍ % (konzistentní s ostatními styly); přepínač Nastavení→Lišta→Číslo ukazuje teď funguje i pro burnBar.

---

### Task 3: App — popover: dvoubarevný burn proužek per okno

**Files:** Create `Sources/StatusBarApp/BurnBarView.swift`; Modify `Sources/StatusBarApp/PopoverView.swift`

- [ ] **Step 1: Vytvořit** `Sources/StatusBarApp/BurnBarView.swift`:
```swift
import SwiftUI
import StatusBarKit

/// Dvoubarevný „buffered" burn proužek (used plné + projekce světlejší + overLimit červená) pro popover.
struct BurnBarView: View {
    let bar: BurnBar
    private var hue: Color {
        switch bar.level { case .normal: return .green; case .warning: return .orange; case .critical: return .red }
    }
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.12))
                if bar.projected > bar.used {
                    Rectangle().fill((bar.overLimit ? Color.red : hue).opacity(0.32))
                        .frame(width: w * min(1.0, bar.projected))
                }
                Rectangle().fill(hue).frame(width: w * min(1.0, bar.used))
                if bar.overLimit {
                    Rectangle().fill(Color.red).frame(width: 3).offset(x: w - 3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 7)
    }
}
```

- [ ] **Step 2:** V `PopoverView.swift`, ve `windowsList`, NAHRADIT řádek s `ProgressView`:
```swift
                ProgressView(value: max(0.0, min(1.0, 1 - w.usedFraction))).tint(UsageColor.color(forFraction: w.usedFraction))
```
tímto:
```swift
                BurnBarView(bar: BurnBarBuilder.bar(forWindow: w, now: Date()))
```

- [ ] **Step 3: Build** `swift build -c debug` → 0 errors, 0 warnings. `swift test` 167 PASS.
- [ ] **Step 4: Commit** `feat: popover — dvoubarevný burn proužek per okno (nahrazuje fuel-gauge)`.

**Pozn. reviewerovi:** Burn proužek per okno používá `BurnBarBuilder.bar(forWindow:now:)` (Task 1). Text „X% zbývá" + reset nad barem zůstává. `UsageColor` import už v PopoverView je (zůstává pro jiné použití? ověř — pokud nikde jinde, ponech bez warningů).

---

### Task 4: Finalizace — verze 0.11.1 + plný test + release build

**Files:** Modify `Resources/Info.plist`

- [ ] **Step 1:** Parity (Kit+App en==cs prázdný diff).
- [ ] **Step 2:** Bump `Resources/Info.plist` → 0.11.1 (oba klíče, PlistBuddy), ověřit Print.
- [ ] **Step 3:** `swift test` → zelené (167), zaznamenat.
- [ ] **Step 4:** `swift build -c release` → 0 errors, 0 warnings.
- [ ] **Step 5: Commit** `chore: verze 0.11.1 (burn bar polish)`.

**Pozn.:** Vizuální PNG/popover smoke + lišta = orchestrátor po finálním review.

## Self-Review
- Coverage: forWindow builder (T1), lišta toggle+šířka (T2), popover bar (T3), verze (T4). ✓
- Type consistency: `bar(forWindow:)`→`BurnBarView`/menu. ✓
- Regrese: showUsedPercent default změní zobrazené číslo na zbývající (záměr); ostatní styly nedotčené. ✓
