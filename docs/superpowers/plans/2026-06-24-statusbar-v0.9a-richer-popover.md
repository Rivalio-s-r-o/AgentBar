# StatusBar v0.9a — Bohatší popover (Pace + Updated X ago + odkazy) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Popover ukazuje čerstvost dat („Aktualizováno před X"), tempo čerpání limitů (Pace) a rychlé odkazy na status/usage stránky.

**Architecture:** Výpočty (relativní čas, pace) jsou pure Kit (testovatelné). `fetchedAt` teče přes `ClaudeLiveUsage`/nový `CodexLiveUsage` do `ProviderUsage.lastUpdated` (aby čerstvost nelhala po throttle z v0.8b). UI + odkazy v `PopoverView` (App).

**Tech Stack:** Swift 6, SwiftPM (`StatusBarKit` + `StatusBarApp`), SwiftUI/AppKit, Swift Testing.

## Global Constraints

- Swift 6 strict concurrency. `StatusBarKit` pure (Foundation OK; `Date()` se v Kitu už používá — collectory).
- **`fetchedAt`** = čas posledního ÚSPĚŠNÉHO fetche; collector ho na živé cestě dá do `lastUpdated` (místo `now`). `ClaudeLiveUsage.init` má `fetchedAt: Date = Date()` default (staré konstrukce kompilují). `CodexUsageSource.fetchFresh()` vrací nově `CodexLiveUsage?` (hard změna → live source+collector+test ve stejném tasku).
- Pace: `kind == .rolling5h ? 5h : 7d`; `delta = (usedFraction − elapsedFraction)×100` (Int); nil když `resetAt` nil nebo `≤ now`.
- Texty česky natvrdo (lokalizace až v0.9c).
- **Testy jsou volné `@Test func`:** ověřuj VŽDY plným `swift test`, NIKDY `--filter <jménoSouboru>`.
- **App smoke:** brána = `swift build && swift test` + `make-app.sh` exit 0; agent NESPOUŠTÍ GUI `.app`.
- České názvy testů s diakritikou. Bundle verze → `0.8.1`. TDD, časté commity, DRY, YAGNI.

## Guardrails
- Zakázané: měnit `CodexSnapshot` (parser typ); rozbít fallback na file cache; spouštět GUI `.app`.
- Rollback: aditivní; `git revert`/`git checkout`.
- Stop: selže-li krok, dle „On failure"; kill: Kit testy (T1) nezelené po 2 pokusech → stop.

---

### Task 1: Kit — `RelativeTimeFormatter` + `PaceCalculator` + `PaceLabel`

**Files:**
- Create: `Sources/StatusBarKit/Formatting/RelativeTimeFormatter.swift`
- Create: `Sources/StatusBarKit/Providers/Pace.swift`
- Create (test): `Tests/StatusBarKitTests/RelativeTimeFormatterTests.swift`
- Create (test): `Tests/StatusBarKitTests/PaceTests.swift`

**Interfaces:**
- Consumes: `UsageWindow` (`kind: WindowKind`, `usedFraction: Double`, `resetAt: Date?`), `WindowKind.rolling5h`.
- Produces: `RelativeTimeFormatter.string(from:now:) -> String`, `PaceCalculator.pace(window:now:) -> Int?`, `PaceLabel.text(deltaPercent:) -> String`.

- [ ] **Step 1: Napiš testy**

Create `Tests/StatusBarKitTests/RelativeTimeFormatterTests.swift`:

```swift
import Testing
import Foundation
@testable import StatusBarKit

private let now = Date(timeIntervalSince1970: 1_000_000)

@Test func relČasPrávěTeď() {
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-30), now: now) == "právě teď")
    #expect(RelativeTimeFormatter.string(from: now, now: now) == "právě teď")
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(60), now: now) == "právě teď")  // budoucnost
}
@Test func relČasMinuty() {
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-5*60), now: now) == "před 5 min")
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-59*60), now: now) == "před 59 min")
}
@Test func relČasHodiny() {
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-2*3600), now: now) == "před 2 h")
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-23*3600), now: now) == "před 23 h")
}
@Test func relČasDny() {
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-3*86400), now: now) == "před 3 d")
}
```

Create `Tests/StatusBarKitTests/PaceTests.swift`:

```swift
import Testing
import Foundation
@testable import StatusBarKit

private let now = Date(timeIntervalSince1970: 1_000_000)

@Test func paceTýdenPozadu() {
    // reset za 3.5 dne → start před 3.5 dne → uplynulo 50 %; vyčerpáno 30 % → -20
    let w = UsageWindow(kind: .weekly(scope: nil), usedFraction: 0.30, resetAt: now.addingTimeInterval(3.5*86400))
    #expect(PaceCalculator.pace(window: w, now: now) == -20)
}
@Test func paceTýdenNapřed() {
    let w = UsageWindow(kind: .weekly(scope: nil), usedFraction: 0.70, resetAt: now.addingTimeInterval(3.5*86400))
    #expect(PaceCalculator.pace(window: w, now: now) == 20)
}
@Test func pace5hOkno() {
    // reset za 2.5h → uplynulo 50 %; vyčerpáno 50 % → 0
    let w = UsageWindow(kind: .rolling5h, usedFraction: 0.50, resetAt: now.addingTimeInterval(2.5*3600))
    #expect(PaceCalculator.pace(window: w, now: now) == 0)
}
@Test func paceNilBezResetu() {
    #expect(PaceCalculator.pace(window: UsageWindow(kind: .rolling5h, usedFraction: 0.5, resetAt: nil), now: now) == nil)
}
@Test func paceNilResetVMinulosti() {
    let w = UsageWindow(kind: .weekly(scope: nil), usedFraction: 0.5, resetAt: now.addingTimeInterval(-3600))
    #expect(PaceCalculator.pace(window: w, now: now) == nil)
}
@Test func paceLabelTexty() {
    #expect(PaceLabel.text(deltaPercent: 20) == "napřed o 20 %")
    #expect(PaceLabel.text(deltaPercent: -42) == "pozadu o 42 %")
    #expect(PaceLabel.text(deltaPercent: 0) == "v tempu")
}
```

- [ ] **Step 2: Spusť testy — selžou (typy neexistují)**

Run: `swift test`
Expected: FAIL — kompilace `cannot find 'RelativeTimeFormatter'`. (Pozn. F1: NEpoužívej `--filter`.)

- [ ] **Step 3: Napiš `RelativeTimeFormatter.swift`**

Create `Sources/StatusBarKit/Formatting/RelativeTimeFormatter.swift`:

```swift
import Foundation

/// Relativní čas „před X" (česky; lokalizace v0.9c).
public enum RelativeTimeFormatter {
    public static func string(from date: Date, now: Date) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return "právě teď" }
        let m = s / 60
        if m < 60 { return "před \(m) min" }
        let h = s / 3600
        if h < 24 { return "před \(h) h" }
        return "před \(s / 86400) d"
    }
}
```

- [ ] **Step 4: Napiš `Pace.swift`**

Create `Sources/StatusBarKit/Providers/Pace.swift`:

```swift
import Foundation

/// Tempo čerpání okna: vyčerpáno% − uplynulo% (signed). Kladné = rychleji než lineárně (napřed), záporné = pomaleji (pozadu).
public enum PaceCalculator {
    public static func pace(window: UsageWindow, now: Date) -> Int? {
        guard let reset = window.resetAt, reset > now else { return nil }
        let duration: TimeInterval = window.kind == .rolling5h ? 5 * 3600 : 7 * 24 * 3600
        let start = reset.addingTimeInterval(-duration)
        let elapsedFraction = min(1, max(0, now.timeIntervalSince(start) / duration))
        return Int(((window.usedFraction - elapsedFraction) * 100).rounded())
    }
}

/// Lidský popisek pace (česky; lokalizace v0.9c).
public enum PaceLabel {
    public static func text(deltaPercent d: Int) -> String {
        if d > 0 { return "napřed o \(d) %" }
        if d < 0 { return "pozadu o \(-d) %" }
        return "v tempu"
    }
}
```

- [ ] **Step 5: Spusť testy — projdou; build čistý**

