# StatusBar v0.10 — Burn-rate odhad + kontrola aktualizací — Implementační plán

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Přidat burn-rate projekci limitních oken do popoveru + in-app kontrolu aktualizací přes GitHub Releases.

**Architecture:** Čistá logika v `StatusBarKit` (burn matematika, semver, update vyhodnocení — vše unit-testované), systémový přístup (síť, Bundle, UserDefaults, UI) v `StatusBarApp`. Mirror existujících patternů (`PaceCalculator`, `LiveCodexUsageSource`, `CostHistoryStore`).

**Tech Stack:** Swift 6 strict concurrency, SwiftPM, Swift Testing (`@Test`/`#expect` — volné funkce → `swift test --filter` NEmatchne, vždy plný `swift test`).

## Global Constraints
- **Bezpečnost:** update check = read-only anonymní HTTPS GET na `api.github.com` (žádný token/auth). ŽÁDNÁ auto-instalace, ŽÁDNÉ spouštění shellu/buildu, ŽÁDNÁ mutace working tree. Jediný zápis = `UserDefaults` (přepínač + timestamp). `~/.claude`/`~/.codex` a OAuth tokeny netknuté. Repo se NEzveřejňuje.
- **Lokalizace:** `bundle: Bundle? = nil` → `?? .module` (Bundle.module je internal, nejde jako default arg public fce). Pravidlo %/%%: klíče přes `String(format:)` s literálním % → `%%`; přímý `NSLocalizedString` bez formátu → text. Nové klíče VŽDY do en i cs (parity test `kitKlíčeEnACsShodné` hlídá Kit).
- **Verze:** 0.10.0 (CFBundleShortVersionString + CFBundleVersion v `Resources/Info.plist`).
- **Nulová regrese:** Pace zůstává (jen obohacen burnem); auto-check throttle 24 h + vypínatelný; default-on nemění existující chování oken/lišty.
- **Testy:** vždy plný `swift test`. Baseline 136 testů, build 0 warningů.

---

### Task 1: Kit — BurnProjection + BurnRateCalculator

**Files:**
- Create: `Sources/StatusBarKit/Providers/BurnRate.swift`
- Test: `Tests/StatusBarKitTests/BurnRateTests.swift`

**Interfaces:**
- Consumes: `UsageWindow` (kind: `WindowKind`, usedFraction: Double, resetAt: Date?), `WindowKind.rolling5h`/`.weekly(scope:)`.
- Produces: `public struct BurnProjection { public let projectedFractionAtReset: Double; public let timeToExhaustion: TimeInterval? }`, `public enum BurnRateCalculator { public static func project(window: UsageWindow, now: Date) -> BurnProjection? }`.

- [ ] **Step 1: Napsat test** `Tests/StatusBarKitTests/BurnRateTests.swift`:

```swift
import Testing
import Foundation
@testable import StatusBarKit

private func win(_ kind: WindowKind, used: Double, resetIn: TimeInterval, now: Date) -> UsageWindow {
    UsageWindow(kind: kind, usedFraction: used, resetAt: now.addingTimeInterval(resetIn))
}

@Test func burnProjectedAExhausting() {
    let now = Date()
    // 5h okno, uplynula 1h (20 %), vyčerpáno 50 % → tempo 2.5× → projected 250 %, exhausting
    let w = win(.rolling5h, used: 0.5, resetIn: 4*3600, now: now)
    let p = BurnRateCalculator.project(window: w, now: now)!
    #expect(abs(p.projectedFractionAtReset - 2.5) < 0.001)
    #expect(p.timeToExhaustion != nil)
    #expect(p.timeToExhaustion! < w.resetAt!.timeIntervalSince(now))
    #expect(abs(p.timeToExhaustion! - 3600) < 1)   // zbývá 0.5 frakce při rate 0.5/3600 → 1h
}

@Test func burnNeexhausting() {
    let now = Date()
    let w = win(.rolling5h, used: 0.25, resetIn: 2.5*3600, now: now)   // 50 % uplynulo, 25 % použito
    let p = BurnRateCalculator.project(window: w, now: now)!
    #expect(abs(p.projectedFractionAtReset - 0.5) < 0.001)
    #expect(p.timeToExhaustion == nil)
}

@Test func burnLimitJizDosazen() {
    let now = Date()
    let w = win(.rolling5h, used: 1.05, resetIn: 3600, now: now)
    let p = BurnRateCalculator.project(window: w, now: now)!
    #expect(p.timeToExhaustion == 0)
}

@Test func burnPrilisBrzyNil() {
    let now = Date()
    // elapsed 60s z 18000 = 0.0033 < 0.02
    let w = win(.rolling5h, used: 0.01, resetIn: 5*3600 - 60, now: now)
    #expect(BurnRateCalculator.project(window: w, now: now) == nil)
}

@Test func burnResetVMinulostiNil() {
    let now = Date()
    let w = win(.rolling5h, used: 0.5, resetIn: -100, now: now)
    #expect(BurnRateCalculator.project(window: w, now: now) == nil)
}

@Test func burnResetNilNil() {
    let now = Date()
    let w = UsageWindow(kind: .rolling5h, usedFraction: 0.5, resetAt: nil)
    #expect(BurnRateCalculator.project(window: w, now: now) == nil)
}

@Test func burnWeeklyDny() {
    let now = Date()
    // weekly, zbývají 4 dny (uplynuly 3 → ~43 %), vyčerpáno 80 % → exhausting, tte v dnech/hodinách
    let w = win(.weekly(scope: nil), used: 0.8, resetIn: 4*86400, now: now)
    let p = BurnRateCalculator.project(window: w, now: now)!
    #expect(p.timeToExhaustion != nil)
    #expect(p.timeToExhaustion! < w.resetAt!.timeIntervalSince(now))
}
```

