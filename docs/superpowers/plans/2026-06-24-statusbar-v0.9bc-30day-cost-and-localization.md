# StatusBar v0.9b + v0.9c Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Přidat do popoveru 30denní reálnou cenu + měsíční projekci (off-main, throttlovaně) a poté lokalizovat celou aplikaci do en/cs.

**Architecture:** v0.9b — skenery dostanou `rangeUsage(start:end:)` (DRY refaktor sdílený s `todayUsage`); 30denní data tečou samostatným `CostHistoryStore` (Kit, `@MainActor ObservableObject`) s off-main `Task.detached` computem a throttle 6 h, mimo rychlou collector cestu. v0.9c — `defaultLocalization:"en"` + `Localizable.strings` (en base / cs) v OBOU targetech; Kit formattery dostanou injektovatelný `bundle: Bundle = .module` (default = Kit bundle) pro deterministické testy.

**Tech Stack:** Swift 6.0, SwiftPM (macOS 14+), Swift Testing (`@Test`/`#expect`), AppKit/SwiftUI.

## Global Constraints

- **Testy:** `swift test --filter <jméno>` NEMATCHUJE volné `@Test func` (bez typu/`@Suite`) → vždy spouštět **plný `swift test`**.
- **Swift 6 strict concurrency:** `static let` non-Sendable formatter NEJDE — formatter vytvářet lokálně; closures pro async compute musí být `@Sendable`, žádný `await` uvnitř zámku.
- **Bezpečnost (z projektu):** `~/.claude`/`~/.codex` JEN pro čtení; NIKDY nelogovat surový obsah konverzací (jen čísla). v této větvi se NEMĚNÍ žádný auth/credential/network kód.
- **Cena = reálná spotřeba:** vždy `PricingEstimator.estimateReal` (jen input+output, BEZ cache) — konzistentní s v0.8a.
- **NElokalizovat:** symbol `$` (USD odhad), názvy plánů (Max/Pro/Free/Team/Enterprise), názvy modelů, MenuBar `"—"` (univerzální), čistě numerické formáty bez slov (`"2h 14m"`, `"41m"`).
- **Default bundle pattern:** Kit formattery používají `bundle: Bundle = .module`; default `.module` se váže v místě DEFINICE (Kit) → App volá bez parametru a dostane Kit bundle; testy předávají `L10n.bundle("cs")`/`L10n.bundle("en")`.
- **Verze:** na konci v0.9b bumpnout `Resources/Info.plist` na **0.8.2** (`CFBundleShortVersionString` + `CFBundleVersion`).
- **Agent NESPOUŠTÍ GUI `.app`** — jen `swift build`/`swift test` (případně `scripts/make-app.sh` jako build-check); reálné spuštění dělá uživatel.

---

## Část A — v0.9b: 30denní cena + projekce (Tasky 1–5)

### Task 1: `PeriodCost` model + `CostProjection`

**Files:**
- Create: `Sources/StatusBarKit/Models/PeriodCost.swift`
- Create: `Sources/StatusBarKit/Pricing/CostProjection.swift`
- Test: `Tests/StatusBarKitTests/CostProjectionTests.swift`

**Interfaces:**
- Produces: `struct PeriodCost: Sendable, Equatable { let tokens: TokenUsage; let cost: Decimal; init(tokens:cost:) }`; `enum CostProjection { static func monthly(cost: Decimal, days: Double) -> Decimal; static func monthlyTokens(_ tokens: UInt, days: Double) -> UInt }`.
- Consumes: `TokenUsage` (existující).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/StatusBarKitTests/CostProjectionTests.swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func projekceMěsícCena() {
    // 300 / 30 dní = 10/den × 30.4 = 304
    #expect(CostProjection.monthly(cost: Decimal(300), days: 30) == Decimal(304))
    #expect(CostProjection.monthly(cost: 0, days: 30) == 0)
    #expect(CostProjection.monthly(cost: Decimal(100), days: 0) == 0)   // ochrana dělení nulou
}

@Test func projekceMěsícTokeny() {
    #expect(CostProjection.monthlyTokens(300, days: 30) == 304)
    #expect(CostProjection.monthlyTokens(0, days: 30) == 0)
    #expect(CostProjection.monthlyTokens(100, days: 0) == 0)
}