Run: `swift test`
Expected: PASS (10 nových testů zelených).
Run: `swift build`
Expected: Build complete, 0 warnings.

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusBarKit/Formatting/RelativeTimeFormatter.swift Sources/StatusBarKit/Providers/Pace.swift Tests/StatusBarKitTests/RelativeTimeFormatterTests.swift Tests/StatusBarKitTests/PaceTests.swift
git commit -m "feat: RelativeTimeFormatter + PaceCalculator + PaceLabel (pure, tested)"
```

---

### Task 2: `fetchedAt` threading (Kit + App)

**Files:**
- Modify: `Sources/StatusBarKit/Providers/ClaudeUsageSource.swift`
- Modify: `Sources/StatusBarKit/Providers/CodexUsageSource.swift`
- Modify: `Sources/StatusBarKit/Providers/ClaudeCodeCollector.swift`
- Modify: `Sources/StatusBarKit/Providers/CodexCollector.swift`
- Modify: `Sources/StatusBarApp/LiveClaudeUsageSource.swift`
- Modify: `Sources/StatusBarApp/LiveCodexUsageSource.swift`
- Modify (test): `Tests/StatusBarKitTests/ClaudeCodeCollectorTests.swift`
- Modify (test): `Tests/StatusBarKitTests/CodexCollectorTests.swift`

**Interfaces:**
- Produces: `ClaudeLiveUsage.fetchedAt: Date` (init `fetchedAt: Date = Date()`); `CodexLiveUsage { snapshot: CodexSnapshot, fetchedAt: Date }`; `CodexUsageSource.fetchFresh() async -> CodexLiveUsage?`.

- [ ] **Step 1: `ClaudeUsageSource.swift` — `ClaudeLiveUsage +fetchedAt`**

V `Sources/StatusBarKit/Providers/ClaudeUsageSource.swift` nahraď strukturu `ClaudeLiveUsage`:

```swift
public struct ClaudeLiveUsage: Sendable, Equatable {
    public let windows: [UsageWindow]
    public let planLabel: String?
    public let fetchedAt: Date
    public init(windows: [UsageWindow], planLabel: String?, fetchedAt: Date = Date()) {
        self.windows = windows; self.planLabel = planLabel; self.fetchedAt = fetchedAt
    }
}
```

- [ ] **Step 2: `CodexUsageSource.swift` — `CodexLiveUsage` wrapper + protokol**

Nahraď obsah `Sources/StatusBarKit/Providers/CodexUsageSource.swift`:

```swift
import Foundation

/// Živý Codex výsledek: snapshot (z parseru) + čas pořízení.
public struct CodexLiveUsage: Sendable, Equatable {
    public let snapshot: CodexSnapshot
    public let fetchedAt: Date
    public init(snapshot: CodexSnapshot, fetchedAt: Date = Date()) {
        self.snapshot = snapshot; self.fetchedAt = fetchedAt
    }
}

/// Zdroj ČERSTVÝCH Codex limitů (živé wham/usage API). nil = nezdařilo se → fallback na JSONL.
public protocol CodexUsageSource: Sendable {
    func fetchFresh() async -> CodexLiveUsage?
}
```

- [ ] **Step 3: `ClaudeCodeCollector.swift` — `lastUpdated: fresh.fetchedAt`**

V `Sources/StatusBarKit/Providers/ClaudeCodeCollector.swift` v živé větvi (`if let fresh = await liveSource?.fetchFresh()`) změň `lastUpdated: now` na `lastUpdated: fresh.fetchedAt`:

```swift
        if let fresh = await liveSource?.fetchFresh() {
            return ProviderUsage(providerId: .claudeCode, displayName: "Claude Code",
                planLabel: fresh.planLabel, windows: fresh.windows, status: .ok,
                lastUpdated: fresh.fetchedAt, today: today)
        }
```

- [ ] **Step 4: `CodexCollector.swift` — použij `CodexLiveUsage`**

V `Sources/StatusBarKit/Providers/CodexCollector.swift` změň živou větev:

```swift
        if let fresh = await liveSource?.fetchFresh() {
            return ProviderUsage(providerId: .codex, displayName: "Codex",
                planLabel: CodexPlan.label(forPlanType: fresh.snapshot.planType), windows: fresh.snapshot.windows,
                status: .ok, lastUpdated: fresh.fetchedAt, today: today)
        }
```

- [ ] **Step 5: `LiveClaudeUsageSource.swift` — konstruuj s `fetchedAt`**

V `Sources/StatusBarApp/LiveClaudeUsageSource.swift` v `doNetwork()` v případu `case 200` změň konstrukci `ClaudeLiveUsage` tak, aby explicitně nesla `fetchedAt: Date()`:

```swift
        case 200:
            guard let body, let windows = try? ClaudeUsageCacheParser.parseAPIWindows(body), !windows.isEmpty
            else { return (.failed, nil) }
            return (.success, ClaudeLiveUsage(windows: windows, planLabel: ClaudePlan.label(forSubscriptionType: sub), fetchedAt: Date()))
