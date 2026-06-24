# StatusBar v0.9d Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** UX polish popoveru/nastavení dle CodexBar reference (Session/Weekly názvy, per-provider odkazy, volba okna v liště, přehlednější Nastavení) + paralelizace 30denního skenu (12 s → ~2-3 s).

**Architecture:** Kit dostane paralelní `rangeUsage` (akumulátor `@unchecked Sendable` + `NSLock`), nové názvy oken, `BarWindowSource` + `ProviderUsage.usedPercent(for:)` + `segments(source:)` + `PreferencesStore.barWindowSource`. App přepíše popover odkazy na per-provider, přeorganizuje Nastavení a přidá picker okna. Vše lokalizováno přes systém z v0.9c.

**Tech Stack:** Swift 6.0, SwiftPM (macOS 14+), Swift Testing (`@Test`/`#expect`), AppKit/SwiftUI, GCD (`DispatchQueue.concurrentPerform`).

## Global Constraints

- **Testy:** `swift test --filter` NEMATCHUJE volné `@Test func` → vždy **plný `swift test`**.
- **Swift 6 strict concurrency:** paralelní closure NESMÍ mutovat zachycený `var` ani nešendovatelný stav → použít `final class … @unchecked Sendable` + `NSLock` akumulátor (vzor jako existující `Counter`/live zdroje). Žádný `await` pod zámkem.
- **Lokalizace:** Kit formattery `bundle: Bundle? = nil` → `?? .module` (`Bundle.module` je internal, NEJDE default arg public fce). App přes `.module` přímo. Pravidlo **%/%%**: klíče přes `String(format:)` → `%%`; přímý `NSLocalizedString`/`String(localized:)` → `%`. `%lld` pro Int, `%@` pro String.
- **Default `BarWindowSource = .auto`** → `usedPercent(.auto) == nearestLimitPercent` = bajt-za-bajt dnešní chování lišty (nulová regrese, existující `segments` testy projdou beze změny).
- **Cena = reálná spotřeba** (`PricingEstimator.estimateReal`). Tato větev NEMĚNÍ auth/credential/network/refresh kód.
- **Verze:** `Resources/Info.plist` → **0.9.1** (oba klíče).
- **Agent NESPOUŠTÍ GUI `.app`** — jen `swift build`/`swift test` (+ `make-app.sh` build-check).
- **NElokalizováno:** `$`, názvy plánů/modelů, MenuBar „—", `weekly(scope)` = název modelu (přímo, bez klíče), číselné formáty.

---

## Plan-forge hardening (AUDIT 2026-06-24, depth standard)

> Executor: subagent-driven-development (implementer Sonnet + reviewer Sonnet/Opus per task). 0 CRIT/HIGH. Paralelizace empiricky ověřena PŘED tímto hardeningem.

### Assumptions
| # | Předpoklad | Stav | Jak ověřeno |
|---|------------|------|-------------|
| A1 | `concurrentPerform` + `@unchecked Sendable` akumulátor + `NSLock` projde Swift 6 strict (kompilace) | **verified** | forge: dočasná paralelizace → `swift build` Build complete (jen 1 warning, viz A2) |
| A2 | Zachycení `var urls` v `concurrentPerform` je čisté | **FALSE → F1** | forge build: warning `#SendableClosureCaptures` na ClaudeTokenScanner; Codex (`let urls`) bez warningu → fix `let urls` |
| A3 | Paralelní výsledek == sekvenční (korektnost merge) | **verified** | forge stress test (20 souborů → přesně 3000 tok) PASS |
| A4 | Reálné zrychlení 12 s → cíl ~2-3 s | **verified** | forge: živá ~/.claude data 30d → **3,67 s** (~3,3×); 113M tok, 5 modelů |
| A5 | Default `BarWindowSource.auto` → `usedPercent(.auto) == nearestLimitPercent` = nulová regrese lišty | **verified (logika)** | `segments(source: .auto)` volá `usedPercent(.auto)` = `nearestLimitPercent`; existující `segments`/`MenuBarStyle` testy beze změny |
| A6 | `BarWindowSource: String` funguje s `@AppStorage` (jako `MenuBarStyle`) | **verified** | stejný vzor ověřen v0.7a (`@AppStorage<MenuBarStyle>` kompiluje nativně) |
| A7 | SF Symbols `chart.line.uptrend.xyaxis`, `waveform.path.ecg` existují (macOS 14) | **accepted** | standardní SF Symbols (macOS 13+); fallback: jiný symbol, vizuál ověří uživatel |
| A8 | `bundle: Bundle? = nil` + `%/%%` pravidlo + `Bundle.module` internal | **verified (v0.9c)** | převzato z ověřené v0.9c lokalizace |

### Guardrails
- **Zakázáno:** měnit auth/credential/network/refresh kód; logovat surový obsah konverzací; psát do `~/.claude`/`~/.codex`; spouštět GUI `.app`; push bez explicitního souhlasu.
- **⚠ Nevratné:** žádné (lokální kód + testy, vše `git`-revertovatelné).
- **Globální stop podmínky:** (1) `swift build` Swift 6 concurrency ERROR (ne warning) v paralelizaci → ZASTAV (A1 to vylučuje, F1 řeší warning). (2) Po tasku `swift test` červené a nejde opravit dle „On failure" → ZASTAV. (3) Po Task 1 reálný sken NEzrychlí (> 8 s) → ZASTAV a nahlas (A4 to vylučuje).
- **Kill criteria:** pokud po 2 re-implementačních smyčkách kteréhokoli tasku `swift test` neprochází, nebo paralelizace nejde Swift-6-čistě bez warningu → větev se odloží, perf (Task 1) se vrátí do forge, UX tasky (2–6) mohou jít samostatně. Přezkum: nedojde-li exekuce do konce této session, stav v ledgeru → pokračovat příště.

