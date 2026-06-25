# StatusBar v0.11.2 — Dvoutónová barva burn baru + EN pace mezera

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps `- [ ]`.

**Goal:** (1) Plná část baru („teď") barvená podle AKTUÁLNÍHO stavu, projekce („ghost") podle KAM SMĚŘUJE (oddělené barvy) — takže nízká spotřeba s rychlým tempem = zelená plná + červená projekce. (2) EN pace bez mezery („62% behind").

**Verze:** 0.11.2. Větev `feat/v0.11.2-twotone-color`. Baseline 167 testů.

## Rozhodnutí
- **D1 — split `BurnBar.level` → `usedLevel` (z `used`) + `projectedLevel` (z `projected`).** Staré `level` == `projectedLevel` (protože `max(used,projected)==projected`), takže projekce/okraj se chovají STEJNĚ; mění se JEN barva plné části (used) z `projectedLevel`→`usedLevel`.
- **D2 — EN `pace.ahead`/`pace.behind` bez mezery** (`%lld%% ahead`); cs ponechat s mezerou (správná česká typografie).

## Global Constraints
- Nulová regrese ostatních featur. Build 0 warningů, plný `swift test`. Kit parity test zelený. NEspouštět GUI.

---

### Task 1: Kit — BurnBar split levels + builder + EN pace mezera

**Files:** Modify `Sources/StatusBarKit/Formatting/BurnBar.swift`, `Sources/StatusBarKit/Resources/en.lproj/Localizable.strings`; Modify tests `Tests/StatusBarKitTests/BurnBarTests.swift`, `Tests/StatusBarKitTests/BurnBarWindowTests.swift`

- [ ] **Step 1: EN pace mezera** — v `Sources/StatusBarKit/Resources/en.lproj/Localizable.strings` změnit:
```
"pace.ahead" = "%lld%% ahead";
"pace.behind" = "%lld%% behind";
```
(byly `"%lld %% ahead"`/`"%lld %% behind"` — odstranit mezeru před `%%`). `pace.onpace` beze změny. cs NEMĚNIT.

- [ ] **Step 2: Aktualizovat existující testy** (split `level`→`projectedLevel`, přidat `usedLevel`):
  V `BurnBarTests.swift`:
  - `burnBarProjekce` (used 0.5, proj→1.0): `#expect(b.level == .critical)` → `#expect(b.projectedLevel == .critical)` a přidat `#expect(b.usedLevel == .normal)`.
  - `burnBarMirnaProjekce` (used 0.25, proj 0.5): `#expect(b.level == .normal)` → `#expect(b.projectedLevel == .normal)` a přidat `#expect(b.usedLevel == .normal)`.
  - `burnBarUsedClamp` (used→1.0): `#expect(b.level == .critical)` → `#expect(b.projectedLevel == .critical)` a přidat `#expect(b.usedLevel == .critical)`.
  V `BurnBarWindowTests.swift`:
  - `barForWindowProjekce`: `#expect(b.level == .critical)` → `#expect(b.projectedLevel == .critical)` a přidat `#expect(b.usedLevel == .normal)`.
  - Přidat NOVÝ test (oddělené barvy):
```swift
@Test func barForWindowOddeleneBarvy() {
    let now = Date()
    // Weekly: used 29 % (zelená), ale rychlé tempo → projekce přes limit (červená)
    // 7d okno, uplynulo ~27 % (122h55m zbývá z 168h), used 0.29 → proj ~108 % overLimit
    let w = UsageWindow(kind: .weekly(scope: nil), usedFraction: 0.29, resetAt: now.addingTimeInterval(122.92*3600))
    let b = BurnBarBuilder.bar(forWindow: w, now: now)
    #expect(b.usedLevel == .normal)        // teď 29 % = zelená
    #expect(b.projectedLevel == .critical) // projekce přes limit = červená
    #expect(b.overLimit == true)
}
```

- [ ] **Step 3:** `swift test` → FAIL (usedLevel/projectedLevel neexistují).

- [ ] **Step 4: Implementace** — v `BurnBar.swift` nahradit `level` dvěma poli:
```swift
public struct BurnBar: Sendable, Equatable {
    public let used: Double          // vyčerpáno teď (0..1)
    public let projected: Double     // projekce do resetu (0..1, vždy >= used)
    public let overLimit: Bool       // surová projekce > 1.0
    public let usedLevel: UsageLevel       // barva plné části (aktuální stav)
    public let projectedLevel: UsageLevel  // barva projekce (kam směřuje)
    public init(used: Double, projected: Double, overLimit: Bool, usedLevel: UsageLevel, projectedLevel: UsageLevel) {
        self.used = used; self.projected = projected; self.overLimit = overLimit
        self.usedLevel = usedLevel; self.projectedLevel = projectedLevel
    }
}
```
A v `bar(forWindow:now:)` nahradit výpočet `level` a `return`:
```swift
        let usedLevel = UsageLevel.level(forPercent: Int((used * 100).rounded()))
        let projectedLevel = UsageLevel.level(forPercent: Int((projected * 100).rounded()))
        return BurnBar(used: used, projected: projected, overLimit: overLimit,
                       usedLevel: usedLevel, projectedLevel: projectedLevel)
```

- [ ] **Step 5:** `swift test` → PASS (167 + 1 nový = 168; existující BurnBar/BurnBarWindow testy upravené zelené; `kitKlíčeEnACsShodné` zelený — jen hodnoty se změnily, klíče ne).
- [ ] **Step 6: Commit** `feat: BurnBar split usedLevel/projectedLevel + EN pace bez mezery`.

---

### Task 2: App — renderer + popover view použijí oddělené barvy

**Files:** Modify `Sources/StatusBarApp/BurnBarRenderer.swift`, `Sources/StatusBarApp/BurnBarView.swift`

- [ ] **Step 1: BurnBarRenderer** — tři řádky s `bar.level`:
  - projekce (řádek ~45): `hue(bar.level)` → `hue(bar.projectedLevel)`.
  - used (řádek ~49): `hue(bar.level)` → `hue(bar.usedLevel)`.
  - okraj (řádek ~55): `hue(bar.level)` → `hue(bar.projectedLevel)`.

- [ ] **Step 2: BurnBarView** — nahradit computed `hue` (z `bar.level`) funkcí přijímající level a použít oddělené:
```swift
    private func color(_ l: UsageLevel) -> Color {
        switch l { case .normal: return .green; case .warning: return .orange; case .critical: return .red }
    }
```
A v `body` ZStacku:
  - projekce: `(bar.overLimit ? Color.red : color(bar.projectedLevel)).opacity(0.32)`.
  - used: `color(bar.usedLevel)`.
  (overLimit čepička červená — beze změny.)
Odstranit původní `private var hue: Color`.

- [ ] **Step 3:** `swift build -c debug` → 0 errors, 0 warnings. `swift test` 168 PASS.
- [ ] **Step 4: Commit** `feat: burn bar plná část=aktuální stav, projekce=kam směřuje (oddělené barvy)`.

---

### Task 3: Finalizace — verze 0.11.2 + test + build

**Files:** Modify `Resources/Info.plist`

- [ ] **Step 1:** Parity (Kit+App en==cs prázdný diff).
- [ ] **Step 2:** Bump `Resources/Info.plist` → 0.11.2 (oba klíče, PlistBuddy), Print ověřit.
- [ ] **Step 3:** `swift test` → 168 zelené.
- [ ] **Step 4:** `swift build -c release` → 0 warningů.
- [ ] **Step 5: Commit** `chore: verze 0.11.2 (dvoutónová barva burn baru)`.

**Pozn.:** PNG smoke (zelená plná + červená projekce) dělá orchestrátor po finálním review.

## Self-Review
- Coverage: split levels + EN mezera (T1), renderer+view barvy (T2), verze (T3). ✓
- Regrese: projekce/okraj beze změny (projectedLevel==staré level); jen used fill nově usedLevel. ✓