@Test func periodCostRovnost() {
    let a = PeriodCost(tokens: TokenUsage(input: 10, output: 20), cost: Decimal(5))
    let b = PeriodCost(tokens: TokenUsage(input: 10, output: 20), cost: Decimal(5))
    #expect(a == b)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test`
Expected: FAIL — „cannot find 'CostProjection'/'PeriodCost' in scope".

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/StatusBarKit/Models/PeriodCost.swift
import Foundation

/// Souhrn ceny + tokenů za období (display vrstva pro 30denní cenu).
public struct PeriodCost: Sendable, Equatable {
    public let tokens: TokenUsage
    public let cost: Decimal
    public init(tokens: TokenUsage, cost: Decimal) {
        self.tokens = tokens; self.cost = cost
    }
}
```

```swift
// Sources/StatusBarKit/Pricing/CostProjection.swift
import Foundation

/// Extrapolace na měsíc z období (denní průměr × 30.4). Pure.
public enum CostProjection {
    public static func monthly(cost: Decimal, days: Double) -> Decimal {
        guard days > 0 else { return 0 }
        // přesné: cost × 304 / (days × 10) = cost/days × 30.4 (bez Double→Decimal nepřesnosti)
        return cost * Decimal(304) / (Decimal(days) * 10)
    }
    public static func monthlyTokens(_ tokens: UInt, days: Double) -> UInt {
        guard days > 0 else { return 0 }
        return UInt((Double(tokens) / days * 30.4).rounded())
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test`
Expected: PASS (všechny dosavadní + 3 nové).

- [ ] **Step 5: Commit**

```bash
git add Sources/StatusBarKit/Models/PeriodCost.swift Sources/StatusBarKit/Pricing/CostProjection.swift Tests/StatusBarKitTests/CostProjectionTests.swift
git commit -m "feat: PeriodCost model + CostProjection (měsíční extrapolace)"
```

---

### Task 2: `ClaudeTokenScanner.rangeUsage` (DRY refaktor)

**Files:**
- Modify: `Sources/StatusBarKit/Providers/ClaudeTokenScanner.swift`
- Test: `Tests/StatusBarKitTests/ClaudeTokenScannerTests.swift` (přidat testy)

**Interfaces:**
- Produces: `func rangeUsage(start: Date, end: Date) -> TodayUsage?` na `ClaudeTokenScanner`. `todayUsage(now:calendar:)` zůstává a deleguje na `rangeUsage`.
- Consumes: `ClaudeTokenParser.sumByModel(fromJSONL:dayStart:dayEnd:)`, `PricingEstimator.estimateReal`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/StatusBarKitTests/ClaudeTokenScannerTests.swift — PŘIDAT na konec souboru
@Test func claudeRangeUsageSečteVíceDnů() throws {
    let cal = Calendar.current
    var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 20; c.hour = 12
    let day20 = cal.date(from: c)!
    let day10 = cal.date(byAdding: .day, value: -10, to: day20)!   // v rozsahu
    let day40 = cal.date(byAdding: .day, value: -40, to: day20)!   // mimo rozsah (>30 dní)
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("claudeRange-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    // soubor v rozsahu (mtime = day10, řádky day10)
    let f1 = tmp.appendingPathComponent("a.jsonl")
    try """
    {"type":"assistant","timestamp":"\(iso.string(from: day10))","message":{"model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":9999}}}
    """.data(using: .utf8)!.write(to: f1)
    try FileManager.default.setAttributes([.modificationDate: day10], ofItemAtPath: f1.path)

    // soubor mimo rozsah (mtime = day40) — nesmí se započítat (mtime < start)
    let f2 = tmp.appendingPathComponent("b.jsonl")
    try """
    {"type":"assistant","timestamp":"\(iso.string(from: day40))","message":{"model":"claude-opus-4-8","usage":{"input_tokens":777,"output_tokens":777,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
    """.data(using: .utf8)!.write(to: f2)
    try FileManager.default.setAttributes([.modificationDate: day40], ofItemAtPath: f2.path)

    let start = cal.date(byAdding: .day, value: -30, to: day20)!
    let r = try #require(ClaudeTokenScanner(projectsDir: tmp).rangeUsage(start: start, end: day20))
    #expect(r.total.realTokens == 150)            // jen f1 (100+50); f2 mimo rozsah; cache se do realTokens nepočítá
    #expect(r.estimatedCost > 0)
}

@Test func claudeRangeUsageFiltrujeŘádkyMimoOkno() throws {
    // soubor má mtime v rozsahu, ale obsahuje řádek STARŠÍ než start → parser ho odfiltruje
    let cal = Calendar.current
    var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 20; c.hour = 12
    let day20 = cal.date(from: c)!
    let start = cal.date(byAdding: .day, value: -30, to: day20)!
    let inWindow = cal.date(byAdding: .day, value: -5, to: day20)!
    let beforeWindow = cal.date(byAdding: .day, value: -35, to: day20)!
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("claudeRange2-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let f = tmp.appendingPathComponent("a.jsonl")
    try """
    {"type":"assistant","timestamp":"\(iso.string(from: inWindow))","message":{"model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
    {"type":"assistant","timestamp":"\(iso.string(from: beforeWindow))","message":{"model":"claude-opus-4-8","usage":{"input_tokens":555,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
    """.data(using: .utf8)!.write(to: f)
    try FileManager.default.setAttributes([.modificationDate: inWindow], ofItemAtPath: f.path)

    let r = try #require(ClaudeTokenScanner(projectsDir: tmp).rangeUsage(start: start, end: day20))
    #expect(r.total.realTokens == 100)            // řádek beforeWindow (555) odfiltrován parserem
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test`
Expected: FAIL — „value of type 'ClaudeTokenScanner' has no member 'rangeUsage'".

- [ ] **Step 3: Write minimal implementation**

Nahraď celý obsah `Sources/StatusBarKit/Providers/ClaudeTokenScanner.swift`:

```swift
import Foundation

public struct ClaudeTokenScanner: Sendable {
    private let projectsDir: URL
    public init(projectsDir: URL? = nil) {
        self.projectsDir = projectsDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    /// Sečte dnešní tokeny per model. Vrátí nil, pokud nic dnešního není.
    public func todayUsage(now: Date, calendar: Calendar = .current) -> TodayUsage? {
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        return rangeUsage(start: dayStart, end: dayEnd)
    }

    /// Sečte tokeny per model v rozsahu [start, end). Vrátí nil, pokud nic.
    /// Čte JEN soubory s mtime ≥ start; parser dál filtruje řádky podle timestampu do [start, end).
    public func rangeUsage(start: Date, end: Date) -> TodayUsage? {
        var byModel: [String: TokenUsage] = [:]
        if let en = FileManager.default.enumerator(at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let url as URL in en where url.pathExtension == "jsonl" {
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                guard let mod, mod >= start else { continue }   // soubory upravené v rozsahu
                guard let data = try? Data(contentsOf: url) else { continue }
                for (model, usage) in ClaudeTokenParser.sumByModel(fromJSONL: data, dayStart: start, dayEnd: end) {
                    byModel[model, default: .zero] = (byModel[model] ?? .zero) + usage
                }
            }
        }
        // Vyhoď modely s 0 tokeny (např. "<synthetic>") — nepatří do rozpadu ani součtu.
        let perModel = byModel
            .filter { $0.value.totalTokens > 0 }
            .map { ModelTokens(modelName: $0.key, tokens: $0.value) }
            .sorted { $0.modelName < $1.modelName }
        guard !perModel.isEmpty else { return nil }
        return TodayUsage(perModel: perModel, estimatedCost: PricingEstimator.estimateReal(perModel))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test`
Expected: PASS — nové testy + původní `claudeScannerJenDnešní…`/`claudeScannerVyhodíNulové…` (todayUsage deleguje, beze změny chování).

- [ ] **Step 5: Commit**

```bash
git add Sources/StatusBarKit/Providers/ClaudeTokenScanner.swift Tests/StatusBarKitTests/ClaudeTokenScannerTests.swift
git commit -m "feat: ClaudeTokenScanner.rangeUsage (DRY refaktor s todayUsage)"
```

---

### Task 3: `CodexTokenScanner.rangeUsage`

**Files:**
- Modify: `Sources/StatusBarKit/Providers/CodexTokenScanner.swift`
- Test: `Tests/StatusBarKitTests/CodexTokenScannerTests.swift` (přidat testy)

**Interfaces:**
- Produces: `func rangeUsage(start: Date, end: Date) -> TodayUsage?` na `CodexTokenScanner`. `todayUsage(now:calendar:)` zůstává a deleguje. `init(sessionsDir:maxFilesToScan:)` beze změny (30denní scanner se konstruuje s `maxFilesToScan: .max`).
- Consumes: `CodexTokenParser.lastTotal(fromJSONL:)`, `PricingEstimator.estimateReal`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/StatusBarKitTests/CodexTokenScannerTests.swift — PŘIDAT na konec souboru
@Test func codexRangeUsageSečteSoubotyVRozsahu() throws {
    let cal = Calendar.current
    var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 20; c.hour = 12
    let day20 = cal.date(from: c)!
    let day10 = cal.date(byAdding: .day, value: -10, to: day20)!   // v rozsahu
    let day40 = cal.date(byAdding: .day, value: -40, to: day20)!   // mimo (>30 dní)

    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("codexRange-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    func write(_ name: String, mtime: Date, input: Int, output: Int) throws {
        let f = tmp.appendingPathComponent(name)
        try """
        {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":0,"output_tokens":\(output),"reasoning_output_tokens":0}}}}
        """.data(using: .utf8)!.write(to: f)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: f.path)
    }
    try write("a.jsonl", mtime: day10, input: 100, output: 50)   // v rozsahu
    try write("b.jsonl", mtime: day40, input: 999, output: 999)  // mimo rozsah

    let start = cal.date(byAdding: .day, value: -30, to: day20)!
    let r = try #require(CodexTokenScanner(sessionsDir: tmp).rangeUsage(start: start, end: day20))
    #expect(r.total.realTokens == 150)            // jen a.jsonl (100+50)
    #expect(r.perModel.first?.modelName == "codex")
}

@Test func codexRangeUsagePrázdnýRozsahNil() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("codexRangeEmpty-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(CodexTokenScanner(sessionsDir: tmp).rangeUsage(start: now.addingTimeInterval(-30*86400), end: now) == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test`
Expected: FAIL — „value of type 'CodexTokenScanner' has no member 'rangeUsage'".

- [ ] **Step 3: Write minimal implementation**

Nahraď celý obsah `Sources/StatusBarKit/Providers/CodexTokenScanner.swift`:

```swift
import Foundation

public struct CodexTokenScanner: Sendable {
    private let sessionsDir: URL
    private let maxFilesToScan: Int
    public init(sessionsDir: URL? = nil, maxFilesToScan: Int = 50) {
        self.sessionsDir = sessionsDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        self.maxFilesToScan = maxFilesToScan
    }

    /// Sečte dnešní Codex tokeny (finální total per dnešní soubor). Nil, pokud nic.
    public func todayUsage(now: Date, calendar: Calendar = .current) -> TodayUsage? {
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        return rangeUsage(start: dayStart, end: dayEnd)
    }

    /// Sečte Codex tokeny přes session soubory s mtime v [start, end). Finální `lastTotal` per soubor.
    /// POZN. (R5, akceptováno): kumulativní total → session přes hranici okna přičte i tokeny mimo rozsah.
    public func rangeUsage(start: Date, end: Date) -> TodayUsage? {
        var sum = TokenUsage.zero
        var any = false
        guard let en = FileManager.default.enumerator(at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        var files: [(URL, Date)] = []
        for case let url as URL in en where url.pathExtension == "jsonl" {
            if let m = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               m >= start, m < end {
                files.append((url, m))
            }
        }
        for (url, _) in files.sorted(by: { $0.1 > $1.1 }).prefix(maxFilesToScan) {
            guard let data = try? Data(contentsOf: url),
                  let t = CodexTokenParser.lastTotal(fromJSONL: data) else { continue }
            sum = sum + t; any = true
        }
        guard any else { return nil }
        let perModel = [ModelTokens(modelName: "codex", tokens: sum)]
        return TodayUsage(perModel: perModel, estimatedCost: PricingEstimator.estimateReal(perModel))
    }
}
```

> POZN. k refaktoru: `todayUsage` nově přidává horní mez `m < end` (= zítřek). Soubory nemají budoucí mtime → chování „dnes" beze změny. Ověř plným `swift test` (existující Codex today testy musí projít).

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test`
Expected: PASS — nové testy + původní Codex today testy.

- [ ] **Step 5: Commit**

```bash
git add Sources/StatusBarKit/Providers/CodexTokenScanner.swift Tests/StatusBarKitTests/CodexTokenScannerTests.swift
git commit -m "feat: CodexTokenScanner.rangeUsage (mtime rozsah, sdílí s todayUsage)"
```

---

### Task 4: `CostHistoryStore` (throttle + off-main + published)

**Files:**
- Create: `Sources/StatusBarKit/Store/CostHistoryStore.swift`
- Test: `Tests/StatusBarKitTests/CostHistoryStoreTests.swift`

**Interfaces:**
- Consumes: `PeriodCost` (Task 1), `ProviderID`.
- Produces: `@MainActor final class CostHistoryStore: ObservableObject` s `@Published private(set) var history: [ProviderID: PeriodCost]`, `@Published private(set) var isComputing: Bool`, `private(set) var lastComputed: Date?`; `init(staleInterval: TimeInterval = 6*3600, provider: @escaping @Sendable (Date) async -> [ProviderID: PeriodCost])`; `func shouldRefresh(now: Date) -> Bool`; `func refresh(now: Date) async`; `func refreshIfStale(now: Date = Date())`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/StatusBarKitTests/CostHistoryStoreTests.swift
import Testing
import Foundation
@testable import StatusBarKit

private let t0 = Date(timeIntervalSince1970: 1_000_000)

@MainActor @Test func costHistoryNaplníHistoriiAUkončíPočítání() async {
    let store = CostHistoryStore(staleInterval: 3600, provider: { _ in
        [.claudeCode: PeriodCost(tokens: TokenUsage(input: 1000, output: 500), cost: Decimal(5))]
    })
    await store.refresh(now: t0)
    #expect(store.history[.claudeCode]?.cost == Decimal(5))
    #expect(store.history[.claudeCode]?.tokens.realTokens == 1500)
    #expect(store.isComputing == false)
    #expect(store.lastComputed == t0)
}

@MainActor @Test func costHistoryThrottle() async {
    let store = CostHistoryStore(staleInterval: 3600, provider: { _ in [:] })
    #expect(store.shouldRefresh(now: t0) == true)                              // nikdy nepočítáno
    await store.refresh(now: t0)
    #expect(store.shouldRefresh(now: t0.addingTimeInterval(1800)) == false)    // čerstvé (< 1h)
    #expect(store.shouldRefresh(now: t0.addingTimeInterval(3700)) == true)     // zatuchlé (> 1h)
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func bump() { lock.withLock { n += 1 } }
    var value: Int { lock.withLock { n } }
}

@MainActor @Test func costHistoryThrottleZabráníDruhémuComputeu() async {
    let counter = Counter()
    let store = CostHistoryStore(staleInterval: 3600, provider: { _ in counter.bump(); return [:] })
    await store.refresh(now: t0)
    await store.refresh(now: t0.addingTimeInterval(60))     // čerstvé → no-op (guard shouldRefresh)
    #expect(counter.value == 1)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test`
Expected: FAIL — „cannot find 'CostHistoryStore' in scope".

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/StatusBarKit/Store/CostHistoryStore.swift
import Foundation
import Combine

/// Drží 30denní cenu per provider. Compute běží přes injektovaný async provider
/// (v appce off-main přes Task.detached), throttlovaně (staleInterval). MIMO rychlou collector cestu.
@MainActor
public final class CostHistoryStore: ObservableObject {
    @Published public private(set) var history: [ProviderID: PeriodCost] = [:]
    @Published public private(set) var isComputing = false
    public private(set) var lastComputed: Date?

    private let staleInterval: TimeInterval
    private let provider: @Sendable (Date) async -> [ProviderID: PeriodCost]

    public init(staleInterval: TimeInterval = 6 * 3600,
                provider: @escaping @Sendable (Date) async -> [ProviderID: PeriodCost]) {
        self.staleInterval = staleInterval
        self.provider = provider
    }

    /// Throttle: nepočítat když právě počítá nebo když je poslední výpočet čerstvý.
    public func shouldRefresh(now: Date) -> Bool {
        guard !isComputing else { return false }
        if let last = lastComputed, now.timeIntervalSince(last) < staleInterval { return false }
        return true
    }

    /// Awaitable výpočet (pro testy i interně). Respektuje throttle.
    public func refresh(now: Date) async {
        guard shouldRefresh(now: now) else { return }
        isComputing = true
        let h = await provider(now)
        history = h
        lastComputed = now
        isComputing = false
    }

    /// Fire-and-forget pro app (start / popover-open).
    public func refreshIfStale(now: Date = Date()) {
        Task { await refresh(now: now) }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test`
Expected: PASS (všechny + 3 nové).

- [ ] **Step 5: Commit**

```bash
git add Sources/StatusBarKit/Store/CostHistoryStore.swift Tests/StatusBarKitTests/CostHistoryStoreTests.swift
git commit -m "feat: CostHistoryStore (throttle + off-main async + published 30denní cena)"
```

---

### Task 5: App wiring + PopoverView 30denní řádek + verze 0.8.2

**Files:**
- Modify: `Sources/StatusBarApp/AppDelegate.swift`
- Modify: `Sources/StatusBarApp/MenuBarController.swift:16-37` (přidat `costHistory` do init + PopoverView)
- Modify: `Sources/StatusBarApp/PopoverView.swift`
- Modify: `Resources/Info.plist` (verze 0.8.2)

**Interfaces:**
- Consumes: `CostHistoryStore`, `PeriodCost`, `CostProjection` (Tasky 1,4), `ClaudeTokenScanner.rangeUsage`/`CodexTokenScanner.rangeUsage` (Tasky 2,3).
- Produces: nic pro pozdější tasky (koncový App task v0.9b).

Toto je App-integrační task — ověření je **build + smoke** (`swift build`, volitelně `scripts/make-app.sh` jako build-check). GUI NESPOUŠTĚT.

- [ ] **Step 1: `PopoverView` — přidat 30denní řádek**

V `Sources/StatusBarApp/PopoverView.swift`:

(a) Do `PopoverView` přidej observovaný store a předej ho kartám. Změň hlavičku struktu a `ForEach`:

```swift
struct PopoverView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var costHistory: CostHistoryStore
    let onRefresh: () -> Void
    let onQuit: () -> Void
    var onOpenSettings: () -> Void = {}
```

V `body` nahraď řádek `ForEach(...)`:

```swift
                ForEach(store.orderedUsages, id: \.providerId) {
                    ProviderCard(usage: $0,
                                 period: costHistory.history[$0.providerId],
                                 isComputingPeriod: costHistory.isComputing)
                    Divider()
                }
```

(b) Do `ProviderCard` přidej properties a 30denní řádek. Změň hlavičku:

```swift
private struct ProviderCard: View {
    let usage: ProviderUsage
    var period: PeriodCost? = nil
    var isComputingPeriod: Bool = false
```

V `body` přidej `monthRow` za `todayRow` v obou větvích, kde se zobrazuje today:

```swift
            switch usage.status {
            case .unavailable(let m): Text(m).font(.caption).foregroundStyle(.secondary)
            case .degraded(let m): Text(m).font(.caption2).foregroundStyle(.orange); windowsList; todayRow; monthRow
            case .ok: windowsList; todayRow; monthRow
            }
```

Přidej nový `@ViewBuilder` (za `todayRow`):

```swift
    @ViewBuilder private var monthRow: some View {
        if let p = period {
            HStack {
                Text("30 dní").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(TokenFormatter.compact(p.tokens.realTokens)) tok ≈ \(TokenFormatter.money(p.cost))")
                    .font(.caption).fontWeight(.medium)
            }
            Text("≈ \(TokenFormatter.money(CostProjection.monthly(cost: p.cost, days: 30)))/měs")
                .font(.caption2).foregroundStyle(.tertiary)
        } else if isComputingPeriod {
            Text("30 dní: počítám…").font(.caption2).foregroundStyle(.tertiary)
        }
    }
```

- [ ] **Step 2: `MenuBarController` — protáhnout `costHistory` do PopoverView**

V `Sources/StatusBarApp/MenuBarController.swift` uprav `init` (přidej parametr a předej do `PopoverView`):

```swift
    init(store: UsageStore, costHistory: CostHistoryStore, prefs: PreferencesStore, onClick: @escaping () -> Void,
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
            PopoverView(store: store, costHistory: costHistory, onRefresh: onClick, onQuit: { NSApp.terminate(nil) },
                        onOpenSettings: onOpenSettings))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
    }
```

- [ ] **Step 3: `AppDelegate` — zkonstruovat `CostHistoryStore` + triggery**

V `Sources/StatusBarApp/AppDelegate.swift` přidej property a wiring:

```swift
    private let store = UsageStore()
    private let costHistory: CostHistoryStore
    private let prefs = PreferencesStore()
```

Přidej `override init()` (nebo nech default a inicializuj `costHistory` v `applicationDidFinishLaunching` jako `var`; preferuj stored let s init). Vlož inicializátor:

```swift
    override init() {
        let claudeScanner = ClaudeTokenScanner()
        let codexScanner = CodexTokenScanner(maxFilesToScan: .max)   // 30denní: bez stropu (off-main, throttle)
        costHistory = CostHistoryStore(provider: { now in
            let start = now.addingTimeInterval(-30 * 86400)
            return await Task.detached(priority: .utility) {
                var out: [ProviderID: PeriodCost] = [:]
                if let c = claudeScanner.rangeUsage(start: start, end: now) {
                    out[.claudeCode] = PeriodCost(tokens: c.total, cost: c.estimatedCost)
                }
                if let x = codexScanner.rangeUsage(start: start, end: now) {
                    out[.codex] = PeriodCost(tokens: x.total, cost: x.estimatedCost)
                }
                return out
            }.value
        })
        super.init()
    }
```

V `applicationDidFinishLaunching` uprav konstrukci `menuBar` (předej `costHistory`), přidej trigger na popover-open i start:

```swift
        menuBar = MenuBarController(store: store, costHistory: costHistory, prefs: prefs, onClick: { [weak self] in
            guard let self else { return }
            Task { await self.coordinator.refreshNow(includeToday: true) }   // today (rychlé)
            self.costHistory.refreshIfStale()                                 // 30 dní (throttle 6h, off-main)
        }, onOpenSettings: { [weak self] in
            self?.settings.show()
        })
        Task { await coordinator.refreshNow(includeToday: false) }            // start: jen limity
        costHistory.refreshIfStale()                                          // start: nachystej 30denní data
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.coordinator.refreshNow(includeToday: false) }   // 60s: jen limity — 30denní cenu NEVOLÁ
        }
```

> POZN.: 60s timer **nikdy** nevolá `costHistory.refreshIfStale()` — 30denní sken jen start + popover-open (throttle 6h).

- [ ] **Step 4: Verze 0.8.2**

V `Resources/Info.plist` změň `CFBundleShortVersionString` a `CFBundleVersion` z `0.8.1` na `0.8.2`.

- [ ] **Step 5: Build + smoke**

Run: `swift build`
Expected: BUILD úspěšný, žádné warningy concurrency.

Run: `swift test`
Expected: PASS (Kit testy nezměněny touto App změnou).

(Volitelný build-check bundle, BEZ spuštění GUI:)
Run: `bash scripts/make-app.sh`
Expected: vytvoří `.app` bez chyby. **NESPOUŠTĚT** — restart lišty dělá uživatel.

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusBarApp/PopoverView.swift Sources/StatusBarApp/MenuBarController.swift Sources/StatusBarApp/AppDelegate.swift Resources/Info.plist
git commit -m "feat: 30denní cena+projekce v popoveru (off-main CostHistoryStore), verze 0.8.2"
```

---

## Část B — v0.9c: lokalizace en/cs (Tasky 6–9)

> **R-OVĚŘENÍ (plan-forge):** SwiftPM `.lproj` pipeline (build/test/runtime) + test-time bundle injekce se empiricky ověří PŘED napsáním všech klíčů. Task 6 je canary; pokud selže, plan-forge rozhodne o fallbacku (`.xcstrings` / en-only testy) ještě před Tasky 7–9.

### Task 6: SwiftPM lokalizační scaffolding + canary pipeline test

**Files:**
- Modify: `Package.swift`
- Create: `Sources/StatusBarKit/Resources/en.lproj/Localizable.strings`
- Create: `Sources/StatusBarKit/Resources/cs.lproj/Localizable.strings`
- Create: `Sources/StatusBarApp/Resources/en.lproj/Localizable.strings`
- Create: `Sources/StatusBarApp/Resources/cs.lproj/Localizable.strings`
- Create: `Sources/StatusBarKit/Localization/L10n.swift`
- Test: `Tests/StatusBarKitTests/LocalizationPipelineTests.swift`

**Interfaces:**
- Produces: `enum L10n { static func bundle(_ code: String) -> Bundle }` (vrací jazykově specifický `.lproj` bundle z Kit `.module`, fallback `.module`).

- [ ] **Step 1: Vytvoř canary `.strings` (Kit, oba jazyky)**

`Sources/StatusBarKit/Resources/en.lproj/Localizable.strings`:
```
"test.ping" = "pong-en";
```
`Sources/StatusBarKit/Resources/cs.lproj/Localizable.strings`:
```
"test.ping" = "pong-cs";
```

`Sources/StatusBarApp/Resources/en.lproj/Localizable.strings`:
```
"test.ping" = "app-pong-en";
```
`Sources/StatusBarApp/Resources/cs.lproj/Localizable.strings`:
```
"test.ping" = "app-pong-cs";
```

- [ ] **Step 2: `Package.swift` — defaultLocalization + resources**

Nahraď `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatusBar",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "StatusBarKit",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "StatusBarApp",
            dependencies: ["StatusBarKit"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "StatusBarKitTests",
            dependencies: ["StatusBarKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

- [ ] **Step 3: `L10n.bundle` helper**

```swift
// Sources/StatusBarKit/Localization/L10n.swift
import Foundation

/// Lokalizační pomocník. `bundle(_:)` vrací jazykově specifický .lproj bundle z Kit modulu
/// (pro deterministické testy); při neúspěchu vrací .module.
public enum L10n {
    public static func bundle(_ code: String) -> Bundle {
        guard let url = Bundle.module.url(forResource: code, withExtension: "lproj"),
              let b = Bundle(url: url) else { return .module }
        return b
    }
}
```

- [ ] **Step 4: Canary test (round-trip)**

```swift
// Tests/StatusBarKitTests/LocalizationPipelineTests.swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func lokalizacePipelineKitFunguje() {
    let cs = L10n.bundle("cs")
    let en = L10n.bundle("en")
    #expect(NSLocalizedString("test.ping", bundle: cs, comment: "") == "pong-cs")
    #expect(NSLocalizedString("test.ping", bundle: en, comment: "") == "pong-en")
}
```

- [ ] **Step 5: Run test — OVĚŘ pipeline**

Run: `swift build`
Expected: BUILD OK (resources zpracovány, `Bundle.module` vygenerován pro Kit i App).

Run: `swift test`
Expected: PASS včetně `lokalizacePipelineKitFunguje`.

> **KILL/GATE:** Pokud canary FAILuje (klíč se nepřeloží / `Bundle.module` nenalezne `.lproj`), NEPOKRAČUJ na Task 7 — eskaluj orchestrátorovi (plan-forge fallback: `.xcstrings`, nebo en-only asserce). Tohle je celý smysl Tasku 6.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/StatusBarKit/Resources Sources/StatusBarApp/Resources Sources/StatusBarKit/Localization/L10n.swift Tests/StatusBarKitTests/LocalizationPipelineTests.swift
git commit -m "feat: SwiftPM lokalizační scaffolding (en/cs .lproj) + canary pipeline test"
```

---

### Task 7: Lokalizace Kit formatterů

**Files:**
- Modify: `Sources/StatusBarKit/Formatting/RelativeTimeFormatter.swift`
- Modify: `Sources/StatusBarKit/Providers/Pace.swift`
- Modify: `Sources/StatusBarKit/Formatting/Formatting.swift` (ResetFormatter, WindowLabel)
- Modify: `Sources/StatusBarKit/Formatting/MenuBarStyle.swift`
- Modify: `Sources/StatusBarKit/Providers/ClaudeCodeCollector.swift` (3 hlášky)
- Modify: `Sources/StatusBarKit/Providers/CodexCollector.swift` (3 hlášky)
- Modify: `Sources/StatusBarKit/Resources/en.lproj/Localizable.strings`, `cs.lproj/Localizable.strings`
- Test: `Tests/StatusBarKitTests/RelativeTimeFormatterTests.swift`, `PaceTests.swift`, `FormattingTests.swift`, `MenuBarStyleTests.swift` (upravit exact-text asserce na injektovaný bundle)

**Interfaces:**
- Produces (změny signatur): `RelativeTimeFormatter.string(from:now:bundle: Bundle = .module)`, `PaceLabel.text(deltaPercent:bundle: Bundle = .module)`, `ResetFormatter.short(until:now:bundle: Bundle = .module)`, `WindowLabel.text(for:bundle: Bundle = .module)`, `MenuBarStyle.displayName(bundle: Bundle = .module) -> String` + `var displayName: String { displayName() }`.
- Consumes: `L10n` (Task 6) — jen v testech.

> **Pozn. k testovatelnosti:** App call-sites volají BEZ `bundle:` → dostanou Kit `.module` (default vázán v Kitu). Collectory (`ClaudeCodeCollector`/`CodexCollector`) používají `NSLocalizedString(key, bundle: .module, comment:)` přímo — jejich testy asertují jen `case` statusu (ne text), takže se NEMĚNÍ. `WindowLabel.text` volá i `AlertEvaluator` bez bundle → notifikace lokalizované; `AlertEvaluatorTests` text neasertují.

- [ ] **Step 1: Uprav exact-text testy na injektovaný bundle (NEJDŘÍV — musí failnout)**

`Tests/StatusBarKitTests/RelativeTimeFormatterTests.swift` — nahraď celý:

```swift
import Testing
import Foundation
@testable import StatusBarKit

private let now = Date(timeIntervalSince1970: 1_000_000)
private let cs = L10n.bundle("cs")
private let en = L10n.bundle("en")

@Test func relČasPrávěTeď() {
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-30), now: now, bundle: cs) == "právě teď")
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-30), now: now, bundle: en) == "just now")
}
@Test func relČasMinuty() {
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-5*60), now: now, bundle: cs) == "před 5 min")
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-5*60), now: now, bundle: en) == "5 min ago")
}
@Test func relČasHodiny() {
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-2*3600), now: now, bundle: cs) == "před 2 h")
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-2*3600), now: now, bundle: en) == "2 h ago")
}
@Test func relČasDny() {
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-3*86400), now: now, bundle: cs) == "před 3 d")
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-3*86400), now: now, bundle: en) == "3 d ago")
}
```

`Tests/StatusBarKitTests/PaceTests.swift` — nahraď jen `paceLabelTexty`:

```swift
@Test func paceLabelTexty() {
    let cs = L10n.bundle("cs"); let en = L10n.bundle("en")
    #expect(PaceLabel.text(deltaPercent: 20, bundle: cs) == "napřed o 20 %")
    #expect(PaceLabel.text(deltaPercent: -42, bundle: cs) == "pozadu o 42 %")
    #expect(PaceLabel.text(deltaPercent: 0, bundle: cs) == "v tempu")
    #expect(PaceLabel.text(deltaPercent: 20, bundle: en) == "20 % ahead")
    #expect(PaceLabel.text(deltaPercent: -42, bundle: en) == "42 % behind")
    #expect(PaceLabel.text(deltaPercent: 0, bundle: en) == "on pace")
}
```

`Tests/StatusBarKitTests/FormattingTests.swift` — nahraď `resetFormat` a `popiskyOken`:

```swift
@Test func resetFormat() {
    let now = Date(timeIntervalSince1970: 0)
    let cs = L10n.bundle("cs"); let en = L10n.bundle("en")
    #expect(ResetFormatter.short(until: Date(timeIntervalSince1970: 2*3600+14*60), now: now) == "2h 14m")  // numerický, beze slov
    #expect(ResetFormatter.short(until: Date(timeIntervalSince1970: 41*60), now: now) == "41m")
    #expect(ResetFormatter.short(until: Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 100), bundle: cs) == "teď")
    #expect(ResetFormatter.short(until: Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 100), bundle: en) == "now")
}

@Test func popiskyOken() {
    let cs = L10n.bundle("cs"); let en = L10n.bundle("en")
    #expect(WindowLabel.text(for: .rolling5h, bundle: cs) == "5h okno")
    #expect(WindowLabel.text(for: .weekly(scope: nil), bundle: cs) == "Týden")
    #expect(WindowLabel.text(for: .weekly(scope: "Sonnet"), bundle: cs) == "Týden · Sonnet")
    #expect(WindowLabel.text(for: .rolling5h, bundle: en) == "5h window")
    #expect(WindowLabel.text(for: .weekly(scope: nil), bundle: en) == "Week")
    #expect(WindowLabel.text(for: .weekly(scope: "Sonnet"), bundle: en) == "Week · Sonnet")
}
```

`Tests/StatusBarKitTests/MenuBarStyleTests.swift` — nahraď jen řádky 84–85 v `menuBarStyleRawValueAFallback`:

```swift
    let cs = L10n.bundle("cs"); let en = L10n.bundle("en")
    #expect(MenuBarStyle.dotPercent.displayName(bundle: cs) == "Tečka + %")
    #expect(MenuBarStyle.worst.displayName(bundle: cs) == "Nejkritičtější")
    #expect(MenuBarStyle.dotPercent.displayName(bundle: en) == "Dot + %")
    #expect(MenuBarStyle.worst.displayName(bundle: en) == "Most critical")
```

- [ ] **Step 2: Run — ověř že testy failují (signatury/klíče)**

Run: `swift test`
Expected: FAIL — chybí `bundle:` overloady + klíče.

- [ ] **Step 3: Lokalizuj formattery**

`Sources/StatusBarKit/Formatting/RelativeTimeFormatter.swift`:
```swift
import Foundation

/// Relativní čas „před X". Lokalizováno (en base / cs).
public enum RelativeTimeFormatter {
    public static func string(from date: Date, now: Date, bundle: Bundle = .module) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return NSLocalizedString("reltime.now", bundle: bundle, comment: "just now") }
        let m = s / 60
        if m < 60 { return String(format: NSLocalizedString("reltime.min", bundle: bundle, comment: "X minutes ago"), m) }
        let h = s / 3600
        if h < 24 { return String(format: NSLocalizedString("reltime.hour", bundle: bundle, comment: "X hours ago"), h) }
        return String(format: NSLocalizedString("reltime.day", bundle: bundle, comment: "X days ago"), s / 86400)
    }
}
```

`Sources/StatusBarKit/Providers/Pace.swift` — `PaceLabel` (PaceCalculator beze změny):
```swift
/// Lidský popisek pace. Lokalizováno.
public enum PaceLabel {
    public static func text(deltaPercent d: Int, bundle: Bundle = .module) -> String {
        if d > 0 { return String(format: NSLocalizedString("pace.ahead", bundle: bundle, comment: "X % ahead"), d) }
        if d < 0 { return String(format: NSLocalizedString("pace.behind", bundle: bundle, comment: "X % behind"), -d) }
        return NSLocalizedString("pace.onpace", bundle: bundle, comment: "on pace")
    }
}
```

`Sources/StatusBarKit/Formatting/Formatting.swift` — uprav `ResetFormatter` a `WindowLabel` (zbytek souboru beze změny):
```swift
public enum ResetFormatter {
    public static func short(until date: Date, now: Date, bundle: Bundle = .module) -> String {
        let s = Int(date.timeIntervalSince(now))
        guard s > 0 else { return NSLocalizedString("reset.now", bundle: bundle, comment: "resets now") }
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"   // numerický formát beze slov — nelokalizuje se
    }
}

public enum WindowLabel {
    public static func text(for kind: WindowKind, bundle: Bundle = .module) -> String {
        switch kind {
        case .rolling5h: return NSLocalizedString("window.5h", bundle: bundle, comment: "5h rolling window")
        case .weekly(let s):
            if let s { return String(format: NSLocalizedString("window.week.scope", bundle: bundle, comment: "Week · scope"), s) }
            return NSLocalizedString("window.week", bundle: bundle, comment: "Week")
        }
    }
}
```

`Sources/StatusBarKit/Formatting/MenuBarStyle.swift` — uprav `displayName` (zbytek enumu beze změny). Najdi stávající `var displayName: String { switch self {...} }` a nahraď:
```swift
    public func displayName(bundle: Bundle = .module) -> String {
        switch self {
        case .dotPercent:   return NSLocalizedString("style.dotPercent", bundle: bundle, comment: "")
        case .labelPercent: return NSLocalizedString("style.labelPercent", bundle: bundle, comment: "")
        case .dotOnly:      return NSLocalizedString("style.dotOnly", bundle: bundle, comment: "")
        case .worst:        return NSLocalizedString("style.worst", bundle: bundle, comment: "")
        }
    }
    public var displayName: String { displayName() }
```

`Sources/StatusBarKit/Providers/ClaudeCodeCollector.swift` — nahraď 3 string literály (řádky ~29, 38, 44):
```swift
// řádek "Soubor … nenalezen":
                reason: String(format: NSLocalizedString("collector.claude.missing", bundle: .module, comment: ""), cachePath.lastPathComponent), now: now)
// řádek "Data stará … min":
                    status: .degraded(String(format: NSLocalizedString("collector.claude.stale", bundle: .module, comment: ""), Int(age/60))),
// řádek "Cache nelze přečíst":
                reason: String(format: NSLocalizedString("collector.claude.unreadable", bundle: .module, comment: ""), error.localizedDescription), now: now)
```

`Sources/StatusBarKit/Providers/CodexCollector.swift` — nahraď 3 string literály (řádky ~34, 41, 48). Načti soubor a uprav každý `.unavailable`/`.degraded` reason takto:
```swift
// "Žádná session …":
NSLocalizedString("collector.codex.nosession", bundle: .module, comment: "")
// "Data stará … h …":
String(format: NSLocalizedString("collector.codex.stale", bundle: .module, comment: ""), Int(age/3600))
// "V posledních … sessionech …":
String(format: NSLocalizedString("collector.codex.nolimits", bundle: .module, comment: ""), maxFilesToScan)
```

- [ ] **Step 4: Přidej klíče do Kit `.strings` (nahraď celé soubory, vč. test.ping z Tasku 6)**

`Sources/StatusBarKit/Resources/en.lproj/Localizable.strings`:
```
"test.ping" = "pong-en";

"reltime.now" = "just now";
"reltime.min" = "%lld min ago";
"reltime.hour" = "%lld h ago";
"reltime.day" = "%lld d ago";

"pace.ahead" = "%lld %% ahead";
"pace.behind" = "%lld %% behind";
"pace.onpace" = "on pace";

"reset.now" = "now";

"window.5h" = "5h window";
"window.week" = "Week";
"window.week.scope" = "Week · %@";

"style.dotPercent" = "Dot + %%";
"style.labelPercent" = "Label + %%";
"style.dotOnly" = "Dot only";
"style.worst" = "Most critical";

"collector.claude.missing" = "File %@ not found. Open Claude Code and run /usage.";
"collector.claude.stale" = "Data %lld min old — open Claude Code.";
"collector.claude.unreadable" = "Cache unreadable: %@";

"collector.codex.nosession" = "No session in ~/.codex/sessions. Run `codex` once.";
"collector.codex.stale" = "Data %lld h old — run `codex` to refresh.";
"collector.codex.nolimits" = "No limits in the last %lld sessions.";
```

`Sources/StatusBarKit/Resources/cs.lproj/Localizable.strings`:
```
"test.ping" = "pong-cs";

"reltime.now" = "právě teď";
"reltime.min" = "před %lld min";
"reltime.hour" = "před %lld h";
"reltime.day" = "před %lld d";

"pace.ahead" = "napřed o %lld %%";
"pace.behind" = "pozadu o %lld %%";
"pace.onpace" = "v tempu";

"reset.now" = "teď";

"window.5h" = "5h okno";
"window.week" = "Týden";
"window.week.scope" = "Týden · %@";

"style.dotPercent" = "Tečka + %%";
"style.labelPercent" = "Štítek + %%";
"style.dotOnly" = "Jen tečka";
"style.worst" = "Nejkritičtější";

"collector.claude.missing" = "Soubor %@ nenalezen. Otevři Claude Code a spusť /usage.";
"collector.claude.stale" = "Data stará %lld min — otevři Claude Code.";
"collector.claude.unreadable" = "Cache nelze přečíst: %@";

"collector.codex.nosession" = "Žádná session v ~/.codex/sessions. Spusť jednou `codex`.";
"collector.codex.stale" = "Data stará %lld h — spusť `codex` pro aktualizaci.";
"collector.codex.nolimits" = "V posledních %lld sessionech nejsou žádné limity.";
```

- [ ] **Step 5: Run test — vše zelené**

Run: `swift test`
Expected: PASS — upravené formatter testy (cs i en) + nezměněné collector/AlertEvaluator testy (asertují case).

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusBarKit Tests/StatusBarKitTests
git commit -m "feat: lokalizace Kit formatterů (en/cs) přes injektovatelný bundle"
```

---

### Task 8: Lokalizace App stringů

**Files:**
- Modify: `Sources/StatusBarApp/PopoverView.swift`
- Modify: `Sources/StatusBarApp/SettingsView.swift`
- Modify: `Sources/StatusBarApp/NotificationService.swift`
- Modify: `Sources/StatusBarApp/MenuBarController.swift` (fallback + 3 tooltipy)
- Modify: `Sources/StatusBarApp/SettingsWindowController.swift` (titulek okna)
- Modify: `Sources/StatusBarApp/Resources/en.lproj/Localizable.strings`, `cs.lproj/Localizable.strings`

**Interfaces:** žádné nové (App-interní). App stringy přes `String(localized: "key", bundle: .module)` (SwiftUI `Text`) nebo `NSLocalizedString("key", bundle: .module, comment:)` + `String(format:)` (interpolace). App nemá unit testy → ověření build + smoke.

> **Vzor:** prosté texty `Text(String(localized: "popover.title", bundle: .module))`; interpolace `Text(String(format: NSLocalizedString("popover.month.total", bundle: .module, comment: ""), a, b))`. `.module` zde = App bundle.

- [ ] **Step 1: `PopoverView.swift` — nahraď user-facing literály klíči**

Mapování (klíč → kde): `popover.title`("Spotřeba"), `popover.todaytotal`("Dnes ≈ %@"), `popover.loading`("Načítám…"), `popover.link.anthropic`("Stav Anthropic"), `popover.link.openai`("Stav OpenAI"), `popover.link.usageClaude`("Usage Claude"), `popover.link.usageOpenai`("Usage OpenAI"), `popover.settings`("Nastavení…"), `popover.quit`("Konec"), `popover.updated`("Aktualizováno %@"), `popover.today`("Dnes"), `popover.today.detail`("%@ tok (+%@ cache) ≈ %@"), `popover.remaining`("%lld%% zbývá" → pozor: zdroj počítá Int, ne fraction), `popover.pace`("Tempo: %@"), `popover.month`("30 dní"), `popover.month.detail`("%@ tok ≈ %@"), `popover.month.projection`("≈ %@/měs"), `popover.computing`("30 dní: počítám…").

Konkrétní náhrady (klíčové řádky):
```swift
// header:
Text(String(localized: "popover.title", bundle: .module)).font(.headline)
// dnesCelkem:
Text(String(format: NSLocalizedString("popover.todaytotal", bundle: .module, comment: ""), TokenFormatter.money(dnesCelkem)))
// prázdný store:
Text(String(localized: "popover.loading", bundle: .module))
// odkazy:
linkButton(String(localized: "popover.link.anthropic", bundle: .module), "https://status.anthropic.com")
linkButton(String(localized: "popover.link.openai", bundle: .module), "https://status.openai.com")
linkButton(String(localized: "popover.link.usageClaude", bundle: .module), "https://claude.ai/settings/usage")
linkButton(String(localized: "popover.link.usageOpenai", bundle: .module), "https://platform.openai.com/usage")
// dolní lišta:
Button(String(localized: "popover.settings", bundle: .module), action: onOpenSettings)...
Button(String(localized: "popover.quit", bundle: .module), action: onQuit)...
// ProviderCard "Aktualizováno":
Text(String(format: NSLocalizedString("popover.updated", bundle: .module, comment: ""), RelativeTimeFormatter.string(from: usage.lastUpdated, now: Date())))
// todayRow "Dnes":
Text(String(localized: "popover.today", bundle: .module)).font(.caption2)...
// todayRow detail:
Text(String(format: NSLocalizedString("popover.today.detail", bundle: .module, comment: ""), TokenFormatter.compact(today.total.realTokens), TokenFormatter.compact(today.total.cacheTokens), TokenFormatter.money(today.estimatedCost)))
// windowsList "% zbývá":
Text(String(format: NSLocalizedString("popover.remaining", bundle: .module, comment: ""), max(0, 100 - Int((w.usedFraction*100).rounded()))))
// windowsList "Tempo:":
Text(String(format: NSLocalizedString("popover.pace", bundle: .module, comment: ""), PaceLabel.text(deltaPercent: d)))
// monthRow (z Tasku 5):
Text(String(localized: "popover.month", bundle: .module))   // "30 dní"
Text(String(format: NSLocalizedString("popover.month.detail", bundle: .module, comment: ""), TokenFormatter.compact(p.tokens.realTokens), TokenFormatter.money(p.cost)))
Text(String(format: NSLocalizedString("popover.month.projection", bundle: .module, comment: ""), TokenFormatter.money(CostProjection.monthly(cost: p.cost, days: 30))))
Text(String(localized: "popover.computing", bundle: .module))   // "30 dní: počítám…"
```

- [ ] **Step 2: `SettingsView.swift` — nahraď literály klíči**

`settings.title`("Nastavení"), `settings.launch`("Spouštět při přihlášení"), `settings.bar`("Zobrazení lišty"), `settings.style`("Styl"), `settings.numberShows`("Číslo ukazuje"), `settings.remaining`("Zbývající"), `settings.used`("Vyčerpané"), `settings.alerts`("Upozornění"), `settings.alertToggle`("Upozornit, když klesnou zbývající limity"), `settings.threshold`("Práh (zbývá ≤)"), `settings.percent`("%lld %%" → pozor Int), `settings.version`("StatusBar %@"). Použij `Text(String(localized: "...", bundle: .module))`; pro `"\($0) %"` → `Text(String(format: NSLocalizedString("settings.percent", bundle: .module, comment: ""), $0))`; verze → `Text(String(format: NSLocalizedString("settings.version", bundle: .module, comment: ""), verze))`. `MenuBarStyle` v Pickeru: `Text($0.displayName)` zůstává (property → App bundle? POZOR: `displayName` property používá Kit `.module` → správně Kit překlad). OK beze změny.

- [ ] **Step 3: `NotificationService.swift` — nahraď literály klíči**

```swift
content.title = String(format: NSLocalizedString("notif.title", bundle: .module, comment: ""), e.providerDisplayName, e.windowLabel)
var body = String(format: NSLocalizedString("notif.body", bundle: .module, comment: ""), e.remainingPercent)
if let r = e.resetAt { body += String(format: NSLocalizedString("notif.body.reset", bundle: .module, comment: ""), ResetFormatter.short(until: r, now: Date())) }
```

- [ ] **Step 4: `MenuBarController.swift` — fallback + tooltipy**

```swift
if segs.isEmpty { title.append(NSAttributedString(string: NSLocalizedString("menubar.fallback", bundle: .module, comment: ""))) }
// tooltip:
case .ok: return String(format: NSLocalizedString("menubar.tooltip.ok", bundle: .module, comment: ""), u.displayName, max(0, 100 - u.nearestLimitPercent))
case .degraded(let m): return String(format: NSLocalizedString("menubar.tooltip.degraded", bundle: .module, comment: ""), u.displayName, m)
case .unavailable(let m): return String(format: NSLocalizedString("menubar.tooltip.unavailable", bundle: .module, comment: ""), u.displayName, m)
```

- [ ] **Step 5: `SettingsWindowController.swift` — titulek okna**

Najdi `"StatusBar — Nastavení"` a nahraď: `String(localized: "window.settings.title", bundle: .module)`.

- [ ] **Step 6: App `.strings` (nahraď celé soubory)**

`Sources/StatusBarApp/Resources/en.lproj/Localizable.strings`:
```
"test.ping" = "app-pong-en";

"popover.title" = "Usage";
"popover.todaytotal" = "Today ≈ %@";
"popover.loading" = "Loading…";
"popover.link.anthropic" = "Anthropic Status";
"popover.link.openai" = "OpenAI Status";
"popover.link.usageClaude" = "Claude Usage";
"popover.link.usageOpenai" = "OpenAI Usage";
"popover.settings" = "Settings…";
"popover.quit" = "Quit";
"popover.updated" = "Updated %@";
"popover.today" = "Today";
"popover.today.detail" = "%@ tok (+%@ cache) ≈ %@";
"popover.remaining" = "%lld%% left";
"popover.pace" = "Pace: %@";
"popover.month" = "30 days";
"popover.month.detail" = "%@ tok ≈ %@";
"popover.month.projection" = "≈ %@/mo";
"popover.computing" = "30 days: computing…";

"settings.title" = "Settings";
"settings.launch" = "Launch at login";
"settings.bar" = "Menu bar display";
"settings.style" = "Style";
"settings.numberShows" = "Number shows";
"settings.remaining" = "Remaining";
"settings.used" = "Used";
"settings.alerts" = "Alerts";
"settings.alertToggle" = "Alert when remaining limits drop";
"settings.threshold" = "Threshold (left ≤)";
"settings.percent" = "%lld %%";
"settings.version" = "StatusBar %@";

"notif.title" = "%@ — %@";
"notif.body" = "%lld%% left";
"notif.body.reset" = " · resets in %@";

"menubar.fallback" = "StatusBar";
"menubar.tooltip.ok" = "%@: %lld%% left";
"menubar.tooltip.degraded" = "%@: ⚠︎ %@";
"menubar.tooltip.unavailable" = "%@: — %@";

"window.settings.title" = "StatusBar — Settings";
```

`Sources/StatusBarApp/Resources/cs.lproj/Localizable.strings`:
```
"test.ping" = "app-pong-cs";

"popover.title" = "Spotřeba";
"popover.todaytotal" = "Dnes ≈ %@";
"popover.loading" = "Načítám…";
"popover.link.anthropic" = "Stav Anthropic";
"popover.link.openai" = "Stav OpenAI";
"popover.link.usageClaude" = "Usage Claude";
"popover.link.usageOpenai" = "Usage OpenAI";
"popover.settings" = "Nastavení…";
"popover.quit" = "Konec";
"popover.updated" = "Aktualizováno %@";
"popover.today" = "Dnes";
"popover.today.detail" = "%@ tok (+%@ cache) ≈ %@";
"popover.remaining" = "%lld%% zbývá";
"popover.pace" = "Tempo: %@";
"popover.month" = "30 dní";
"popover.month.detail" = "%@ tok ≈ %@";
"popover.month.projection" = "≈ %@/měs";
"popover.computing" = "30 dní: počítám…";

"settings.title" = "Nastavení";
"settings.launch" = "Spouštět při přihlášení";
"settings.bar" = "Zobrazení lišty";
"settings.style" = "Styl";
"settings.numberShows" = "Číslo ukazuje";
"settings.remaining" = "Zbývající";
"settings.used" = "Vyčerpané";
"settings.alerts" = "Upozornění";
"settings.alertToggle" = "Upozornit, když klesnou zbývající limity";
"settings.threshold" = "Práh (zbývá ≤)";
"settings.percent" = "%lld %%";
"settings.version" = "StatusBar %@";

"notif.title" = "%@ — %@";
"notif.body" = "Zbývá %lld%%";
"notif.body.reset" = " · reset za %@";

"menubar.fallback" = "StatusBar";
"menubar.tooltip.ok" = "%@: %lld%% zbývá";
"menubar.tooltip.degraded" = "%@: ⚠︎ %@";
"menubar.tooltip.unavailable" = "%@: — %@";

"window.settings.title" = "StatusBar — Nastavení";
```

- [ ] **Step 7: Build + smoke**

Run: `swift build`
Expected: BUILD OK.

Run: `swift test`
Expected: PASS (App změny neovlivní Kit testy).

- [ ] **Step 8: Commit**

```bash
git add Sources/StatusBarApp
git commit -m "feat: lokalizace App stringů (PopoverView, Settings, notifikace, tooltipy)"
```

---

### Task 9: Kontrola úplnosti překladů + finální smoke

**Files:**
- Test: `Tests/StatusBarKitTests/LocalizationCompletenessTests.swift`
- (případně drobné opravy chybějících klíčů v `.strings`)

**Interfaces:** žádné. Pojistka, že en i cs `.strings` mají identickou množinu klíčů (žádný neplakomarený/chybějící).

- [ ] **Step 1: Test úplnosti klíčů (Kit bundle)**

```swift
// Tests/StatusBarKitTests/LocalizationCompletenessTests.swift
import Testing
import Foundation
@testable import StatusBarKit

private func keys(_ langBundle: Bundle) -> Set<String> {
    guard let url = langBundle.url(forResource: "Localizable", withExtension: "strings"),
          let dict = NSDictionary(contentsOf: url) as? [String: String] else { return [] }
    return Set(dict.keys)
}

@Test func kitKlíčeEnACsShodné() {
    let en = keys(L10n.bundle("en"))
    let cs = keys(L10n.bundle("cs"))
    #expect(!en.isEmpty)
    #expect(en == cs, "Kit: rozdíl klíčů en↔cs: \(en.symmetricDifference(cs).sorted())")
}
```

- [ ] **Step 2: Run test**

Run: `swift test`
Expected: PASS. Pokud FAIL → doplň chybějící klíče do příslušného `.strings`, znovu `swift test`.

- [ ] **Step 3: Finální smoke (build + bundle check)**

Run: `swift build && swift test`
Expected: vše zelené (cílově ~133+ testů: 119 původních + nové z Tasků 1–9).

(Volitelný bundle build-check, BEZ spuštění:)
Run: `bash scripts/make-app.sh`
Expected: `.app` vytvořen. **NESPOUŠTĚT.** Vizuální ověření cs/en (přepnutí jazyka macOS) + 30denní řádek dělá uživatel.

- [ ] **Step 4: Commit**

```bash
git add Tests/StatusBarKitTests/LocalizationCompletenessTests.swift
git commit -m "test: kontrola úplnosti lokalizačních klíčů en↔cs"
```

---

## Verifikace plánu (self-review)

- **Spec coverage:** v0.9b §2 → Tasky 1–5 (PeriodCost/CostProjection, rangeUsage Claude/Codex, CostHistoryStore, App wiring+PopoverView). v0.9c §3 → Tasky 6–9 (scaffolding+canary, Kit formattery, App stringy, úplnost). Perf (off-main/throttle/ne-60s) → Task 4+5. Projekce → Task 1+5. Injektovatelný bundle → Task 6+7. R-OVĚŘENÍ pipeline → Task 6 (gate). NElokalizovat ($/plány/modely/„—") → Global Constraints + Task 7/8 pozn.
- **Typová konzistence:** `PeriodCost(tokens:cost:)`, `CostProjection.monthly(cost:days:)`, `rangeUsage(start:end:)`, `CostHistoryStore(staleInterval:provider:)`/`refresh(now:)`/`refreshIfStale(now:)`/`shouldRefresh(now:)`, `L10n.bundle(_:)`, formatter `bundle:` overloady, `MenuBarStyle.displayName(bundle:)` + `var displayName` — používány konzistentně napříč tasky a testy.
- **TodayUsage reuse:** `rangeUsage` vrací `TodayUsage?` (interní agregát); display vrstva mapuje na `PeriodCost`. Hlídá review (R3).
- **Pořadí:** v0.9b první (zavede „30 dní"/„počítám…" stringy) → v0.9c je lokalizuje (Task 8 monthRow klíče). Task 6 je gate před 7–9.