### Risk Register
| ID | Sev | Lik | Riziko | Mitigace (krok) | Resolution |
|----|-----|-----|--------|------------------|------------|
| F1 | MED | H | `var urls` zachycený → Swift 6 warning | `let urls = collected` (Task 1 Step 3) | fixed-in-Task1 |
| F2 | MED | M | `.weekly` ukáže scoped % místo celkového | preferovat `weekly(nil)` (Task 3 Step 4 + test) | fixed-in-Task3 (CP2) |
| F3 | LOW | L | Nejednoznačné umístění akumulátoru/metody | předepsáno přesně (Task 1/3) | fixed |
| F4 | LOW | L | Task 5 Step 2 part-replace bez kotev | zpřesněny kotvy | fixed |
| R2 | LOW | L | `.session/.weekly` skryje kritické druhé okno | `.auto` default hlídá nejhorší | accepted |

### Audit Trail
- **Lenses:** 1 (failure) → F1; 2 (security) → N/A (read-only paralelní sken čísel + UI, žádné credentials/síť/destrukce); 3 (assumptions) → A1–A8 (A2 odhalil F1); 4 (deps) → ordering Task2→3→5 OK, žádný konflikt; 5 (alternatives) → akumulátor vs unsafe-buffer vs TaskGroup (akumulátor verified clean+fast); 6 (executor) → F3/F4; 7 (goal) → F2 (Weekly sémantika).
- **Findings:** 4 (2 MED, 2 LOW) → 4 fixed; 0 CRIT/HIGH. F1 empiricky odhalen.
- **Re-audit (R*):** po hardeningu bez nových defektů (let urls čisté, weekly_all preferuje, kotvy zpřesněny).
- **Tabletop dry run:** PASSED — Task1(parallel)→2(window klíče)→3(BarWindowSource reusuje window.session/weekly + usedPercent prefer weekly_all + segments source)→4(App odkazy)→5(picker reusuje BarWindowSource + source wiring + 0.9.1)→6(úplnost+grep). Identifikátory konzistentní; žádný krok nezávisí na pozdějším.
- **Klíčové změny vs draft v0:** F1→`let urls`; F2→`usedPercent(.weekly)` preferuje weekly_all + test; F3/F4→přesné kotvy.
- **Rozhodnutí uživatele (CP2):** F2 celkové týdenní okno; fix scope vše (F1–F4).
- **Sledovat při exekuci:** Task 1 reálné zrychlení (uživatel ověří svižnost popoveru); vizuál per-provider odkazů + picker okna.

---

### Task 1: Kit — paralelizace 30denního skenu

**Files:**
- Modify: `Sources/StatusBarKit/Providers/ClaudeTokenScanner.swift`
- Modify: `Sources/StatusBarKit/Providers/CodexTokenScanner.swift`
- Test: `Tests/StatusBarKitTests/ClaudeTokenScannerTests.swift` (přidat stress test)

**Interfaces:**
- Beze změny veřejných signatur: `rangeUsage(start:end:) -> TodayUsage?`, `todayUsage(now:calendar:)`. Chování IDENTICKÉ, jen paralelní.

> Refaktor zachovává chování → existující range testy jsou regresní síť. plan-forge navíc empiricky změří zrychlení.

- [ ] **Step 1: Přidej stress test (víc souborů → ověř merge)**

```swift
// Tests/StatusBarKitTests/ClaudeTokenScannerTests.swift — PŘIDAT na konec
@Test func claudeRangeUsageMergePřesVíceSouborů() throws {
    let cal = Calendar.current
    var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 20; c.hour = 12
    let day = cal.date(from: c)!
    let start = cal.date(byAdding: .day, value: -30, to: day)!
    let inWindow = cal.date(byAdding: .day, value: -5, to: day)!
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("claudeMerge-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    // 5 souborů, každý 100 input + 50 output stejného modelu → součet 500/250
    for n in 0..<5 {
        let f = tmp.appendingPathComponent("s\(n).jsonl")
        try """
        {"type":"assistant","timestamp":"\(iso.string(from: inWindow))","message":{"model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """.data(using: .utf8)!.write(to: f)
        try FileManager.default.setAttributes([.modificationDate: inWindow], ofItemAtPath: f.path)
    }
    let r = try #require(ClaudeTokenScanner(projectsDir: tmp).rangeUsage(start: start, end: day))
    #expect(r.perModel.count == 1)
    #expect(r.total.realTokens == 750)   // 5 × (100+50) — paralelní merge musí sečíst vše
}
```

- [ ] **Step 2: Run — ověř že prochází se SEKVENČNÍM kódem (baseline)**

Run: `swift test`
Expected: PASS (sekvenční kód to zvládne; test je regresní síť pro paralelizaci).

- [ ] **Step 3: Paralelizuj `ClaudeTokenScanner.rangeUsage`**