```

(`lastGood` typu `ClaudeLiveUsage?` zůstává — drží snapshot i s jeho `fetchedAt`.)

- [ ] **Step 6: `LiveCodexUsageSource.swift` — vrať `CodexLiveUsage`**

V `Sources/StatusBarApp/LiveCodexUsageSource.swift`:

(a) Změň typ `lastGood` a návratové typy z `CodexSnapshot` na `CodexLiveUsage`:

```swift
    private var lastGood: CodexLiveUsage?
```

(b) `fetchFresh()` návratový typ a tělo (decision vrací `CodexLiveUsage?`):

```swift
    func fetchFresh() async -> CodexLiveUsage? {
        let now = Date()
        let (doFetch, cached): (Bool, CodexLiveUsage?) = lock.withLock {
            if gate.shouldFetch(now: now, policy: policy) {
                gate.lastAttemptAt = now
                return (true, lastGood)
            }
            return (false, lastGood)
        }
        if !doFetch { return cached }
        let (signal, snapshot) = await doNetwork()
        lock.withLock {
            gate = gate.after(signal: signal, now: now, policy: policy)
            if let s = snapshot { lastGood = s }
        }
        return snapshot ?? cached
    }
```

(c) `doNetwork()` návrat `(LiveFetchSignal, CodexLiveUsage?)`; na 200 zabal do `CodexLiveUsage`:

```swift
    private func doNetwork() async -> (LiveFetchSignal, CodexLiveUsage?) {
        guard let auth = CodexAuth.read() else { return (.failed, nil) }
        var (status, body) = await usageCall(token: auth.accessToken, accountId: auth.accountId)
        if status == 401, let refresh = auth.refreshToken, let newToken = await refreshAndStore(refreshToken: refresh) {
            (status, body) = await usageCall(token: newToken, accountId: auth.accountId)
        }
        switch status {
        case 200:
            guard let body, let snap = CodexUsageAPIParser.parse(body), !snap.windows.isEmpty
            else { return (.failed, nil) }
            return (.success, CodexLiveUsage(snapshot: snap, fetchedAt: Date()))
        case 429: return (.rateLimited, nil)
        default:  return (.failed, nil)
        }
    }