- [ ] **Step 2: Spustit** `swift test` → FAIL (BurnRateCalculator neexistuje).

- [ ] **Step 3: Implementace** `Sources/StatusBarKit/Providers/BurnRate.swift`:

```swift
import Foundation

/// Projekce vyčerpání okna při zachování dosavadního tempa.
public struct BurnProjection: Sendable, Equatable {
    /// Odhad vyčerpané frakce v čase resetu (1.0 = 100 %), může být > 1.
    public let projectedFractionAtReset: Double
    /// Sekundy do dosažení limitu, je-li projektováno PŘED resetem; jinak nil. 0 = limit už dosažen.
    public let timeToExhaustion: TimeInterval?
    public init(projectedFractionAtReset: Double, timeToExhaustion: TimeInterval?) {
        self.projectedFractionAtReset = projectedFractionAtReset
        self.timeToExhaustion = timeToExhaustion
    }
}

/// Burn-rate odhad: extrapoluje dosavadní tempo čerpání okna do času resetu.
public enum BurnRateCalculator {
    public static func project(window: UsageWindow, now: Date) -> BurnProjection? {
        guard let reset = window.resetAt, reset > now else { return nil }
        let duration: TimeInterval = window.kind == .rolling5h ? 5 * 3600 : 7 * 24 * 3600
        let start = reset.addingTimeInterval(-duration)
        let elapsed = now.timeIntervalSince(start)
        let elapsedFraction = elapsed / duration
        // Příliš brzy po startu okna → tempo statisticky bezcenné (dělení skoro nulou).
        guard elapsedFraction >= 0.02 else { return nil }
        let u = max(0, window.usedFraction)
        let proj = u / elapsedFraction
        var tte: TimeInterval? = nil
        if u >= 1.0 {
            tte = 0
        } else if proj > 1.0 {
            let rate = u / elapsed
            tte = (1.0 - u) / rate
        }
        return BurnProjection(projectedFractionAtReset: proj, timeToExhaustion: tte)
    }
}
```

- [ ] **Step 4: Spustit** `swift test` → PASS (všech 7 nových + 136 stávajících).
- [ ] **Step 5: Commit** `feat: BurnRateCalculator + BurnProjection (Kit, projekce vyčerpání okna)`.

---

### Task 2: Kit — BurnRateLabel + lokalizace burn.*

**Files:**
- Create: `Sources/StatusBarKit/Formatting/BurnRateLabel.swift`
- Modify: `Sources/StatusBarKit/Resources/en.lproj/Localizable.strings`, `Sources/StatusBarKit/Resources/cs.lproj/Localizable.strings`
- Test: `Tests/StatusBarKitTests/BurnRateLabelTests.swift`

**Interfaces:**
- Consumes: `BurnProjection` (Task 1), `L10n.bundle(_:)` (existující, vrací lproj Bundle).
- Produces: `public enum BurnRateLabel { public static func text(_ p: BurnProjection, bundle: Bundle? = nil) -> String }`.

- [ ] **Step 1: Přidat klíče** na konec `Sources/StatusBarKit/Resources/en.lproj/Localizable.strings`:

```
"burn.projected" = "→ ~%lld%% by reset";
"burn.exhaust" = "limit in ~%@";
"burn.reached" = "limit reached";
```

A na konec `Sources/StatusBarKit/Resources/cs.lproj/Localizable.strings`:

```
"burn.projected" = "→ ~%lld %% do resetu";
"burn.exhaust" = "limit ~za %@";
"burn.reached" = "limit vyčerpán";
```

- [ ] **Step 2: Napsat test** `Tests/StatusBarKitTests/BurnRateLabelTests.swift`:

```swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func burnLabelProjectedEnCs() {
    let p = BurnProjection(projectedFractionAtReset: 0.85, timeToExhaustion: nil)
    #expect(BurnRateLabel.text(p, bundle: L10n.bundle("en")).contains("85"))
    #expect(BurnRateLabel.text(p, bundle: L10n.bundle("en")).contains("by reset"))
    #expect(BurnRateLabel.text(p, bundle: L10n.bundle("cs")).contains("do resetu"))
    // literální % se vykreslí jednou
    #expect(BurnRateLabel.text(p, bundle: L10n.bundle("en")).contains("%"))
    #expect(!BurnRateLabel.text(p, bundle: L10n.bundle("en")).contains("%%"))
}

@Test func burnLabelExhaustEnCs() {
    let p = BurnProjection(projectedFractionAtReset: 2.5, timeToExhaustion: 3600 + 20*60) // 1h 20m
    let en = BurnRateLabel.text(p, bundle: L10n.bundle("en"))
    let cs = BurnRateLabel.text(p, bundle: L10n.bundle("cs"))
    #expect(en.contains("1h 20m"))
    #expect(en.contains("limit in"))
    #expect(cs.contains("limit ~za"))
    #expect(cs.contains("1h 20m"))
}

@Test func burnLabelReached() {
    let p = BurnProjection(projectedFractionAtReset: 1.2, timeToExhaustion: 0)
    #expect(BurnRateLabel.text(p, bundle: L10n.bundle("en")) == "limit reached")
    #expect(BurnRateLabel.text(p, bundle: L10n.bundle("cs")) == "limit vyčerpán")
}

@Test func burnLabelDuration() {
    // dny
    let pd = BurnProjection(projectedFractionAtReset: 1.5, timeToExhaustion: 2*86400 + 5*3600)
    #expect(BurnRateLabel.text(pd, bundle: L10n.bundle("en")).contains("2d 5h"))
    // jen minuty
    let pm = BurnProjection(projectedFractionAtReset: 3.0, timeToExhaustion: 90)
    #expect(BurnRateLabel.text(pm, bundle: L10n.bundle("en")).contains("1m"))
}
```

- [ ] **Step 3: Spustit** `swift test` → FAIL (BurnRateLabel neexistuje).

- [ ] **Step 4: Implementace** `Sources/StatusBarKit/Formatting/BurnRateLabel.swift`:

```swift
import Foundation

/// Lidský popisek burn-rate projekce. Lokalizováno (en base / cs).
public enum BurnRateLabel {
    public static func text(_ p: BurnProjection, bundle: Bundle? = nil) -> String {
        let b = bundle ?? .module
        if let tte = p.timeToExhaustion {
            if tte <= 0 { return NSLocalizedString("burn.reached", bundle: b, comment: "limit reached") }
            return String(format: NSLocalizedString("burn.exhaust", bundle: b, comment: "limit in ~X"),
                          durationString(tte))
        }
        let pct = Int((p.projectedFractionAtReset * 100).rounded())
        return String(format: NSLocalizedString("burn.projected", bundle: b, comment: "→ ~X%% by reset"), pct)
    }

    /// Numerický (nelokalizovaný) kompaktní formát doby: Xd Yh / Xh Ym / Ym.
    private static func durationString(_ s: TimeInterval) -> String {
        let total = Int(s)
        let d = total / 86400, h = (total % 86400) / 3600, m = (total % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
```

- [ ] **Step 5: Spustit** `swift test` → PASS (nové + `kitKlíčeEnACsShodné` stále zelený, protože burn.* je v en i cs).
- [ ] **Step 6: Commit** `feat: BurnRateLabel + burn.* lokalizace (en/cs)`.

---

### Task 3: App — popover sloučí Pace + Burn do jednoho řádku

**Files:**
- Modify: `Sources/StatusBarApp/PopoverView.swift` (blok Pace ve `windowsList`, aktuálně řádky ~129–131)