Nahraď tělo `rangeUsage` (ponech `todayUsage` beze změny) v `Sources/StatusBarKit/Providers/ClaudeTokenScanner.swift`:

```swift
    public func rangeUsage(start: Date, end: Date) -> TodayUsage? {
        // 1) Posbírej URL souborů v rozsahu (mtime ≥ start) — sekvenčně (enumerator je levný).
        // F1: výsledek MUSÍ být `let` (ne `var`) — `var` zachycený v concurrentPerform = Swift 6 warning #SendableClosureCaptures.
        var collected: [URL] = []
        if let en = FileManager.default.enumerator(at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let url as URL in en where url.pathExtension == "jsonl" {
                if let mod = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   mod >= start { collected.append(url) }
            }
        }
        let urls = collected
        guard !urls.isEmpty else { return nil }

        // 2) Parsuj soubory PARALELNĚ; merge přes thread-safe akumulátor (Swift 6 čistý).
        let acc = ModelTokenAccumulator()
        DispatchQueue.concurrentPerform(iterations: urls.count) { i in
            guard let data = try? Data(contentsOf: urls[i]) else { return }
            acc.merge(ClaudeTokenParser.sumByModel(fromJSONL: data, dayStart: start, dayEnd: end))
        }
        let byModel = acc.snapshot()

        // 3) Vyhoď 0-token modely, seřaď, spočítej reálnou cenu.
        let perModel = byModel
            .filter { $0.value.totalTokens > 0 }
            .map { ModelTokens(modelName: $0.key, tokens: $0.value) }
            .sorted { $0.modelName < $1.modelName }
        guard !perModel.isEmpty else { return nil }
        return TodayUsage(perModel: perModel, estimatedCost: PricingEstimator.estimateReal(perModel))
    }
```

Přidej na konec souboru (POD uzavírací `}` struct `ClaudeTokenScanner`, jako top-level deklarace) sdílený akumulátor:

```swift
/// Thread-safe merge per-model tokenů z paralelního skenu (Swift 6: @unchecked Sendable + NSLock).
final class ModelTokenAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var byModel: [String: TokenUsage] = [:]
    func merge(_ partial: [String: TokenUsage]) {
        lock.lock(); defer { lock.unlock() }
        for (model, usage) in partial { byModel[model, default: .zero] = (byModel[model] ?? .zero) + usage }
    }
    func snapshot() -> [String: TokenUsage] { lock.lock(); defer { lock.unlock() }; return byModel }
}
```

- [ ] **Step 4: Paralelizuj `CodexTokenScanner.rangeUsage`**

Nahraď tělo `rangeUsage` (ponech `todayUsage`) v `Sources/StatusBarKit/Providers/CodexTokenScanner.swift`:

```swift
    public func rangeUsage(start: Date, end: Date) -> TodayUsage? {
        guard let en = FileManager.default.enumerator(at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        var files: [(URL, Date)] = []
        for case let url as URL in en where url.pathExtension == "jsonl" {
            if let m = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               m >= start, m < end {
                files.append((url, m))
            }
        }
        let urls = files.sorted(by: { $0.1 > $1.1 }).prefix(maxFilesToScan).map(\.0)
        guard !urls.isEmpty else { return nil }

        let acc = TokenSumAccumulator()
        DispatchQueue.concurrentPerform(iterations: urls.count) { i in
            guard let data = try? Data(contentsOf: urls[i]),
                  let t = CodexTokenParser.lastTotal(fromJSONL: data) else { return }
            acc.add(t)
        }
        let (sum, any) = acc.snapshot()
        guard any else { return nil }
        let perModel = [ModelTokens(modelName: "codex", tokens: sum)]
        return TodayUsage(perModel: perModel, estimatedCost: PricingEstimator.estimateReal(perModel))
    }
```

Přidej na konec souboru (POD uzavírací `}` struct `CodexTokenScanner`, top-level):

```swift
/// Thread-safe součet TokenUsage z paralelního skenu.
final class TokenSumAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var sum = TokenUsage.zero
    private var any = false
    func add(_ t: TokenUsage) { lock.lock(); sum = sum + t; any = true; lock.unlock() }
    func snapshot() -> (TokenUsage, Bool) { lock.lock(); defer { lock.unlock() }; return (sum, any) }
}
```

- [ ] **Step 5: Run test — vše zelené, bez concurrency warningů**