```

(ostatní metody `usageCall`/`refreshAndStore`/`roundTripValid` beze změny.)

- [ ] **Step 7: Aktualizuj fake-source testy**

V `Tests/StatusBarKitTests/ClaudeCodeCollectorTests.swift` v testu `collectorPoužijeŽivýZdroj` předej známý `fetchedAt` a ověř `lastUpdated`:

```swift
@Test func collectorPoužijeŽivýZdroj() async {
    let when = Date(timeIntervalSince1970: 1_700_000_000)
    let fresh = ClaudeLiveUsage(
        windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.13, resetAt: nil)], planLabel: "Max", fetchedAt: when)
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("none-\(UUID().uuidString).json")
    let u = await ClaudeCodeCollector(cachePath: missing, staleAfter: 999,
        liveSource: FakeClaudeSource(usage: fresh)).fetch(includeToday: false)
    #expect(u.status == .ok)
    #expect(u.planLabel == "Max")
    #expect(u.windows.first?.usedFraction == 0.13)
    #expect(u.lastUpdated == when)                          // lastUpdated = fetchedAt
}
```

V `Tests/StatusBarKitTests/CodexCollectorTests.swift` uprav `FakeCodexSource` a oba testy, které ho/`CodexLiveUsage` používají:

```swift
private struct FakeCodexSource: CodexUsageSource {
    let live: CodexLiveUsage?
    func fetchFresh() async -> CodexLiveUsage? { live }
}
```

a v testu `codexCollectorPoužijeŽivýZdroj`:

```swift
@Test func codexCollectorPoužijeŽivýZdroj() async {
    let when = Date(timeIntervalSince1970: 1_700_000_000)
    let live = CodexLiveUsage(snapshot: CodexSnapshot(windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.05, resetAt: nil)], planType: "plus"), fetchedAt: when)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cx-live-\(UUID().uuidString)")
    let u = await CodexCollector(sessionsDir: root, liveSource: FakeCodexSource(live: live)).fetch(includeToday: false)
    if case .ok = u.status {} else { Issue.record("čekán .ok z živého zdroje") }
    #expect(u.planLabel == "Plus")
    #expect(u.windows.count == 1)
    #expect(u.windows.first?.kind == .rolling5h)
    #expect(u.lastUpdated == when)
}
```

a v testu `codexCollectorFallbackNaJSONLKdyžŽivýNil` změň `FakeCodexSource(snap: nil)` na `FakeCodexSource(live: nil)`.

- [ ] **Step 8: Build + test**

Run: `swift build && swift test`
Expected: Build complete (0 warnings); všechny testy PASS (vč. upravených collector testů, `lastUpdated == fetchedAt`).

- [ ] **Step 9: Commit**

```bash
git add Sources/StatusBarKit/Providers/ClaudeUsageSource.swift Sources/StatusBarKit/Providers/CodexUsageSource.swift Sources/StatusBarKit/Providers/ClaudeCodeCollector.swift Sources/StatusBarKit/Providers/CodexCollector.swift Sources/StatusBarApp/LiveClaudeUsageSource.swift Sources/StatusBarApp/LiveCodexUsageSource.swift Tests/StatusBarKitTests/ClaudeCodeCollectorTests.swift Tests/StatusBarKitTests/CodexCollectorTests.swift
git commit -m "feat: fetchedAt threading (ClaudeLiveUsage + CodexLiveUsage) → lastUpdated = čas fetche"
```

---

### Task 3: App UI — `PopoverView` (Aktualizováno, Pace, odkazy) + verze

**Files:**
- Modify: `Sources/StatusBarApp/PopoverView.swift`
- Modify: `Resources/Info.plist` (verze 0.8.1)

**Interfaces:**
- Consumes: `RelativeTimeFormatter.string(from:now:)`, `PaceCalculator.pace(window:now:)`, `PaceLabel.text(deltaPercent:)`, `ProviderUsage.lastUpdated`.

> **Pozn.:** App vrstva, ověření = `swift build && swift test` + smoke. Agent NESPOUŠTÍ `.app`.

- [ ] **Step 1: Přidej `import AppKit` do `PopoverView.swift`**

Na začátek `Sources/StatusBarApp/PopoverView.swift` (za `import SwiftUI`):

```swift
import AppKit
```

- [ ] **Step 2: Header karty — plán doprava + „Aktualizováno před X"**

V `ProviderCard.body` nahraď úvodní `HStack` (s dot + displayName + planLabel) tímto blokem:

```swift
            HStack {
                Circle().fill(usage.providerId == .claudeCode ? Color(red:0.85,green:0.46,blue:0.34) : Color(red:0.06,green:0.64,blue:0.50)).frame(width: 9, height: 9)
                Text(usage.displayName).fontWeight(.semibold)
                Spacer()
                if let p = usage.planLabel { Text(p).font(.caption).foregroundStyle(.secondary) }
            }
            Text("Aktualizováno \(RelativeTimeFormatter.string(from: usage.lastUpdated, now: Date()))")
                .font(.caption2).foregroundStyle(.tertiary)
```

- [ ] **Step 3: Pace řádek pod oknem**

V `windowsList` přidej za `ProgressView(...)` (uvnitř vnitřního `VStack`) pace řádek:

```swift
                ProgressView(value: max(0.0, min(1.0, 1 - w.usedFraction))).tint(UsageColor.color(forFraction: w.usedFraction))
                if let d = PaceCalculator.pace(window: w, now: Date()) {
                    Text("Tempo: \(PaceLabel.text(deltaPercent: d))").font(.caption2).foregroundStyle(.tertiary)
                }
```

- [ ] **Step 4: Sekce rychlých odkazů**

V `PopoverView.body` přidej PŘED finální `HStack` s „Nastavení…/Konec" tento blok:

```swift
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                linkButton("Stav Anthropic", "https://status.anthropic.com")
                linkButton("Stav OpenAI", "https://status.openai.com")
                linkButton("Usage Claude", "https://claude.ai/settings/usage")
                linkButton("Usage OpenAI", "https://platform.openai.com/usage")
            }.padding(.horizontal, 14).padding(.vertical, 8)