**Interfaces:**
- Consumes: `PaceCalculator.pace(window:now:)`, `PaceLabel.text(deltaPercent:)`, `BurnRateCalculator.project(window:now:)` (Task 1), `BurnRateLabel.text(_:)` (Task 2), klíč `popover.pace` (= „Tempo: %@").

- [ ] **Step 1:** V `PopoverView.swift`, ve `windowsList`, NAHRADIT stávající Pace blok:

```swift
                if let d = PaceCalculator.pace(window: w, now: Date()) {
                    Text(String(format: NSLocalizedString("popover.pace", bundle: .module, comment: ""), PaceLabel.text(deltaPercent: d))).font(.caption2).foregroundStyle(.tertiary)
                }
```

tímto (sloučení Pace + Burn; oranžová při projekci vyčerpání před resetem):

```swift
                let paceText = PaceCalculator.pace(window: w, now: Date()).map { PaceLabel.text(deltaPercent: $0) }
                let burn = BurnRateCalculator.project(window: w, now: Date())
                let burnText = burn.map { BurnRateLabel.text($0) }
                let exhausting = burn?.timeToExhaustion != nil
                let clauses = [paceText, burnText].compactMap { $0 }
                if !clauses.isEmpty {
                    Text(String(format: NSLocalizedString("popover.pace", bundle: .module, comment: ""), clauses.joined(separator: " · ")))
                        .font(.caption2)
                        .foregroundStyle(exhausting ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                }
```

- [ ] **Step 2: Build** `swift build -c debug` → 0 errors, 0 warnings.
- [ ] **Step 3: Smoke** `swift test` → 136 + Task1/2 testy stále PASS (žádný App test, ale balíček musí kompilovat).
- [ ] **Step 4: Commit** `feat: popover sloučí Pace + burn-rate do jednoho řádku (oranžová při vyčerpání)`.

**Pozn. reviewerovi:** `AnyShapeStyle` je nutný, aby ternární operátor měl jednotný typ (`.orange` vs `.tertiary` jsou různé ShapeStyle typy). Sjednocení do jednoho `Text` přes `popover.pace` zachovává „Tempo: …" prefix.

---

### Task 4: Kit — SemanticVersion + UpdateStatus + UpdateChecker

**Files:**
- Create: `Sources/StatusBarKit/Providers/UpdateCheck.swift`
- Test: `Tests/StatusBarKitTests/UpdateCheckTests.swift`

**Interfaces:**
- Produces:
  - `public struct SemanticVersion: Comparable, Equatable, Sendable { public let major, minor, patch: Int; public static func parse(_ s: String) -> SemanticVersion? ; public var description: String }`
  - `public enum UpdateStatus: Sendable, Equatable { case upToDate(SemanticVersion); case updateAvailable(version: SemanticVersion, url: String); case unknown }`
  - `public enum UpdateChecker { public static func evaluate(current: SemanticVersion, latestTag: String?, latestURL: String?) -> UpdateStatus }`

- [ ] **Step 1: Napsat test** `Tests/StatusBarKitTests/UpdateCheckTests.swift`:

```swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func semverParse() {
    #expect(SemanticVersion.parse("0.10.0") == SemanticVersion(major: 0, minor: 10, patch: 0))
    #expect(SemanticVersion.parse("v0.10.0") == SemanticVersion.parse("0.10.0"))
    #expect(SemanticVersion.parse("0.10") == SemanticVersion.parse("0.10.0"))
    #expect(SemanticVersion.parse("0.10.1-beta") == SemanticVersion.parse("0.10.1"))
    #expect(SemanticVersion.parse("abc") == nil)
    #expect(SemanticVersion.parse("") == nil)
    #expect(SemanticVersion.parse("1.2.3.4") == nil)
}

@Test func semverCompareNumericky() {
    // KRITICKÉ: 0.10 > 0.9 numericky, NE string compare
    #expect(SemanticVersion.parse("0.10.0")! > SemanticVersion.parse("0.9.1")!)
    #expect(SemanticVersion.parse("0.9.9")! < SemanticVersion.parse("0.10.0")!)
    #expect(SemanticVersion.parse("1.0.0")! > SemanticVersion.parse("0.99.99")!)
    #expect(SemanticVersion.parse("0.10.0")! == SemanticVersion.parse("0.10.0")!)
}

@Test func updateCheckerVyhodnoceni() {
    let cur = SemanticVersion(major: 0, minor: 10, patch: 0)
    // novější dostupná
    if case .updateAvailable(let v, let url) = UpdateChecker.evaluate(current: cur, latestTag: "v0.11.0", latestURL: "https://x/y") {
        #expect(v == SemanticVersion(major: 0, minor: 11, patch: 0))
        #expect(url == "https://x/y")
    } else { Issue.record("čekáno updateAvailable") }
    // stejná → upToDate
    if case .upToDate = UpdateChecker.evaluate(current: cur, latestTag: "0.10.0", latestURL: "u") {} else { Issue.record("čekáno upToDate") }
    // starší → upToDate
    if case .upToDate = UpdateChecker.evaluate(current: cur, latestTag: "0.9.9", latestURL: "u") {} else { Issue.record("čekáno upToDate (starší remote)") }
    // nil tag → unknown
    if case .unknown = UpdateChecker.evaluate(current: cur, latestTag: nil, latestURL: nil) {} else { Issue.record("čekáno unknown") }
    // neparsovatelný tag → unknown
    if case .unknown = UpdateChecker.evaluate(current: cur, latestTag: "garbage", latestURL: "u") {} else { Issue.record("čekáno unknown (garbage)") }
}
```

- [ ] **Step 2: Spustit** `swift test` → FAIL.

- [ ] **Step 3: Implementace** `Sources/StatusBarKit/Providers/UpdateCheck.swift`:

```swift
import Foundation

/// Sémantická verze major.minor.patch. Tolerantní parse, NUMERICKÉ porovnání (0.10 > 0.9).
public struct SemanticVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let major: Int, minor: Int, patch: Int
    public init(major: Int, minor: Int, patch: Int) { self.major = major; self.minor = minor; self.patch = patch }

    public static func parse(_ s: String) -> SemanticVersion? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let f = t.first, f == "v" || f == "V" { t.removeFirst() }
        // odřízni prerelease/build metadata (1.2.3-beta / 1.2.3+build)
        t = t.components(separatedBy: CharacterSet(charactersIn: "-+")).first ?? t
        let parts = t.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        var nums = [0, 0, 0]
        for (i, p) in parts.enumerated() {
            guard let n = Int(p), n >= 0 else { return nil }
            nums[i] = n
        }
        return SemanticVersion(major: nums[0], minor: nums[1], patch: nums[2])
    }

    public static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        if a.major != b.major { return a.major < b.major }
        if a.minor != b.minor { return a.minor < b.minor }
        return a.patch < b.patch
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}

public enum UpdateStatus: Sendable, Equatable {
    case upToDate(SemanticVersion)
    case updateAvailable(version: SemanticVersion, url: String)
    case unknown
}

/// Vyhodnocení aktualizace z (current, latestTag, latestURL). Čisté — síť je injektovaná zvenčí.
public enum UpdateChecker {
    public static func evaluate(current: SemanticVersion, latestTag: String?, latestURL: String?) -> UpdateStatus {
        guard let tag = latestTag, let latest = SemanticVersion.parse(tag) else { return .unknown }
        if latest > current {
            return .updateAvailable(version: latest, url: latestURL ?? "https://github.com/Rivalio-s-r-o/StatusBar/releases")
        }
        return .upToDate(current)
    }
}
```

- [ ] **Step 4: Spustit** `swift test` → PASS.
- [ ] **Step 5: Commit** `feat: SemanticVersion + UpdateChecker (Kit, numerické semver porovnání)`.

---

### Task 5: Kit — PreferencesStore: autoUpdateCheck + lastUpdateCheckAt

**Files:**
- Modify: `Sources/StatusBarKit/Preferences/PreferencesStore.swift`
- Test: `Tests/StatusBarKitTests/PreferencesUpdateTests.swift`

**Interfaces:**
- Produces: `PreferenceKeys.autoUpdateCheck`, `PreferenceKeys.lastUpdateCheckAt`; `PreferencesStore.autoUpdateCheck: Bool` (default **true**), `PreferencesStore.lastUpdateCheckAt: Double` (epoch, default 0).

- [ ] **Step 1: Napsat test** `Tests/StatusBarKitTests/PreferencesUpdateTests.swift`:

```swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func autoUpdateDefaultTrueAPersistence() {
    let suite = "test.update.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: suite)!
    defer { d.removePersistentDomain(forName: suite) }
    let prefs = PreferencesStore(defaults: d)
    #expect(prefs.autoUpdateCheck == true)        // default ZAPNUTO
    prefs.autoUpdateCheck = false
    #expect(prefs.autoUpdateCheck == false)
    #expect(prefs.lastUpdateCheckAt == 0)          // default 0
    prefs.lastUpdateCheckAt = 12345
    #expect(prefs.lastUpdateCheckAt == 12345)
}
```

- [ ] **Step 2: Spustit** `swift test` → FAIL.

- [ ] **Step 3: Implementace** — v `PreferenceKeys` přidat za `barWindowSource`:

```swift
    public static let autoUpdateCheck = "autoUpdateCheck"
    public static let lastUpdateCheckAt = "lastUpdateCheckAt"
```

A v `PreferencesStore` přidat za `barWindowSource` property:

```swift
    public var autoUpdateCheck: Bool {
        get {
            if defaults.object(forKey: PreferenceKeys.autoUpdateCheck) == nil { return true }   // default ZAPNUTO
            return defaults.bool(forKey: PreferenceKeys.autoUpdateCheck)
        }
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.autoUpdateCheck) }
    }
    public var lastUpdateCheckAt: Double {
        get { defaults.double(forKey: PreferenceKeys.lastUpdateCheckAt) }   // default 0
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.lastUpdateCheckAt) }
    }
```

- [ ] **Step 4: Spustit** `swift test` → PASS.
- [ ] **Step 5: Commit** `feat: PreferencesStore autoUpdateCheck (default on) + lastUpdateCheckAt`.

**Pozn.:** `object(forKey:) == nil` test je nutný, protože `bool(forKey:)` vrací false i pro neuloženo — potřebujeme rozlišit „neuloženo → true" od „uloženo false".

---

### Task 6: App — AppVersion + GitHubReleaseChecker + UpdateCoordinator

**Files:**
- Create: `Sources/StatusBarApp/UpdateCoordinator.swift` (obsahuje `AppVersion`, `GitHubReleaseChecker`, `UpdateCoordinator`)

**Interfaces:**
- Consumes: `SemanticVersion`, `UpdateStatus`, `UpdateChecker` (Task 4), `PreferencesStore.autoUpdateCheck`/`lastUpdateCheckAt` (Task 5).
- Produces:
  - `enum AppVersion { static func current() -> SemanticVersion? }`
  - `struct GitHubReleaseChecker { func fetchLatest() async -> (tag: String, url: String)? }`
  - `@MainActor final class UpdateCoordinator: ObservableObject { @Published private(set) var status: UpdateStatus; @Published private(set) var isChecking: Bool; func checkNow() async; func checkIfDue() async }`

- [ ] **Step 1: Implementace** `Sources/StatusBarApp/UpdateCoordinator.swift`:

```swift
import Foundation
import StatusBarKit

enum AppVersion {
    static func current() -> SemanticVersion? {
        guard let s = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return nil }
        return SemanticVersion.parse(s)
    }
}

/// Anonymní read-only GET na veřejné GitHub Releases API. Žádný token, žádná auth.
/// Privátní repo / chyba sítě → nil (graceful). `releases/latest` vynechává drafty i prereleases.
struct GitHubReleaseChecker {
    let owner = "Rivalio-s-r-o"
    let repo = "StatusBar"
    func fetchLatest() async -> (tag: String, url: String)? {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("StatusBar-app", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        guard let pair = try? await URLSession.shared.data(for: req),
              (pair.1 as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: pair.0) as? [String: Any],
              let tag = obj["tag_name"] as? String else { return nil }
        let html = (obj["html_url"] as? String) ?? "https://github.com/\(owner)/\(repo)/releases"
        return (tag, html)
    }
}

@MainActor
final class UpdateCoordinator: ObservableObject {
    @Published private(set) var status: UpdateStatus = .unknown
    @Published private(set) var isChecking: Bool = false
    private let prefs: PreferencesStore
    private let checker = GitHubReleaseChecker()
    private static let interval: TimeInterval = 24 * 3600

    init(prefs: PreferencesStore) { self.prefs = prefs }

    func checkNow() async {
        guard let cur = AppVersion.current() else { return }
        guard !isChecking else { return }
        isChecking = true
        let latest = await checker.fetchLatest()
        status = UpdateChecker.evaluate(current: cur, latestTag: latest?.tag, latestURL: latest?.url)
        prefs.lastUpdateCheckAt = Date().timeIntervalSince1970
        isChecking = false
    }

    func checkIfDue() async {
        guard prefs.autoUpdateCheck else { return }
        let since = Date().timeIntervalSince1970 - prefs.lastUpdateCheckAt
        if since >= Self.interval { await checkNow() }
    }
}
```

- [ ] **Step 2: Build** `swift build -c debug` → 0 errors, 0 warnings (POZOR Swift 6: `@MainActor` třída + `URLSession` await; `GitHubReleaseChecker` je `Sendable` struct bez stavu — OK).
- [ ] **Step 3: Commit** `feat: AppVersion + GitHubReleaseChecker + UpdateCoordinator (anonymní, notify-only)`.

**Pozn. reviewerovi:** `isChecking` guard zabraňuje souběžnému dvojímu checku. `status`/`prefs` mutace běží na `@MainActor` (koordinátor je MainActor). `fetchLatest` je `nonisolated` implicitně (struct metoda volaná s await z MainActoru — hop na background URLSession je interní). Žádný token, žádný citlivý log.

---

### Task 7: App — popover banner + Nastavení sekce Aktualizace + wiring + lokalizace update.*

**Files:**
- Modify: `Sources/StatusBarApp/PopoverView.swift` (banner + nový param), `Sources/StatusBarApp/SettingsView.swift` (sekce Aktualizace), `Sources/StatusBarApp/AppDelegate.swift` (postavit coordinator + checkIfDue), `Sources/StatusBarApp/MenuBarController.swift` (předat coordinator do popoveru — POKUD popover staví MenuBarController), `Sources/StatusBarApp/SettingsWindowController.swift` (předat coordinator do SettingsView)
- Modify: `Sources/StatusBarApp/Resources/en.lproj/Localizable.strings`, `Sources/StatusBarApp/Resources/cs.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `UpdateCoordinator` (Task 6), `UpdateStatus`.

- [ ] **Step 1: Přidat klíče** na konec `Sources/StatusBarApp/Resources/en.lproj/Localizable.strings`:

```
"popover.update" = "New version %@ →";
"settings.updates" = "Updates";
"settings.autoUpdate" = "Check for updates automatically";
"settings.checkNow" = "Check now";
"settings.update.checking" = "Checking…";
"settings.update.upToDate" = "Latest version (%@)";
"settings.update.available" = "New version %@ available";
"settings.update.unknown" = "Couldn't check";
```

A na konec `Sources/StatusBarApp/Resources/cs.lproj/Localizable.strings`:

```
"popover.update" = "Nová verze %@ →";
"settings.updates" = "Aktualizace";
"settings.autoUpdate" = "Kontrolovat aktualizace automaticky";
"settings.checkNow" = "Zkontrolovat nyní";
"settings.update.checking" = "Kontroluji…";
"settings.update.upToDate" = "Nejnovější verze (%@)";
"settings.update.available" = "Nová verze %@ je k dispozici";
"settings.update.unknown" = "Nelze ověřit";
```

- [ ] **Step 2: PopoverView** — přidat `@ObservedObject var updates: UpdateCoordinator` jako parametr a banner pod hlavní Divider (řádek ~26). Banner se ukáže JEN při `.updateAvailable`:

```swift
            if case .updateAvailable(let v, let url) = updates.status {
                Button {
                    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
                        Text(String(format: NSLocalizedString("popover.update", bundle: .module, comment: ""), v.description))
                            .font(.caption).fontWeight(.medium)
                        Spacer()
                    }
                }.buttonStyle(.borderless).padding(.horizontal, 14).padding(.vertical, 6)
                Divider()
            }