Run: `swift build 2>&1 | grep -i warning; swift test`
Expected: žádné concurrency warningy; PASS (existující range/today testy + nový stress test). Pokud Swift 6 odmítne `concurrentPerform` capture → BLOCKED, nahlas přesnou chybu (plan-forge má fallback).

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusBarKit/Providers/ClaudeTokenScanner.swift Sources/StatusBarKit/Providers/CodexTokenScanner.swift Tests/StatusBarKitTests/ClaudeTokenScannerTests.swift
git commit -m "perf: paralelní 30denní sken (concurrentPerform + thread-safe akumulátor)"
```

---

### Task 2: Kit — názvy oken Session/Weekly + scope = název modelu

**Files:**
- Modify: `Sources/StatusBarKit/Formatting/Formatting.swift` (`WindowLabel`)
- Modify: `Sources/StatusBarKit/Resources/en.lproj/Localizable.strings`, `cs.lproj/Localizable.strings`
- Test: `Tests/StatusBarKitTests/FormattingTests.swift` (`popiskyOken`)

**Interfaces:**
- `WindowLabel.text(for:bundle:)` beze změny signatury; jiné výstupy + jiné klíče.

- [ ] **Step 1: Uprav test `popiskyOken` (nejdřív — musí failnout)**

V `Tests/StatusBarKitTests/FormattingTests.swift` nahraď `popiskyOken`:

```swift
@Test func popiskyOken() {
    let cs = L10n.bundle("cs"); let en = L10n.bundle("en")
    #expect(WindowLabel.text(for: .rolling5h, bundle: cs) == "Relace")
    #expect(WindowLabel.text(for: .weekly(scope: nil), bundle: cs) == "Týden")
    #expect(WindowLabel.text(for: .weekly(scope: "Sonnet"), bundle: cs) == "Sonnet")
    #expect(WindowLabel.text(for: .rolling5h, bundle: en) == "Session")
    #expect(WindowLabel.text(for: .weekly(scope: nil), bundle: en) == "Weekly")
    #expect(WindowLabel.text(for: .weekly(scope: "Sonnet"), bundle: en) == "Sonnet")
}
```

- [ ] **Step 2: Run — failuje (staré výstupy/klíče)**

Run: `swift test`
Expected: FAIL (vrací „5h okno"/„Týden · Sonnet").

- [ ] **Step 3: Uprav `WindowLabel`**

V `Sources/StatusBarKit/Formatting/Formatting.swift` nahraď `WindowLabel`:

```swift
public enum WindowLabel {
    public static func text(for kind: WindowKind, bundle: Bundle? = nil) -> String {
        let b = bundle ?? .module
        switch kind {
        case .rolling5h: return NSLocalizedString("window.session", bundle: b, comment: "5h rolling window")
        case .weekly(let scope):
            if let scope { return scope }   // scoped weekly = jen název modelu (nepřekládá se)
            return NSLocalizedString("window.weekly", bundle: b, comment: "weekly window")
        }
    }
}
```

- [ ] **Step 4: Klíče v Kit `.strings` (přidat nové, odstranit staré window.*)**

V `Sources/StatusBarKit/Resources/en.lproj/Localizable.strings` nahraď blok `window.5h`/`window.week`/`window.week.scope`:
```
"window.session" = "Session";
"window.weekly" = "Weekly";
```
V `Sources/StatusBarKit/Resources/cs.lproj/Localizable.strings` nahraď tentýž blok:
```
"window.session" = "Relace";
"window.weekly" = "Týden";
```
(Klíče `window.5h`, `window.week`, `window.week.scope` ÚPLNĚ ODSTRAŇ z obou souborů.)

- [ ] **Step 5: Run test — zelené (cs i en)**

Run: `swift test`
Expected: PASS (`popiskyOken` cs „Relace"/„Týden"/„Sonnet", en „Session"/„Weekly"/„Sonnet").

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusBarKit/Formatting/Formatting.swift Sources/StatusBarKit/Resources Tests/StatusBarKitTests/FormattingTests.swift
git commit -m "feat: názvy oken Session/Weekly (cs Relace/Týden), scoped = název modelu"
```

---

### Task 3: Kit — `BarWindowSource` + `usedPercent(for:)` + `segments(source:)` + preference

**Files:**
- Create: `Sources/StatusBarKit/Formatting/BarWindowSource.swift`
- Modify: `Sources/StatusBarKit/Models/ProviderUsage.swift` (přidat `usedPercent(for:)`)
- Modify: `Sources/StatusBarKit/Formatting/Formatting.swift` (`segments` + `perProvider`)
- Modify: `Sources/StatusBarKit/Preferences/PreferencesStore.swift`
- Modify: `Sources/StatusBarKit/Resources/en.lproj/Localizable.strings`, `cs.lproj/Localizable.strings` (`barsource.auto`)
- Test: `Tests/StatusBarKitTests/BarWindowSourceTests.swift` (nový)

**Interfaces:**
- Produces: `enum BarWindowSource: String, Sendable, Hashable, CaseIterable { case auto, session, weekly }` + `func displayName(bundle: Bundle? = nil) -> String` + `var displayName: String`. `ProviderUsage.usedPercent(for: BarWindowSource) -> Int`. `MenuBarTitleBuilder.segments(for:style:showUsedPercent:source: BarWindowSource = .auto)`. `PreferencesStore.barWindowSource: BarWindowSource`, `PreferenceKeys.barWindowSource`.
- Consumes: `L10n` (testy), `window.session`/`window.weekly` (z Task 2).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/StatusBarKitTests/BarWindowSourceTests.swift
import Testing
import Foundation
@testable import StatusBarKit

private func usage(session: Double?, weekly: Double?) -> ProviderUsage {
    var w: [UsageWindow] = []
    if let s = session { w.append(UsageWindow(kind: .rolling5h, usedFraction: s, resetAt: nil)) }
    if let wk = weekly { w.append(UsageWindow(kind: .weekly(scope: nil), usedFraction: wk, resetAt: nil)) }
    return ProviderUsage(providerId: .claudeCode, displayName: "Claude Code", planLabel: nil,
        windows: w, status: .ok, lastUpdated: Date())
}