```

a přidej do `struct PopoverView` privátní helper (za `dnesCelkem`):

```swift
    private func linkButton(_ title: String, _ urlString: String) -> some View {
        Button(title) { if let u = URL(string: urlString) { NSWorkspace.shared.open(u) } }
            .buttonStyle(.borderless).font(.caption)
    }
```

- [ ] **Step 5: Bump verze v `Info.plist`**

V `Resources/Info.plist` změň obě pole na `0.8.1`:

```xml
  <key>CFBundleVersion</key><string>0.8.1</string>
  <key>CFBundleShortVersionString</key><string>0.8.1</string>
```

- [ ] **Step 6: Build + test**

Run: `swift build && swift test`
Expected: Build complete (0 warnings); všechny testy PASS.

- [ ] **Step 7: Postav `.app` (NEspouštět GUI)**

Run: `swift build -c release && bash scripts/make-app.sh`
Expected: exit 0, vyrobí `StatusBar.app`. Agent NESPOUŠTÍ. Nahlas cestu.
On failure: nahlas výstup a ZASTAV.

- [ ] **Step 8: Commit**

```bash
git add Sources/StatusBarApp/PopoverView.swift Resources/Info.plist
git commit -m "feat: popover Aktualizováno před X + Pace řádky + rychlé odkazy + verze 0.8.1"
```

---

## Verifikace (po všech taskách)
- `swift build` (debug+release) čistý, `swift test` zelený (existující + ~11 nových testů: 4 rel. čas + 6 pace + collector lastUpdated).
- GAP (ověří uživatel): vizuál „Aktualizováno před X", pace řádků, fungující odkazy.

## Rollback & Recovery
Aditivní (nové Kit typy + fetchedAt threading + UI). Rollback = `git revert`/`git checkout main -- <soubory>`.

## Risk Register
| ID | Severity | Likelihood | Risk | Mitigace (krok) | Resolution |
|----|----------|------------|------|-----------------|------------|
| R1 | LOW | M | `CodexUsageSource` návrat = hard změna → nekompiluje, dokud nehotová | live source+collector+test v JEDNOM tasku (T2), build green až po T2 | mitigated |
| R2 | LOW | L | `ClaudeLiveUsage` default `Date()` rozbije rovnost v testu | testy předávají explicitní `fetchedAt`; default jen pro kompilaci starých konstrukcí | mitigated |
| R3 | LOW | L | URL dashboardů se změní | degradace neškodná | accepted |
| R4 | LOW | L | pace u 5h volatilní | caption2, drobné; nil když resetAt v minulosti | accepted |

## Audit Trail
- **Lenses applied:** 1 red-team, 2 security (N/A — jen veřejné status/usage URL, žádné secrets), 3 assumptions, 4 dependencies, 5 alternatives, 6 cheap-executor, 7 goal-fit.
- **Empirická verifikace (klíčová):** 10 Task 1 asercí (4 rel. čas + 6 pace) dočasně přidáno (+ temp impl) a spuštěno `swift test` → **10/10 PASS** (pace −20/+20/0, hranice, nil-cesty ověřeny). Scratch revertnut, baseline zpět 109.
- **Alternativy (lens 5):** `fetchedAt` přes wrapper `CodexLiveUsage` *(zvoleno — `CodexSnapshot` zůstane čistý parser typ)*; vs. přidat fetchedAt do `CodexSnapshot` (rozbije parser testy); vs. akceptovat nepřesný `lastUpdated=now` (lhalo by po throttle).
- **Findings:** 0 CRIT, 0 HIGH, 0 MED, 2 LOW (accepted): „Aktualizováno" u `.unavailable` ukáže „právě teď" (honest — naposled zkoušeno teď); relativní čas se v otevřeném popoveru živě neaktualizuje (popover transientní, refresh při otevření).
- **Re-audit/dry run:** PASSED — build zelený po každém tasku (T1 nový Kit unused; T2 `CodexUsageSource` návrat = hard změna, ale live source+collector+test atomicky v T2; T3 UI). Identifikátory (`RelativeTimeFormatter.string`, `PaceCalculator.pace`, `PaceLabel.text`, `ClaudeLiveUsage.fetchedAt`, `CodexLiveUsage{snapshot,fetchedAt}`) konzistentní.
- **Rozhodnutí:** spuštěno s defaulty dle delegace („prožeň"); 0 nálezů k rozhodnutí; kill criterion v Guardrails.