```

Umístit hned ZA `Divider()` na řádku 26 (po hlavičce), PŘED `if store.orderedUsages.isEmpty`.

- [ ] **Step 3: SettingsView** — přidat sekci „Aktualizace" za sekci Upozornění (před `Spacer()`/verzi). Přidat parametr `@ObservedObject var updates: UpdateCoordinator` a `onCheckNow: () -> Void`:

```swift
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "settings.updates", bundle: .module)).font(.headline)
                Toggle(String(localized: "settings.autoUpdate", bundle: .module), isOn: $autoUpdate)
                HStack {
                    Button(String(localized: "settings.checkNow", bundle: .module)) { onCheckNow() }
                        .disabled(updates.isChecking)
                    Text(updateStatusText).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
```

s `@AppStorage(PreferenceKeys.autoUpdateCheck) private var autoUpdate = true` a computed:

```swift
    private var updateStatusText: String {
        if updates.isChecking { return String(localized: "settings.update.checking", bundle: .module) }
        switch updates.status {
        case .upToDate(let v): return String(format: NSLocalizedString("settings.update.upToDate", bundle: .module, comment: ""), v.description)
        case .updateAvailable(let v, _): return String(format: NSLocalizedString("settings.update.available", bundle: .module, comment: ""), v.description)
        case .unknown: return String(localized: "settings.update.unknown", bundle: .module)
        }
    }
```

- [ ] **Step 4: Wiring (přesné konstruktory ověřené orchestrátorem):**

  **(a) `MenuBarController`** (staví `PopoverView` ve svém `init`, řádky 16–32):
  - Přidat parametr `updates: UpdateCoordinator` do `init(store:costHistory:prefs:onClick:onOpenSettings:)` (např. za `prefs`). Uložit `self.updates = updates` (přidat `private let updates: UpdateCoordinator`).
  - V konstrukci `PopoverView(...)` (řádek 31) přidat argument `updates: updates`.

  **(b) `PopoverView`** — přidat uloženou property `@ObservedObject var updates: UpdateCoordinator` (banner z Step 2 ji čte). Default NEdávat (povinný param).

  **(c) `SettingsWindowController`** (staví `SettingsView` v `show()`, řádky 16–35):
  - Přidat do `init` parametry `updates: UpdateCoordinator` a `onCheckNow: @escaping () -> Void = {}`; uložit do `private let`.
  - V `SettingsView(...)` (řádek 25) přidat `updates: updates, onCheckNow: onCheckNow`.

  **(d) `SettingsView`** — přidat `@ObservedObject var updates: UpdateCoordinator` (povinný) a `var onCheckNow: () -> Void = {}` (k existujícím `onRequestNotificationPermission`/`onAppearanceChanged`).

  **(e) `AppDelegate.applicationDidFinishLaunching`:**
  - Přidat `private var updates: UpdateCoordinator!` (k ostatním propertám).
  - Hned na začátku `applicationDidFinishLaunching` (prefs už existuje jako stored property): `updates = UpdateCoordinator(prefs: prefs)`.
  - `settings = SettingsWindowController(onRequestNotificationPermission: …, onAppearanceChanged: …, updates: updates, onCheckNow: { [weak self] in Task { await self?.updates.checkNow() } })`.
  - `menuBar = MenuBarController(store: store, costHistory: costHistory, prefs: prefs, updates: updates, onClick: { … }, onOpenSettings: …)`.
  - V `onClick` closure (popover-open, za stávající `costHistory.refreshIfStale()`): `Task { await self.updates.checkIfDue() }`.
  - Na startu, za `costHistory.refreshIfStale()` (řádek 62): `Task { await updates.checkIfDue() }`.

  Threading: vše je `@MainActor` (AppDelegate, MenuBarController, SettingsWindowController, UpdateCoordinator) → žádný hop potřeba; `checkNow`/`checkIfDue` jsou `async` na MainActoru, `Task { await … }` je korektní.

- [ ] **Step 5: Build** `swift build -c debug` → 0 errors, 0 warnings.
- [ ] **Step 6: Smoke** `swift test` → vše PASS (Kit testy nedotčené).
- [ ] **Step 7: Commit** `feat: update UI — popover banner + Nastavení sekce Aktualizace + wiring + lokalizace`.

---

### Task 8: Finalizace — App parita lokalizace + verze 0.10.0 + RELEASING.md + plný test

**Files:**
- Modify: `Resources/Info.plist`
- Create: `RELEASING.md`

- [ ] **Step 1: Ověřit App lokalizační paritu** — en a cs `Localizable.strings` (App) musí mít IDENTICKÉ sady klíčů. Diff:

```bash
diff <(grep -oE '^"[^"]+"' Sources/StatusBarApp/Resources/en.lproj/Localizable.strings | sort) \
     <(grep -oE '^"[^"]+"' Sources/StatusBarApp/Resources/cs.lproj/Localizable.strings | sort)
```
Očekávané: prázdný výstup (žádný rozdíl). Stejně pro Kit en/cs.

- [ ] **Step 2: Bump verze** v `Resources/Info.plist` — `CFBundleShortVersionString` a `CFBundleVersion` na `0.10.0`:

```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.10.0" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 0.10.0" Resources/Info.plist
```

- [ ] **Step 3: Vytvořit `RELEASING.md`** (kořen repa):

```markdown
# Vydávání nové verze StatusBar

In-app kontrola aktualizací (Nastavení → Aktualizace) porovnává verzi běžící app
s nejnovějším GitHub Release. Aby se „Nová verze dostupná" zobrazila:

1. Bump verze v `Resources/Info.plist` (`CFBundleShortVersionString` + `CFBundleVersion`).
2. Commit, tag `vX.Y.Z`, push tagu:
   ```
   git tag v0.10.0 && git push origin v0.10.0
   ```
3. Vytvořit GitHub Release z tagu (volitelně přiložit zazipovanou `.app`):
   ```
   gh release create v0.10.0 --title "v0.10.0" --notes "…"
   ```
4. **Repo musí být veřejné.** Anonymní `api.github.com/repos/Rivalio-s-r-o/StatusBar/releases/latest`
   u privátního repa vrací 404 → in-app check tiše hlásí „Nelze ověřit / aktuální".
   Dokud je repo privátní, je updater připravený, ale „neviditelný".

Updater je **notify-only**: otevře release stránku v prohlížeči. Neinstaluje automaticky
(app je ad-hoc podepsaná). Uživatel stáhne/přebuilduje ručně.
```

- [ ] **Step 4: Plný test** `swift test` → vše zelené (136 baseline + ~20 nových). Zaznamenat počet.
- [ ] **Step 5: Build** `swift build -c release` → 0 errors, 0 warnings.
- [ ] **Step 6: Commit** `chore: verze 0.10.0 + RELEASING.md + App lokalizační parita`.

---

## Self-Review (orchestrátor po napsání plánu)
- **Spec coverage:** burn (T1–T3), update logika (T4), prefs (T5), update app (T6–T7), verze/doc/parita (T8). ✓
- **Type consistency:** `BurnProjection`/`BurnRateCalculator` (T1) → `BurnRateLabel` (T2) → PopoverView (T3); `SemanticVersion`/`UpdateStatus`/`UpdateChecker` (T4) → `UpdateCoordinator` (T6) → UI (T7). ✓
- **Placeholdery:** žádné — všechen kód doslovně. ✓
- **Bezpečnost:** read-only GET, žádná auto-instalace, jen UserDefaults zápis. ✓
```