@Test func usedPercentVybíráOkno() {
    let u = usage(session: 0.20, weekly: 0.80)
    #expect(u.usedPercent(for: .session) == 20)
    #expect(u.usedPercent(for: .weekly) == 80)
    #expect(u.usedPercent(for: .auto) == 80)              // nearest = max
}

@Test func usedPercentFallbackKdyžOknoChybí() {
    let jenSession = usage(session: 0.30, weekly: nil)
    #expect(jenSession.usedPercent(for: .weekly) == 30)   // chybí weekly → nearest (30)
    let jenWeekly = usage(session: nil, weekly: 0.55)
    #expect(jenWeekly.usedPercent(for: .session) == 55)   // chybí session → nearest (55)
}

@Test func usedPercentWeeklyPreferujeCelkové() {
    // F2: weekly_all (scope nil) = 40 %, scoped „Sonnet" = 90 % → .weekly bere CELKOVÉ (40), ne scoped
    let u = ProviderUsage(providerId: .claudeCode, displayName: "Claude Code", planLabel: nil,
        windows: [
            UsageWindow(kind: .rolling5h, usedFraction: 0.10, resetAt: nil),
            UsageWindow(kind: .weekly(scope: nil), usedFraction: 0.40, resetAt: nil),
            UsageWindow(kind: .weekly(scope: "Sonnet"), usedFraction: 0.90, resetAt: nil),
        ], status: .ok, lastUpdated: Date())
    #expect(u.usedPercent(for: .weekly) == 40)            // celkové týdenní, ne scoped 90
    #expect(u.usedPercent(for: .auto) == 90)              // auto = nearest = nejhorší (90)
}

@Test func segmentsSourceVybíráČísloIBarvu() {
    let u = usage(session: 0.05, weekly: 0.95)             // session bezpečné, weekly kritické
    let sSession = MenuBarTitleBuilder.segments(for: [u], style: .dotPercent, showUsedPercent: true, source: .session)
    #expect(sSession[0].text == "5%")
    #expect(sSession[0].level == .normal)
    let sWeekly = MenuBarTitleBuilder.segments(for: [u], style: .dotPercent, showUsedPercent: true, source: .weekly)
    #expect(sWeekly[0].text == "95%")
    #expect(sWeekly[0].level == .critical)
    let sAuto = MenuBarTitleBuilder.segments(for: [u], style: .dotPercent, showUsedPercent: true)  // default .auto
    #expect(sAuto[0].text == "95%")                       // auto = nearest = beze změny
}

@Test func barWindowSourceDisplayName() {
    let cs = L10n.bundle("cs"); let en = L10n.bundle("en")
    #expect(BarWindowSource.session.displayName(bundle: cs) == "Relace")
    #expect(BarWindowSource.weekly.displayName(bundle: cs) == "Týden")
    #expect(BarWindowSource.auto.displayName(bundle: cs) == "Auto")
    #expect(BarWindowSource.session.displayName(bundle: en) == "Session")
    #expect(BarWindowSource.allCases.count == 3)
}

@Test func preferenceBarWindowSourceDefaultAuto() {
    let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    let prefs = PreferencesStore(defaults: suite)
    #expect(prefs.barWindowSource == .auto)               // default
    prefs.barWindowSource = .weekly
    #expect(prefs.barWindowSource == .weekly)
}
```

- [ ] **Step 2: Run — failuje**

Run: `swift test`
Expected: FAIL (chybí `BarWindowSource`, `usedPercent`, `source:` param, `barWindowSource`).

- [ ] **Step 3: `BarWindowSource`**

```swift
// Sources/StatusBarKit/Formatting/BarWindowSource.swift
import Foundation

/// Které okno ukazuje lišta. `.auto` = nejhorší okno (dnešní chování).
public enum BarWindowSource: String, Sendable, Hashable, CaseIterable {
    case auto, session, weekly

    public func displayName(bundle: Bundle? = nil) -> String {
        let b = bundle ?? .module
        switch self {
        case .auto:    return NSLocalizedString("barsource.auto", bundle: b, comment: "auto = worst window")
        case .session: return NSLocalizedString("window.session", bundle: b, comment: "")
        case .weekly:  return NSLocalizedString("window.weekly", bundle: b, comment: "")
        }
    }
    public var displayName: String { displayName() }
}
```

- [ ] **Step 4: `ProviderUsage.usedPercent(for:)`**

V `Sources/StatusBarKit/Models/ProviderUsage.swift` přidej do `struct ProviderUsage` jako další metodu, ZA computed `var nearestLimitPercent` (řádek `public var nearestLimitPercent: Int { ... }`):

```swift
    /// Used % okna zvoleného lištou. Chybí-li dané okno, fallback na nejhorší (nearestLimitPercent).
    public func usedPercent(for source: BarWindowSource) -> Int {
        switch source {
        case .auto:
            return nearestLimitPercent
        case .session:
            if let w = windows.first(where: { $0.kind == .rolling5h }) {
                return Int((w.usedFraction * 100).rounded())
            }
            return nearestLimitPercent
        case .weekly:
            // F2: preferuj CELKOVÉ týdenní okno (weekly_all, scope == nil) — to je „Weekly" na fotce.
            if let allWeekly = windows.first(where: { if case .weekly(let s) = $0.kind { return s == nil }; return false }) {
                return Int((allWeekly.usedFraction * 100).rounded())
            }
            // jinak nejhorší týdenní (scoped), jinak nearest
            let weeklies = windows.filter { if case .weekly = $0.kind { return true }; return false }
            if let w = weeklies.max(by: { $0.usedFraction < $1.usedFraction }) {
                return Int((w.usedFraction * 100).rounded())
            }
            return nearestLimitPercent
        }
    }
```

- [ ] **Step 5: `segments(source:)`**

V `Sources/StatusBarKit/Formatting/Formatting.swift` uprav `perProvider` a `segments` (přidej `source`, nahraď `nearestLimitPercent` → `usedPercent(for: source)`):

```swift
    private static func perProvider(_ u: ProviderUsage, label: Bool, showUsedPercent: Bool, source: BarWindowSource) -> MenuBarSegment {
        let leading: MenuBarSegment.Leading = label ? .label(shortLabel(u.providerId)) : .providerDot
        if case .unavailable = u.status {
            return MenuBarSegment(providerId: u.providerId, leading: leading, text: "—", level: .normal)
        }
        let used = u.usedPercent(for: source)
        let shown = showUsedPercent ? used : max(0, 100 - used)
        return MenuBarSegment(providerId: u.providerId, leading: leading,
                              text: "\(shown)%", level: UsageLevel.level(forPercent: used))
    }

    public static func segments(for usages: [ProviderUsage],
                                style: MenuBarStyle = .dotPercent,
                                showUsedPercent: Bool = false,
                                source: BarWindowSource = .auto) -> [MenuBarSegment] {
        switch style {
        case .dotPercent:
            return usages.map { perProvider($0, label: false, showUsedPercent: showUsedPercent, source: source) }
        case .labelPercent:
            return usages.map { perProvider($0, label: true, showUsedPercent: showUsedPercent, source: source) }
        case .dotOnly:
            return usages.map { u in
                let level = displayable(u) ? UsageLevel.level(forPercent: u.usedPercent(for: source)) : .normal
                return MenuBarSegment(providerId: u.providerId, leading: .levelDot, text: "", level: level)
            }
        case .worst:
            let pool = usages.filter(displayable)
            if let worst = pool.max(by: { $0.usedPercent(for: source) < $1.usedPercent(for: source) }) {
                let used = worst.usedPercent(for: source)
                let shown = showUsedPercent ? used : max(0, 100 - used)
                return [MenuBarSegment(providerId: worst.providerId, leading: .providerDot,
                                       text: "\(shown)%", level: UsageLevel.level(forPercent: used))]
            }
            if usages.isEmpty { return [] }
            return [MenuBarSegment(providerId: usages[0].providerId, leading: .none, text: "—", level: .normal)]
        }
    }
```

- [ ] **Step 6: `PreferencesStore.barWindowSource`**

V `Sources/StatusBarKit/Preferences/PreferencesStore.swift` přidej klíč do `PreferenceKeys`:
```swift
    public static let barWindowSource = "barWindowSource"
```
a property do `PreferencesStore`:
```swift
    public var barWindowSource: BarWindowSource {
        get { BarWindowSource(rawValue: defaults.string(forKey: PreferenceKeys.barWindowSource) ?? "") ?? .auto }
        nonmutating set { defaults.set(newValue.rawValue, forKey: PreferenceKeys.barWindowSource) }
    }
```

- [ ] **Step 7: Klíč `barsource.auto` do Kit `.strings`**

en.lproj (přidej k window.* klíčům):
```
"barsource.auto" = "Auto";
```
cs.lproj:
```
"barsource.auto" = "Auto";
```

- [ ] **Step 8: Run test — zelené**

Run: `swift test`
Expected: PASS (nové BarWindowSource testy + VŠECHNY existující `segments`/`MenuBarStyle` testy beze změny — default `.auto` = nearest).

- [ ] **Step 9: Commit**

```bash
git add Sources/StatusBarKit Tests/StatusBarKitTests/BarWindowSourceTests.swift
git commit -m "feat: BarWindowSource (Session/Weekly/Auto) + usedPercent(for:) + segments(source:)"
```

---

### Task 4: App — per-provider odkazy v kartě (zrušit globální blok)

**Files:**
- Modify: `Sources/StatusBarApp/PopoverView.swift`
- Modify: `Sources/StatusBarApp/Resources/en.lproj/Localizable.strings`, `cs.lproj/Localizable.strings`

**Interfaces:** žádné nové (App-interní). Ověření build + smoke.

- [ ] **Step 1: `PopoverView` — odstranit globální blok odkazů**

V `Sources/StatusBarApp/PopoverView.swift` ODSTRAŇ globální `VStack` se 4 `linkButton` (řádky mezi `if store.orderedUsages.isEmpty { Divider() }` a footer `HStack`). Po úpravě jde za empty-state Divider rovnou footer:

```swift
            if store.orderedUsages.isEmpty { Divider() }
            HStack {
                Button(String(localized: "popover.settings", bundle: .module), action: onOpenSettings).buttonStyle(.borderless).font(.caption)
                Spacer()
                Button(String(localized: "popover.quit", bundle: .module), action: onQuit).buttonStyle(.borderless).font(.caption)
            }.padding(.horizontal, 14).padding(.vertical, 8)
        }.frame(width: 320)
```

Také ODSTRAŇ nepoužitý `linkButton` helper z `PopoverView` (řádky 16–19) — přesune se do `ProviderCard` níže.

- [ ] **Step 2: `ProviderCard` — per-provider řádek odkazů**

V `ProviderCard` přidej `linksRow` za `monthRow` v obou větvích, kde se zobrazují data:

```swift
            switch usage.status {
            case .unavailable(let m): Text(m).font(.caption).foregroundStyle(.secondary)
            case .degraded(let m): Text(m).font(.caption2).foregroundStyle(.orange); windowsList; todayRow; monthRow; linksRow
            case .ok: windowsList; todayRow; monthRow; linksRow
            }
```

Přidej do `ProviderCard` (za `monthRow`):

```swift
    private var usageURL: String {
        usage.providerId == .claudeCode ? "https://claude.ai/settings/usage" : "https://platform.openai.com/usage"
    }
    private var statusURL: String {
        usage.providerId == .claudeCode ? "https://status.anthropic.com" : "https://status.openai.com"
    }
    private func linkButton(_ title: String, _ symbol: String, _ urlString: String) -> some View {
        Button { if let u = URL(string: urlString) { NSWorkspace.shared.open(u) } } label: {
            Label(title, systemImage: symbol)
        }.buttonStyle(.borderless).font(.caption)
    }
    @ViewBuilder private var linksRow: some View {
        HStack(spacing: 14) {
            linkButton(String(localized: "card.usage", bundle: .module), "chart.line.uptrend.xyaxis", usageURL)
            linkButton(String(localized: "card.status", bundle: .module), "waveform.path.ecg", statusURL)
            Spacer()
        }
    }
```

- [ ] **Step 3: App `.strings` — přidat card.*, odstranit popover.link.***

en.lproj: ODSTRAŇ `popover.link.anthropic`/`openai`/`usageClaude`/`usageOpenai`; přidej:
```
"card.usage" = "Usage";
"card.status" = "Status";
```
cs.lproj: ODSTRAŇ tytéž `popover.link.*`; přidej:
```
"card.usage" = "Usage";
"card.status" = "Stav";
```

- [ ] **Step 4: Build + smoke**

Run: `swift build 2>&1 | grep -i warning; swift test`
Expected: žádné warningy; 136/136 (Kit testy beze změny App).

- [ ] **Step 5: Commit**

```bash
git add Sources/StatusBarApp/PopoverView.swift Sources/StatusBarApp/Resources
git commit -m "feat: per-provider odkazy Usage/Status v kartě (zrušen globální blok)"
```

---

### Task 5: App — Nastavení reorganizace + picker okna + lišta source + verze 0.9.1

**Files:**
- Modify: `Sources/StatusBarApp/SettingsView.swift`
- Modify: `Sources/StatusBarApp/MenuBarController.swift:62-64` (segments + source)
- Modify: `Sources/StatusBarApp/Resources/en.lproj/Localizable.strings`, `cs.lproj/Localizable.strings` (`settings.general`, `settings.barWindow`)
- Modify: `Resources/Info.plist` (0.9.1)

**Interfaces:** Consumes `BarWindowSource`, `PreferenceKeys.barWindowSource`, `segments(source:)` (Task 3).

- [ ] **Step 1: `MenuBarController` — předat source do segments**

V `Sources/StatusBarApp/MenuBarController.swift` uprav volání `segments`:

```swift
        let segs = MenuBarTitleBuilder.segments(for: usages,
                                                style: prefs.barStyle,
                                                showUsedPercent: prefs.showUsedPercent,
                                                source: prefs.barWindowSource)
```

- [ ] **Step 2: `SettingsView` — sekce + picker okna**

V `Sources/StatusBarApp/SettingsView.swift` přidej `@AppStorage` (k ostatním):
```swift
    @AppStorage(PreferenceKeys.barWindowSource) private var barWindowSource: BarWindowSource = .auto
```

Zabal launch-at-login do sekce „Obecné" (přidej hlavičku) a do sekce „Lišta" přidej picker okna. V `body` nahraď SOUVISLÝ blok začínající řádkem `Text(String(localized: "settings.title", bundle: .module))...` a končící `Divider()`, který je TĚSNĚ PŘED `VStack` se sekcí `settings.alerts` (tento `Divider()` VČETNĚ), následujícím blokem. Sekce „Upozornění" (`settings.alerts` VStack) i patička s verzí ZŮSTÁVAJÍ beze změny POD vloženým blokem:

```swift
            Text(String(localized: "settings.title", bundle: .module)).font(.title3).fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "settings.general", bundle: .module)).font(.headline)
                Toggle(String(localized: "settings.launch", bundle: .module), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        LaunchAtLogin.setEnabled(on)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "settings.bar", bundle: .module)).font(.headline)
                HStack {
                    Text(String(localized: "settings.style", bundle: .module)).foregroundStyle(.secondary)
                    Picker("", selection: $barStyle) {
                        ForEach(MenuBarStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }.labelsHidden().frame(width: 160)
                    Spacer()
                }
                .onChange(of: barStyle) { _, _ in onAppearanceChanged() }
                HStack {
                    Text(String(localized: "settings.numberShows", bundle: .module)).foregroundStyle(.secondary)
                    Picker("", selection: $showUsedPercent) {
                        Text(String(localized: "settings.remaining", bundle: .module)).tag(false)
                        Text(String(localized: "settings.used", bundle: .module)).tag(true)
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 180)
                    Spacer()
                }
                .onChange(of: showUsedPercent) { _, _ in onAppearanceChanged() }
                HStack {
                    Text(String(localized: "settings.barWindow", bundle: .module)).foregroundStyle(.secondary)
                    Picker("", selection: $barWindowSource) {
                        ForEach(BarWindowSource.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }.labelsHidden().frame(width: 160)
                    Spacer()
                }
                .onChange(of: barWindowSource) { _, _ in onAppearanceChanged() }
            }

            Divider()
```

(Sekce „Upozornění" a patička verze ZŮSTÁVAJÍ beze změny pod tímto blokem.)

- [ ] **Step 3: App `.strings` — settings.general + settings.barWindow**

en.lproj (přidej k settings.* klíčům):
```
"settings.general" = "General";
"settings.barWindow" = "Menu bar window";
```
cs.lproj:
```
"settings.general" = "Obecné";
"settings.barWindow" = "Okno v liště";
```

- [ ] **Step 4: Verze 0.9.1**

V `Resources/Info.plist` změň `CFBundleShortVersionString` a `CFBundleVersion` z `0.9.0` na `0.9.1`.

- [ ] **Step 5: Build + smoke**

Run: `swift build 2>&1 | grep -i warning; swift test`
Expected: žádné warningy; 136/136.

Run: `bash scripts/make-app.sh`
Expected: `.app` 0.9.1 vytvořen (NESPOUŠTĚT GUI).

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusBarApp Resources/Info.plist
git commit -m "feat: Nastavení reorganizace + picker okna v liště (Session/Weekly/Auto), verze 0.9.1"
```

---

### Task 6: Lokalizace — úplnost klíčů + grep na vynechané/odstraněné

**Files:**
- Test: `Tests/StatusBarKitTests/LocalizationCompletenessTests.swift` (existující `kitKlíčeEnACsShodné` musí dál platit)

**Interfaces:** žádné. Pojistka konzistence po přidání/odebrání klíčů.

- [ ] **Step 1: Kit úplnost — existující test musí projít**

Run: `swift test`
Expected: `kitKlíčeEnACsShodné` PASS (Kit en/cs množiny shodné po změnách Task 2/3). Pokud FAIL → dorovnej chybějící klíč.

- [ ] **Step 2: App úplnost — grep porovná en/cs klíče**

Run:
```bash
cd /Users/martinpavlista/Projects/StatusBar
diff <(grep -oE '^"[^"]+"' Sources/StatusBarApp/Resources/en.lproj/Localizable.strings | sort) \
     <(grep -oE '^"[^"]+"' Sources/StatusBarApp/Resources/cs.lproj/Localizable.strings | sort)
```
Expected: prázdný výstup (en i cs App mají identickou množinu klíčů). Pokud rozdíl → dorovnej.

- [ ] **Step 3: Grep na ODSTRANĚNÉ klíče (nesmí už nikde být referencované)**

Run:
```bash
grep -rn "popover.link\.\|window\.5h\|window\.week\b\|window\.week\.scope" Sources/ || echo "OK — žádné odkazy na odstraněné klíče"
```
Expected: „OK …" (staré klíče nejsou v kódu ani `.strings`).

- [ ] **Step 4: Grep na vynechané české literály (F3 z v0.9c)**

Run:
```bash
grep -rn "Relace\|Týden\|Session\|Weekly\|Usage\|Status\|Obecné\|Okno v liště\|Spotřeba\|zbývá\|počítám\|Tempo\|Nastavení" Sources/StatusBarKit Sources/StatusBarApp
```
Expected: každý zásah je v KOMENTÁŘI nebo v `.strings`/`L10n` klíči (NE natvrdo v `Text(...)`/`NSLocalizedString` defaultu živého kódu). Pokud živý literál → doplň klíč.

- [ ] **Step 5: Finální smoke + commit (pokud byly opravy)**

Run: `swift build && swift test`
Expected: vše zelené (cílově ~136 testů).

```bash
git add -A
git commit -m "test: úplnost lokalizačních klíčů en↔cs po v0.9d (jen pokud byly změny)"
```
(Pokud nebyly žádné změny, commit vynech.)

---

## Verifikace plánu (self-review)

- **Spec coverage:** §1.1 perf → Task 1; §1.2 názvy → Task 2; §1.4 lišta-zdroj → Task 3 + Task 5 (wiring); §1.3 odkazy → Task 4; §1.5 Nastavení → Task 5; §3 lokalizace → průběžně + Task 6. Verze 0.9.1 → Task 5. R-OVĚŘENÍ paralelizace → Task 1 (plan-forge).
- **Typová konzistence:** `BarWindowSource` (auto/session/weekly), `usedPercent(for:)`, `segments(…source:)`, `barWindowSource` preference, `displayName(bundle:)`+`var displayName`, klíče `window.session`/`window.weekly`/`barsource.auto`/`card.usage`/`card.status`/`settings.general`/`settings.barWindow` — použity konzistentně napříč tasky.
- **Default `.auto`** zajišťuje nulovou regresi lišty (existující `MenuBarStyle`/`segments` testy beze změny).
- **Pořadí:** Task 2 (window.session/weekly klíče) PŘED Task 3 (BarWindowSource.displayName je reusuje) a Task 5 (picker). Task 1 nezávislý.
