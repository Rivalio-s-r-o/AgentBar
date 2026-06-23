# StatusBar MVP v0.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Postavit nativní macOS menu bar aplikaci, která v liště ukazuje spotřebu/limity Claude Code a Codexu (styl A — dvě procenta) a po rozkliknutí panel s 5h/týdenními okny.

**Architecture:** SwiftPM balík se dvěma cíli — knihovna `StatusBarKit` (čistá, plně testovatelná logika: modely, parsery, collectory, store, scheduler, formátování) a spustitelný cíl `StatusBarApp` (tenká AppKit/SwiftUI vrstva: `NSStatusItem` + SwiftUI popover). Data se čtou jen lokálně: Claude z `~/.claude/.usage_cache.json`, Codex z nejnovějšího `~/.codex/sessions/**/*.jsonl`. Žádný cloud.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing (`import Testing`), AppKit (`NSStatusItem`, `NSPopover`), SwiftUI. macOS 14+.

## Global Constraints

- Cílová platforma: **macOS 14+** (`.macOS(.v14)` v Package.swift).
- Jazyk: **Swift 6**, `swift-tools-version: 6.0`.
- Testovací framework: **Swift Testing** (`@Test`, `#expect`), spouštěné `swift test`.
- Veškerá logika v `StatusBarKit` musí být testovatelná **bez UI a bez živých dat** (proti fixturám).
- Čtení souborů **jen pro čtení**; nikdy nezapisovat do `~/.claude` ani `~/.codex`.
- Žádné modální dialogy, žádné pády při chybějících/poškozených datech — poskytovatel přejde do stavu `degraded`/`unavailable`.
- `usedFraction` je vždy desetinné číslo 0.0–1.0+ (procenta /100). Zdroje uvádějí procenta (např. `8.0` = 8 %).
- Žádné vymyšlené hodnoty: pokud zdroj nedává údaj (např. plán „Max"), pole zůstává `nil`.
- Commit po každém dokončeném tasku.

---

### Task 1: Scaffold balíku + doménový model

**Files:**
- Create: `Package.swift`
- Create: `Sources/StatusBarKit/Models/ProviderUsage.swift`
- Create: `Tests/StatusBarKitTests/ProviderUsageTests.swift`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: nic (první task).
- Produces: typy `ProviderID`, `WindowKind`, `ProviderStatus`, `UsageWindow`, `ProviderUsage` a computed `ProviderUsage.nearestLimitPercent: Int`.

- [ ] **Step 1: Vytvoř `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatusBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "StatusBarKit"),
        .executableTarget(
            name: "StatusBarApp",
            dependencies: ["StatusBarKit"]
        ),
        .testTarget(
            name: "StatusBarKitTests",
            dependencies: ["StatusBarKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

- [ ] **Step 2: Přidej `.gitignore` pravidla pro Swift build**

Přidej na konec `.gitignore`:

```
.build/
*.app
DerivedData/
.swiftpm/
```

- [ ] **Step 3: Napiš model `Sources/StatusBarKit/Models/ProviderUsage.swift`**

```swift
import Foundation

public enum ProviderID: String, Sendable, CaseIterable {
    case claudeCode
    case codex
}

public enum WindowKind: Sendable, Equatable {
    case rolling5h
    case weekly(scope: String?)  // scope == nil => celkový týden; jinak název modelu, např. "Sonnet"
}

public enum ProviderStatus: Sendable, Equatable {
    case ok
    case degraded(String)      // máme částečná data; řetězec je tooltip
    case unavailable(String)   // nemáme data; řetězec je tooltip
}

public struct UsageWindow: Sendable, Equatable {
    public let kind: WindowKind
    public let usedFraction: Double   // 0.0 ... 1.0+ (procenta /100)
    public let resetAt: Date?

    public init(kind: WindowKind, usedFraction: Double, resetAt: Date?) {
        self.kind = kind
        self.usedFraction = usedFraction
        self.resetAt = resetAt
    }
}

public struct ProviderUsage: Sendable, Equatable {
    public let providerId: ProviderID
    public let displayName: String
    public let planLabel: String?
    public let windows: [UsageWindow]
    public let status: ProviderStatus
    public let lastUpdated: Date

    public init(
        providerId: ProviderID,
        displayName: String,
        planLabel: String?,
        windows: [UsageWindow],
        status: ProviderStatus,
        lastUpdated: Date
    ) {
        self.providerId = providerId
        self.displayName = displayName
        self.planLabel = planLabel
        self.windows = windows
        self.status = status
        self.lastUpdated = lastUpdated
    }

    /// Nejvyšší naplnění napříč okny (0.0–1.0+). Použije lišta i panel.
    public var nearestLimitFraction: Double {
        windows.map(\.usedFraction).max() ?? 0
    }

    /// Zaokrouhlené procento nejbližšího limitu pro zobrazení v liště.
    public var nearestLimitPercent: Int {
        Int((nearestLimitFraction * 100).rounded())
    }
}
```

- [ ] **Step 4: Napiš padající test `Tests/StatusBarKitTests/ProviderUsageTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func nearestLimitPercentVracíMaximumZOken() {
    let usage = ProviderUsage(
        providerId: .claudeCode,
        displayName: "Claude Code",
        planLabel: nil,
        windows: [
            UsageWindow(kind: .rolling5h, usedFraction: 0.08, resetAt: nil),
            UsageWindow(kind: .weekly(scope: nil), usedFraction: 0.61, resetAt: nil),
        ],
        status: .ok,
        lastUpdated: Date(timeIntervalSince1970: 0)
    )
    #expect(usage.nearestLimitPercent == 61)
}

@Test func nearestLimitPercentBezOkenJeNula() {
    let usage = ProviderUsage(
        providerId: .codex, displayName: "Codex", planLabel: nil,
        windows: [], status: .unavailable("žádná data"),
        lastUpdated: Date(timeIntervalSince1970: 0)
    )
    #expect(usage.nearestLimitPercent == 0)
}
```

- [ ] **Step 5: Spusť test — musí selhat (nezkompiluje se / typy chybí)**

Run: `swift test --filter ProviderUsageTests`
Expected: FAIL při buildu, dokud model neexistuje. Po napsání modelu (Step 3) už build projde; pokud jsi psal v pořadí, spusť znovu.

- [ ] **Step 6: Spusť test — musí projít**

Run: `swift test --filter ProviderUsageTests`
Expected: PASS (2 testy).

- [ ] **Step 7: Commit**

```bash
git add Package.swift .gitignore Sources/StatusBarKit/Models/ProviderUsage.swift Tests/StatusBarKitTests/ProviderUsageTests.swift
git commit -m "feat: scaffold SwiftPM balíku a doménový model ProviderUsage"
```

---

### Task 2: Parser Claude usage cache

**Files:**
- Create: `Sources/StatusBarKit/Providers/ClaudeUsageCacheParser.swift`
- Create: `Tests/StatusBarKitTests/Fixtures/claude-usage-cache.json`
- Create: `Tests/StatusBarKitTests/ClaudeUsageCacheParserTests.swift`

**Interfaces:**
- Consumes: `ProviderUsage`, `UsageWindow`, `WindowKind` (Task 1).
- Produces: `enum ClaudeUsageCacheParser { static func parse(_ data: Data) throws -> ProviderUsage }`.

Pozn.: Struktura fixtury je 1:1 reálný `~/.claude/.usage_cache.json` zachycený na cílovém stroji. `utilization` je procento (8.0 = 8 %). Vnější `timestamp` (Unix epoch) → `lastUpdated`. `resets_at` je ISO 8601.

- [ ] **Step 1: Vytvoř fixturu `Tests/StatusBarKitTests/Fixtures/claude-usage-cache.json`**

```json
{"timestamp": 1782223012.474268, "data": {"five_hour": {"utilization": 8.0, "resets_at": "2026-06-23T14:59:59.461210+00:00", "limit_dollars": null, "used_dollars": null, "remaining_dollars": null}, "seven_day": {"utilization": 2.0, "resets_at": "2026-06-30T11:59:59.461233+00:00", "limit_dollars": null, "used_dollars": null, "remaining_dollars": null}, "seven_day_opus": null, "seven_day_sonnet": {"utilization": 12.0, "resets_at": "2026-06-30T12:00:00.461241+00:00", "limit_dollars": null, "used_dollars": null, "remaining_dollars": null}}}
```

- [ ] **Step 2: Napiš padající test `Tests/StatusBarKitTests/ClaudeUsageCacheParserTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

private func loadFixture(_ name: String) throws -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    return try Data(contentsOf: url)
}

@Test func parseClaudeCacheVytvoříOkna() throws {
    let usage = try ClaudeUsageCacheParser.parse(loadFixture("claude-usage-cache"))

    #expect(usage.providerId == .claudeCode)
    #expect(usage.displayName == "Claude Code")
    #expect(usage.status == .ok)

    // 5h okno: 8 % => 0.08
    let five = usage.windows.first { $0.kind == .rolling5h }
    #expect(five != nil)
    #expect(abs((five?.usedFraction ?? -1) - 0.08) < 0.0001)

    // týden celkový: 2 % => 0.02
    let weekAll = usage.windows.first { $0.kind == .weekly(scope: nil) }
    #expect(abs((weekAll?.usedFraction ?? -1) - 0.02) < 0.0001)

    // týden scoped Sonnet: 12 % => 0.12
    let weekSonnet = usage.windows.first { $0.kind == .weekly(scope: "Sonnet") }
    #expect(abs((weekSonnet?.usedFraction ?? -1) - 0.12) < 0.0001)

    // lastUpdated z vnějšího timestampu
    #expect(abs(usage.lastUpdated.timeIntervalSince1970 - 1782223012.474268) < 0.001)
}

@Test func parseClaudeCacheChybnýJSONHodí() {
    #expect(throws: (any Error).self) {
        _ = try ClaudeUsageCacheParser.parse(Data("nonsense".utf8))
    }
}
```

- [ ] **Step 3: Spusť test — musí selhat**

Run: `swift test --filter ClaudeUsageCacheParserTests`
Expected: FAIL ("cannot find 'ClaudeUsageCacheParser'").

- [ ] **Step 4: Napiš `Sources/StatusBarKit/Providers/ClaudeUsageCacheParser.swift`**

```swift
import Foundation

public enum ClaudeUsageCacheParser {

    private struct Cache: Decodable {
        let timestamp: Double
        let data: CacheData
    }
    private struct CacheData: Decodable {
        let five_hour: Window?
        let seven_day: Window?
        let seven_day_opus: Window?
        let seven_day_sonnet: Window?
    }
    private struct Window: Decodable {
        let utilization: Double
        let resets_at: String?
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        return isoFormatter.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    public static func parse(_ data: Data) throws -> ProviderUsage {
        let cache = try JSONDecoder().decode(Cache.self, from: data)
        var windows: [UsageWindow] = []

        if let w = cache.data.five_hour {
            windows.append(UsageWindow(kind: .rolling5h,
                                       usedFraction: w.utilization / 100.0,
                                       resetAt: date(w.resets_at)))
        }
        if let w = cache.data.seven_day {
            windows.append(UsageWindow(kind: .weekly(scope: nil),
                                       usedFraction: w.utilization / 100.0,
                                       resetAt: date(w.resets_at)))
        }
        if let w = cache.data.seven_day_opus {
            windows.append(UsageWindow(kind: .weekly(scope: "Opus"),
                                       usedFraction: w.utilization / 100.0,
                                       resetAt: date(w.resets_at)))
        }
        if let w = cache.data.seven_day_sonnet {
            windows.append(UsageWindow(kind: .weekly(scope: "Sonnet"),
                                       usedFraction: w.utilization / 100.0,
                                       resetAt: date(w.resets_at)))
        }

        return ProviderUsage(
            providerId: .claudeCode,
            displayName: "Claude Code",
            planLabel: nil,
            windows: windows,
            status: .ok,
            lastUpdated: Date(timeIntervalSince1970: cache.timestamp)
        )
    }
}
```

- [ ] **Step 5: Spusť test — musí projít**

Run: `swift test --filter ClaudeUsageCacheParserTests`
Expected: PASS (2 testy).

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusBarKit/Providers/ClaudeUsageCacheParser.swift Tests/StatusBarKitTests/Fixtures/claude-usage-cache.json Tests/StatusBarKitTests/ClaudeUsageCacheParserTests.swift
git commit -m "feat: parser ~/.claude/.usage_cache.json -> ProviderUsage"
```

---

### Task 3: `UsageProvider` protokol + `ClaudeCodeCollector`

**Files:**
- Create: `Sources/StatusBarKit/Providers/UsageProvider.swift`
- Create: `Sources/StatusBarKit/Providers/ClaudeCodeCollector.swift`
- Create: `Tests/StatusBarKitTests/ClaudeCodeCollectorTests.swift`

**Interfaces:**
- Consumes: `ProviderUsage`, `ClaudeUsageCacheParser`.
- Produces:
  - `protocol UsageProvider: Sendable { var id: ProviderID { get }; func fetch() async -> ProviderUsage }`
  - `struct ClaudeCodeCollector: UsageProvider { init(cachePath: URL) }`

- [ ] **Step 1: Napiš protokol `Sources/StatusBarKit/Providers/UsageProvider.swift`**

```swift
import Foundation

/// Každý poskytovatel umí jediné: získat svůj aktuální stav.
/// Chyby se nevyhazují — vrací se ProviderUsage se statusem .unavailable/.degraded,
/// aby selhání jednoho poskytovatele neshodilo ostatní.
public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func fetch() async -> ProviderUsage
}

extension ProviderUsage {
    /// Pomocník pro stav „nedostupné" s prázdnými okny.
    public static func unavailable(_ id: ProviderID, displayName: String, reason: String, now: Date) -> ProviderUsage {
        ProviderUsage(providerId: id, displayName: displayName, planLabel: nil,
                      windows: [], status: .unavailable(reason), lastUpdated: now)
    }
}
```

- [ ] **Step 2: Napiš padající test `Tests/StatusBarKitTests/ClaudeCodeCollectorTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func collectorPřečteExistujícíCache() async throws {
    // Připrav dočasný soubor s fixturou.
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("statusbar-test-\(UUID().uuidString).json")
    let fixture = try Bundle.module.url(forResource: "claude-usage-cache", withExtension: "json", subdirectory: "Fixtures")!
    try FileManager.default.copyItem(at: fixture, to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let collector = ClaudeCodeCollector(cachePath: tmp)
    let usage = await collector.fetch()

    #expect(usage.providerId == .claudeCode)
    #expect(usage.status == .ok)
    #expect(usage.windows.isEmpty == false)
}

@Test func collectorChybějícíSouborJeUnavailable() async {
    let missing = FileManager.default.temporaryDirectory
        .appendingPathComponent("statusbar-missing-\(UUID().uuidString).json")
    let collector = ClaudeCodeCollector(cachePath: missing)
    let usage = await collector.fetch()

    if case .unavailable = usage.status {} else {
        Issue.record("Očekáván status .unavailable, byl \(usage.status)")
    }
    #expect(usage.windows.isEmpty)
}
```

- [ ] **Step 3: Spusť test — musí selhat**

Run: `swift test --filter ClaudeCodeCollectorTests`
Expected: FAIL ("cannot find 'ClaudeCodeCollector'").

- [ ] **Step 4: Napiš `Sources/StatusBarKit/Providers/ClaudeCodeCollector.swift`**

```swift
import Foundation

public struct ClaudeCodeCollector: UsageProvider {
    public let id: ProviderID = .claudeCode
    private let cachePath: URL

    /// Výchozí cesta: ~/.claude/.usage_cache.json
    public init(cachePath: URL? = nil) {
        self.cachePath = cachePath ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.usage_cache.json")
    }

    public func fetch() async -> ProviderUsage {
        let now = Date()
        guard let data = try? Data(contentsOf: cachePath) else {
            return .unavailable(.claudeCode, displayName: "Claude Code",
                                reason: "Soubor \(cachePath.lastPathComponent) nenalezen. Otevři Claude Code a spusť /usage.",
                                now: now)
        }
        do {
            return try ClaudeUsageCacheParser.parse(data)
        } catch {
            return .unavailable(.claudeCode, displayName: "Claude Code",
                                reason: "Cache se nepodařilo přečíst: \(error.localizedDescription)",
                                now: now)
        }
    }
}
```

- [ ] **Step 5: Spusť test — musí projít**

Run: `swift test --filter ClaudeCodeCollectorTests`
Expected: PASS (2 testy).

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusBarKit/Providers/UsageProvider.swift Sources/StatusBarKit/Providers/ClaudeCodeCollector.swift Tests/StatusBarKitTests/ClaudeCodeCollectorTests.swift
git commit -m "feat: UsageProvider protokol + ClaudeCodeCollector"
```

---

### Task 4: Parser Codex rate-limitů

**Files:**
- Create: `Sources/StatusBarKit/Providers/CodexRateLimitParser.swift`
- Create: `Tests/StatusBarKitTests/Fixtures/codex-session-with-limits.jsonl`
- Create: `Tests/StatusBarKitTests/Fixtures/codex-session-null-limits.jsonl`
- Create: `Tests/StatusBarKitTests/CodexRateLimitParserTests.swift`

**Interfaces:**
- Consumes: `UsageWindow`, `WindowKind`.
- Produces: `enum CodexRateLimitParser { static func latestWindows(fromJSONL data: Data, now: Date) -> [UsageWindow] }`.

Pozn.: Codex zapisuje do session JSONL události `{"type":"event_msg","payload":{"type":"token_count","rate_limits":{...}}}`. Reálná struktura `rate_limits` (zachyceno na stroji, verze 0.135.0) obsahuje `primary`/`secondary` (zde mohou být `null`, dokud neproběhne odpověď) plus `limit_id`/`credits`. Okna `primary` (5h) a `secondary` (týden) nesou `used_percent` a `resets_in_seconds`. Dekodér je **defenzivní**: chybějící/`null` pole tolerantně přeskočí. Inner názvy polí ověř proti čerstvé session při integraci (Task 9, Step 6) — dekodér kvůli optional polím nespadne, jen vrátí míň oken.

- [ ] **Step 1: Vytvoř fixturu s limity `Tests/StatusBarKitTests/Fixtures/codex-session-with-limits.jsonl`**

```
{"timestamp":"2026-05-08T10:09:00.000Z","type":"session_meta","payload":{"id":"test"}}
{"timestamp":"2026-05-08T10:10:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"premium","primary":{"used_percent":40.0,"window_minutes":300,"resets_in_seconds":3600},"secondary":{"used_percent":55.0,"window_minutes":10080,"resets_in_seconds":172800}}}}
{"timestamp":"2026-05-08T10:12:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"premium","primary":{"used_percent":78.0,"window_minutes":300,"resets_in_seconds":2460},"secondary":{"used_percent":55.0,"window_minutes":10080,"resets_in_seconds":172000}}}}
```

- [ ] **Step 2: Vytvoř fixturu bez limitů `Tests/StatusBarKitTests/Fixtures/codex-session-null-limits.jsonl`**

```
{"timestamp":"2026-05-08T10:10:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"premium","primary":null,"secondary":null,"credits":{"has_credits":false}}}}
```

- [ ] **Step 3: Napiš padající test `Tests/StatusBarKitTests/CodexRateLimitParserTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

private func fixtureData(_ name: String) throws -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures")!
    return try Data(contentsOf: url)
}

@Test func parserVezmePosledníTokenCountSLimity() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let windows = CodexRateLimitParser.latestWindows(fromJSONL: try fixtureData("codex-session-with-limits"), now: now)

    // Bere POSLEDNÍ událost (used_percent 78 / 55).
    let five = windows.first { $0.kind == .rolling5h }
    #expect(five != nil)
    #expect(abs((five?.usedFraction ?? -1) - 0.78) < 0.0001)
    // resetAt = now + 2460 s
    #expect(abs((five?.resetAt?.timeIntervalSince1970 ?? 0) - (1_000_000 + 2460)) < 0.5)

    let week = windows.first { $0.kind == .weekly(scope: nil) }
    #expect(abs((week?.usedFraction ?? -1) - 0.55) < 0.0001)
}

@Test func parserBezLimitůVrátíPrázdno() throws {
    let windows = CodexRateLimitParser.latestWindows(
        fromJSONL: try fixtureData("codex-session-null-limits"), now: Date())
    #expect(windows.isEmpty)
}
```

- [ ] **Step 4: Spusť test — musí selhat**

Run: `swift test --filter CodexRateLimitParserTests`
Expected: FAIL ("cannot find 'CodexRateLimitParser'").

- [ ] **Step 5: Napiš `Sources/StatusBarKit/Providers/CodexRateLimitParser.swift`**

```swift
import Foundation

public enum CodexRateLimitParser {

    private struct Line: Decodable {
        let type: String?
        let payload: Payload?
    }
    private struct Payload: Decodable {
        let type: String?
        let rate_limits: RateLimits?
    }
    private struct RateLimits: Decodable {
        let primary: Window?
        let secondary: Window?
    }
    private struct Window: Decodable {
        let used_percent: Double?
        let resets_in_seconds: Double?
        let window_minutes: Double?
    }

    /// Projde JSONL řádky, najde POSLEDNÍ token_count událost s nenulovými rate_limits
    /// a vrátí z ní okna. Pokud žádná není, vrátí [].
    public static func latestWindows(fromJSONL data: Data, now: Date) -> [UsageWindow] {
        let decoder = JSONDecoder()
        var lastLimits: RateLimits?

        for raw in data.split(separator: UInt8(ascii: "\n")) {
            guard !raw.isEmpty,
                  let line = try? decoder.decode(Line.self, from: Data(raw)),
                  line.type == "event_msg",
                  line.payload?.type == "token_count",
                  let rl = line.payload?.rate_limits
            else { continue }
            // Bereme jen události, kde aspoň jedno okno není null.
            if rl.primary != nil || rl.secondary != nil {
                lastLimits = rl
            }
        }

        guard let rl = lastLimits else { return [] }
        var windows: [UsageWindow] = []
        if let p = rl.primary, let pct = p.used_percent {
            windows.append(UsageWindow(
                kind: .rolling5h,
                usedFraction: pct / 100.0,
                resetAt: p.resets_in_seconds.map { now.addingTimeInterval($0) }))
        }
        if let s = rl.secondary, let pct = s.used_percent {
            windows.append(UsageWindow(
                kind: .weekly(scope: nil),
                usedFraction: pct / 100.0,
                resetAt: s.resets_in_seconds.map { now.addingTimeInterval($0) }))
        }
        return windows
    }
}
```

- [ ] **Step 6: Spusť test — musí projít**

Run: `swift test --filter CodexRateLimitParserTests`
Expected: PASS (2 testy).

- [ ] **Step 7: Commit**

```bash
git add Sources/StatusBarKit/Providers/CodexRateLimitParser.swift Tests/StatusBarKitTests/Fixtures/codex-session-with-limits.jsonl Tests/StatusBarKitTests/Fixtures/codex-session-null-limits.jsonl Tests/StatusBarKitTests/CodexRateLimitParserTests.swift
git commit -m "feat: defenzivní parser Codex rate_limits ze session JSONL"
```

---

### Task 5: `CodexCollector` (nejnovější session + freshness)

**Files:**
- Create: `Sources/StatusBarKit/Providers/CodexCollector.swift`
- Create: `Tests/StatusBarKitTests/CodexCollectorTests.swift`

**Interfaces:**
- Consumes: `CodexRateLimitParser`, `UsageProvider`, `ProviderUsage`.
- Produces: `struct CodexCollector: UsageProvider { init(sessionsDir: URL?, staleAfter: TimeInterval) }`.

- [ ] **Step 1: Napiš padající test `Tests/StatusBarKitTests/CodexCollectorTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

private func writeSession(_ fixtureName: String, into dir: URL, subpath: String) throws {
    let dest = dir.appendingPathComponent(subpath)
    try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
    let src = Bundle.module.url(forResource: fixtureName, withExtension: "jsonl", subdirectory: "Fixtures")!
    try FileManager.default.copyItem(at: src, to: dest)
}

@Test func codexCollectorNajdeNejnovějšíSessionSLimity() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cx-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try writeSession("codex-session-with-limits", into: root, subpath: "2026/05/08/rollout-a.jsonl")

    let collector = CodexCollector(sessionsDir: root, staleAfter: .greatestFiniteMagnitude)
    let usage = await collector.fetch()

    #expect(usage.providerId == .codex)
    #expect(usage.windows.contains { $0.kind == .rolling5h })
}

@Test func codexCollectorBezSessionJeUnavailable() async {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cx-empty-\(UUID().uuidString)")
    let collector = CodexCollector(sessionsDir: root, staleAfter: .greatestFiniteMagnitude)
    let usage = await collector.fetch()
    if case .unavailable = usage.status {} else {
        Issue.record("Očekáván .unavailable, byl \(usage.status)")
    }
}
```

- [ ] **Step 2: Spusť test — musí selhat**

Run: `swift test --filter CodexCollectorTests`
Expected: FAIL ("cannot find 'CodexCollector'").

- [ ] **Step 3: Napiš `Sources/StatusBarKit/Providers/CodexCollector.swift`**

```swift
import Foundation

public struct CodexCollector: UsageProvider {
    public let id: ProviderID = .codex
    private let sessionsDir: URL
    private let staleAfter: TimeInterval

    /// Výchozí: ~/.codex/sessions, data starší než 24 h označí jako degraded.
    public init(sessionsDir: URL? = nil, staleAfter: TimeInterval = 24 * 3600) {
        self.sessionsDir = sessionsDir ?? FileManager.default
            .homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        self.staleAfter = staleAfter
    }

    public func fetch() async -> ProviderUsage {
        let now = Date()
        guard let newest = newestSessionFile() else {
            return .unavailable(.codex, displayName: "Codex",
                                reason: "Žádná session v ~/.codex/sessions. Spusť jednou `codex`.",
                                now: now)
        }
        guard let data = try? Data(contentsOf: newest.url) else {
            return .unavailable(.codex, displayName: "Codex",
                                reason: "Session se nepodařilo přečíst.", now: now)
        }

        let windows = CodexRateLimitParser.latestWindows(fromJSONL: data, now: now)
        if windows.isEmpty {
            return .unavailable(.codex, displayName: "Codex",
                                reason: "V poslední session nejsou žádné limity (Codex je nezapsal).", now: now)
        }

        let age = now.timeIntervalSince(newest.modified)
        let status: ProviderStatus = age > staleAfter
            ? .degraded("Data jsou stará \(Int(age / 3600)) h — spusť Codex pro aktualizaci.")
            : .ok

        return ProviderUsage(providerId: .codex, displayName: "Codex", planLabel: nil,
                             windows: windows, status: status, lastUpdated: newest.modified)
    }

    private func newestSessionFile() -> (url: URL, modified: Date)? {
        guard let en = FileManager.default.enumerator(
            at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else { return nil }

        var best: (URL, Date)?
        for case let url as URL in en where url.pathExtension == "jsonl" {
            let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            guard let mod = vals?.contentModificationDate else { continue }
            if best == nil || mod > best!.1 { best = (url, mod) }
        }
        return best.map { (url: $0.0, modified: $0.1) }
    }
}
```

- [ ] **Step 4: Spusť test — musí projít**

Run: `swift test --filter CodexCollectorTests`
Expected: PASS (2 testy).

- [ ] **Step 5: Commit**

```bash
git add Sources/StatusBarKit/Providers/CodexCollector.swift Tests/StatusBarKitTests/CodexCollectorTests.swift
git commit -m "feat: CodexCollector — nejnovější session + freshness"
```

---

### Task 6: `UsageStore` (observable stav)

**Files:**
- Create: `Sources/StatusBarKit/Store/UsageStore.swift`
- Create: `Tests/StatusBarKitTests/UsageStoreTests.swift`

**Interfaces:**
- Consumes: `ProviderUsage`, `ProviderID`.
- Produces: `@MainActor final class UsageStore: ObservableObject` s `@Published var providers: [ProviderID: ProviderUsage]`, metodou `update(_:)`, computed `orderedUsages: [ProviderUsage]` a `worstPercent: Int`.

- [ ] **Step 1: Napiš padající test `Tests/StatusBarKitTests/UsageStoreTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

@MainActor
@Test func storeDržíNejhoršíProcento() {
    let store = UsageStore()
    store.update(ProviderUsage(providerId: .claudeCode, displayName: "Claude Code", planLabel: nil,
        windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.42, resetAt: nil)],
        status: .ok, lastUpdated: Date()))
    store.update(ProviderUsage(providerId: .codex, displayName: "Codex", planLabel: nil,
        windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.78, resetAt: nil)],
        status: .ok, lastUpdated: Date()))

    #expect(store.providers.count == 2)
    #expect(store.worstPercent == 78)
    // Pořadí: claudeCode před codex (dle ProviderID.allCases).
    #expect(store.orderedUsages.map(\.providerId) == [.claudeCode, .codex])
}
```

- [ ] **Step 2: Spusť test — musí selhat**

Run: `swift test --filter UsageStoreTests`
Expected: FAIL ("cannot find 'UsageStore'").

- [ ] **Step 3: Napiš `Sources/StatusBarKit/Store/UsageStore.swift`**

```swift
import Foundation
import Combine

@MainActor
public final class UsageStore: ObservableObject {
    @Published public private(set) var providers: [ProviderID: ProviderUsage] = [:]

    public init() {}

    public func update(_ usage: ProviderUsage) {
        providers[usage.providerId] = usage
    }

    /// Poskytovatelé v pevném pořadí (dle ProviderID.allCases).
    public var orderedUsages: [ProviderUsage] {
        ProviderID.allCases.compactMap { providers[$0] }
    }

    /// Nejhorší (nejvyšší) procento napříč všemi poskytovateli; 0 pokud žádná data.
    public var worstPercent: Int {
        orderedUsages.map(\.nearestLimitPercent).max() ?? 0
    }
}
```

- [ ] **Step 4: Spusť test — musí projít**

Run: `swift test --filter UsageStoreTests`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add Sources/StatusBarKit/Store/UsageStore.swift Tests/StatusBarKitTests/UsageStoreTests.swift
git commit -m "feat: UsageStore observable stav + agregace worstPercent"
```

---

### Task 7: `RefreshCoordinator` (spuštění collectorů → store)

**Files:**
- Create: `Sources/StatusBarKit/Store/RefreshCoordinator.swift`
- Create: `Tests/StatusBarKitTests/RefreshCoordinatorTests.swift`

**Interfaces:**
- Consumes: `UsageProvider`, `UsageStore`, `ProviderUsage`.
- Produces: `@MainActor final class RefreshCoordinator { init(store:providers:); func refreshNow() async }`.

Pozn.: Časovač (periodicita) se zapojuje až v UI vrstvě (Task 9) voláním `refreshNow()`; tady testujeme jen orchestraci, ne `Timer`.

- [ ] **Step 1: Napiš padající test `Tests/StatusBarKitTests/RefreshCoordinatorTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

private struct StubProvider: UsageProvider {
    let id: ProviderID
    let fraction: Double
    func fetch() async -> ProviderUsage {
        ProviderUsage(providerId: id, displayName: id.rawValue, planLabel: nil,
            windows: [UsageWindow(kind: .rolling5h, usedFraction: fraction, resetAt: nil)],
            status: .ok, lastUpdated: Date())
    }
}

@MainActor
@Test func refreshNowNaplníStoreZeVšechProviderů() async {
    let store = UsageStore()
    let coordinator = RefreshCoordinator(store: store, providers: [
        StubProvider(id: .claudeCode, fraction: 0.30),
        StubProvider(id: .codex, fraction: 0.90),
    ])
    await coordinator.refreshNow()
    #expect(store.providers.count == 2)
    #expect(store.worstPercent == 90)
}
```

- [ ] **Step 2: Spusť test — musí selhat**

Run: `swift test --filter RefreshCoordinatorTests`
Expected: FAIL ("cannot find 'RefreshCoordinator'").

- [ ] **Step 3: Napiš `Sources/StatusBarKit/Store/RefreshCoordinator.swift`**

```swift
import Foundation

@MainActor
public final class RefreshCoordinator {
    private let store: UsageStore
    private let providers: [any UsageProvider]

    public init(store: UsageStore, providers: [any UsageProvider]) {
        self.store = store
        self.providers = providers
    }

    /// Spustí všechny collectory paralelně a výsledky zapíše do store.
    public func refreshNow() async {
        await withTaskGroup(of: ProviderUsage.self) { group in
            for provider in providers {
                group.addTask { await provider.fetch() }
            }
            for await usage in group {
                store.update(usage)
            }
        }
    }
}
```

- [ ] **Step 4: Spusť test — musí projít**

Run: `swift test --filter RefreshCoordinatorTests`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add Sources/StatusBarKit/Store/RefreshCoordinator.swift Tests/StatusBarKitTests/RefreshCoordinatorTests.swift
git commit -m "feat: RefreshCoordinator — paralelní spuštění collectorů do store"
```

---

### Task 8: Builder textu do lišty (styl A) + formátování resetu

**Files:**
- Create: `Sources/StatusBarKit/Formatting/MenuBarTitleBuilder.swift`
- Create: `Sources/StatusBarKit/Formatting/ResetFormatter.swift`
- Create: `Tests/StatusBarKitTests/MenuBarTitleBuilderTests.swift`
- Create: `Tests/StatusBarKitTests/ResetFormatterTests.swift`

**Interfaces:**
- Consumes: `ProviderUsage`, `ProviderID`, `ProviderStatus`.
- Produces:
  - `enum UsageLevel { case normal, warning, critical }` + `static func level(forPercent:) -> UsageLevel`
  - `struct MenuBarSegment: Equatable { let providerId: ProviderID; let text: String; let level: UsageLevel }`
  - `enum MenuBarTitleBuilder { static func segments(for usages: [ProviderUsage]) -> [MenuBarSegment] }`
  - `enum ResetFormatter { static func short(until date: Date, now: Date) -> String }`

- [ ] **Step 1: Napiš padající testy — `MenuBarTitleBuilderTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func builderVytvoříSegmentSProcentemAÚrovní() {
    let usages = [
        ProviderUsage(providerId: .claudeCode, displayName: "Claude Code", planLabel: nil,
            windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.42, resetAt: nil)],
            status: .ok, lastUpdated: Date()),
        ProviderUsage(providerId: .codex, displayName: "Codex", planLabel: nil,
            windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.92, resetAt: nil)],
            status: .ok, lastUpdated: Date()),
    ]
    let segs = MenuBarTitleBuilder.segments(for: usages)
    #expect(segs.count == 2)
    #expect(segs[0] == MenuBarSegment(providerId: .claudeCode, text: "42%", level: .normal))
    #expect(segs[1] == MenuBarSegment(providerId: .codex, text: "92%", level: .critical))
}

@Test func builderNedostupnýUkážePomlčku() {
    let usages = [
        ProviderUsage.unavailable(.claudeCode, displayName: "Claude Code", reason: "x", now: Date())
    ]
    let segs = MenuBarTitleBuilder.segments(for: usages)
    #expect(segs[0] == MenuBarSegment(providerId: .claudeCode, text: "—", level: .normal))
}

@Test func úrovněPodleProcent() {
    #expect(UsageLevel.level(forPercent: 10) == .normal)
    #expect(UsageLevel.level(forPercent: 80) == .warning)
    #expect(UsageLevel.level(forPercent: 95) == .critical)
}
```

- [ ] **Step 2: Napiš padající testy — `ResetFormatterTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func resetFormatHodinyAMinuty() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(ResetFormatter.short(until: Date(timeIntervalSince1970: 2*3600 + 14*60), now: now) == "2h 14m")
}

@Test func resetFormatJenMinuty() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(ResetFormatter.short(until: Date(timeIntervalSince1970: 41*60), now: now) == "41m")
}

@Test func resetFormatVMinulosti() {
    let now = Date(timeIntervalSince1970: 100)
    #expect(ResetFormatter.short(until: Date(timeIntervalSince1970: 0), now: now) == "teď")
}
```

- [ ] **Step 3: Spusť testy — musí selhat**

Run: `swift test --filter MenuBarTitleBuilderTests` a `swift test --filter ResetFormatterTests`
Expected: FAIL (typy chybí).

- [ ] **Step 4: Napiš `Sources/StatusBarKit/Formatting/ResetFormatter.swift`**

```swift
import Foundation

public enum ResetFormatter {
    /// "2h 14m", "41m", nebo "teď" pokud už uplynulo.
    public static func short(until date: Date, now: Date) -> String {
        let secs = Int(date.timeIntervalSince(now))
        guard secs > 0 else { return "teď" }
        let hours = secs / 3600
        let minutes = (secs % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
```

- [ ] **Step 5: Napiš `Sources/StatusBarKit/Formatting/MenuBarTitleBuilder.swift`**

```swift
import Foundation

public enum UsageLevel: Sendable, Equatable {
    case normal, warning, critical

    public static func level(forPercent p: Int) -> UsageLevel {
        switch p {
        case ..<75: return .normal
        case 75..<90: return .warning
        default: return .critical
        }
    }
}

public struct MenuBarSegment: Sendable, Equatable {
    public let providerId: ProviderID
    public let text: String
    public let level: UsageLevel
    public init(providerId: ProviderID, text: String, level: UsageLevel) {
        self.providerId = providerId
        self.text = text
        self.level = level
    }
}

public enum MenuBarTitleBuilder {
    /// Styl A: pro každého poskytovatele text procenta (nebo "—" když nedostupný) + barevná úroveň.
    public static func segments(for usages: [ProviderUsage]) -> [MenuBarSegment] {
        usages.map { usage in
            switch usage.status {
            case .unavailable:
                return MenuBarSegment(providerId: usage.providerId, text: "—", level: .normal)
            case .ok, .degraded:
                let pct = usage.nearestLimitPercent
                return MenuBarSegment(providerId: usage.providerId,
                                      text: "\(pct)%",
                                      level: UsageLevel.level(forPercent: pct))
            }
        }
    }
}
```

- [ ] **Step 6: Spusť testy — musí projít**

Run: `swift test`
Expected: PASS (všechny dosavadní testy, vč. nových 6).

- [ ] **Step 7: Commit**

```bash
git add Sources/StatusBarKit/Formatting/ Tests/StatusBarKitTests/MenuBarTitleBuilderTests.swift Tests/StatusBarKitTests/ResetFormatterTests.swift
git commit -m "feat: MenuBarTitleBuilder (styl A) + ResetFormatter"
```

---

### Task 9: App shell — `NSStatusItem` + životní cyklus + časovač

**Files:**
- Create: `Sources/StatusBarApp/main.swift`
- Create: `Sources/StatusBarApp/AppDelegate.swift`
- Create: `Sources/StatusBarApp/MenuBarController.swift`
- Create: `Resources/Info.plist`
- Create: `scripts/make-app.sh`

**Interfaces:**
- Consumes: `UsageStore`, `RefreshCoordinator`, `ClaudeCodeCollector`, `CodexCollector`, `MenuBarTitleBuilder`, `MenuBarSegment`, `UsageLevel`.
- Produces: spustitelnou menu bar aplikaci; `MenuBarController` přemosťuje store → `NSStatusItem`. (Popover obsah doplní Task 10.)

Pozn.: Tento task je z velké části UI — ověřuje se **manuálním smoke testem**, ne unit testem (čistá logika už je otestovaná v Tasku 8).

- [ ] **Step 1: Napiš `Sources/StatusBarApp/main.swift`**

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // bez ikony v Docku
app.run()
```

- [ ] **Step 2: Napiš `Sources/StatusBarApp/AppDelegate.swift`**

```swift
import AppKit
import StatusBarKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private var coordinator: RefreshCoordinator!
    private var menuBar: MenuBarController!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = RefreshCoordinator(store: store, providers: [
            ClaudeCodeCollector(),
            CodexCollector(),
        ])
        menuBar = MenuBarController(store: store, onRefresh: { [weak self] in
            Task { await self?.coordinator.refreshNow() }
        })

        // První načtení hned.
        Task { await coordinator.refreshNow() }

        // Periodicky každých 60 s.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.coordinator.refreshNow() }
        }
    }
}
```

- [ ] **Step 3: Napiš `Sources/StatusBarApp/MenuBarController.swift`**

```swift
import AppKit
import Combine
import StatusBarKit

@MainActor
final class MenuBarController {
    private let store: UsageStore
    private let onRefresh: () -> Void
    private let statusItem: NSStatusItem
    private var cancellable: AnyCancellable?

    init(store: UsageStore, onRefresh: @escaping () -> Void) {
        self.store = store
        self.onRefresh = onRefresh
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        render(store.orderedUsages)
        // objectWillChange je veřejné a fíruje před změnou; aktuální stav přečteme na dalším runloopu.
        cancellable = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.render(self?.store.orderedUsages ?? []) }
        }
    }

    private func color(for level: UsageLevel) -> NSColor {
        switch level {
        case .normal: return .labelColor
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    private func dotColor(for id: ProviderID) -> NSColor {
        switch id {
        case .claudeCode: return NSColor(red: 0.85, green: 0.46, blue: 0.34, alpha: 1) // oranžová
        case .codex: return NSColor(red: 0.06, green: 0.64, blue: 0.50, alpha: 1)       // zelená
        }
    }

    private func render(_ usages: [ProviderUsage]) {
        let segments = MenuBarTitleBuilder.segments(for: usages)
        let title = NSMutableAttributedString()
        for (i, seg) in segments.enumerated() {
            if i > 0 { title.append(NSAttributedString(string: "  ")) }
            // barevná tečka
            title.append(NSAttributedString(string: "● ", attributes: [
                .foregroundColor: dotColor(for: seg.providerId),
                .font: NSFont.systemFont(ofSize: 9)
            ]))
            title.append(NSAttributedString(string: seg.text, attributes: [
                .foregroundColor: color(for: seg.level),
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            ]))
        }
        if segments.isEmpty {
            title.append(NSAttributedString(string: "StatusBar"))
        }
        statusItem.button?.attributedTitle = title
        statusItem.button?.toolTip = usages
            .map { "\($0.displayName): \(statusText($0))" }
            .joined(separator: "\n")
    }

    private func statusText(_ u: ProviderUsage) -> String {
        switch u.status {
        case .ok: return "\(u.nearestLimitPercent) %"
        case .degraded(let m): return "⚠︎ \(m)"
        case .unavailable(let m): return "— \(m)"
        }
    }
}
```

- [ ] **Step 4: Napiš `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>StatusBar</string>
    <key>CFBundleIdentifier</key><string>cz.rivalio.statusbar</string>
    <key>CFBundleVersion</key><string>0.1</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>StatusBar</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
```

- [ ] **Step 5: Napiš `scripts/make-app.sh` (sestaví .app bundle)**

```bash
#!/usr/bin/env bash
set -euo pipefail
CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/StatusBarApp"
APP="StatusBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/StatusBar"
echo "Hotovo: $APP"
```

- [ ] **Step 6: Build, spusť a manuálně ověř (smoke test)**

```bash
chmod +x scripts/make-app.sh
swift build
./scripts/make-app.sh debug
open StatusBar.app
```
Expected:
- V menu baru se objeví widget se dvěma hodnotami (např. `● 8%  ● 2%` pro Claude / `—` pro Codex, pokud Codex nemá čerstvá data).
- Tooltip nad widgetem ukáže názvy poskytovatelů a stav.
- Žádné okno v Docku.
- **Validace Codexu:** Pokud Codex ukazuje `—`, spusť jednou `codex` v terminálu (ať zapíše čerstvou session s `rate_limits`), počkej do 60 s (nebo restartuj app) a ověř, že se objeví procento. Tím ověříš reálný formát `primary`/`secondary` z Tasku 4. Pokud se procento neobjeví ani po reálné session, zkontroluj inner názvy polí v nejnovější `~/.codex/sessions/**/*.jsonl` a uprav `CodexRateLimitParser.Window` (Task 4) + jeho fixturu/testy.

- [ ] **Step 7: Commit**

```bash
git add Sources/StatusBarApp/ Resources/Info.plist scripts/make-app.sh
git commit -m "feat: menu bar app shell (NSStatusItem, styl A) + packaging skript"
```

---

### Task 10: SwiftUI popover (panel A — karty)

**Files:**
- Create: `Sources/StatusBarApp/PopoverView.swift`
- Create: `Sources/StatusBarApp/UsageViewModel.swift`
- Modify: `Sources/StatusBarApp/MenuBarController.swift` (připojení popoveru na klik)
- Create: `Tests/StatusBarKitTests/WindowLabelTests.swift`

**Interfaces:**
- Consumes: `UsageStore`, `ProviderUsage`, `UsageWindow`, `WindowKind`, `ResetFormatter`, `UsageLevel`.
- Produces: `enum WindowLabel { static func text(for kind: WindowKind) -> String }` (čistá, testovaná), SwiftUI `PopoverView`, a klikací popover v `MenuBarController`.

- [ ] **Step 1: Napiš padající test `Tests/StatusBarKitTests/WindowLabelTests.swift`**

```swift
import Testing
@testable import StatusBarKit

@Test func popiskyOken() {
    #expect(WindowLabel.text(for: .rolling5h) == "5h okno")
    #expect(WindowLabel.text(for: .weekly(scope: nil)) == "Týden")
    #expect(WindowLabel.text(for: .weekly(scope: "Sonnet")) == "Týden · Sonnet")
}
```

- [ ] **Step 2: Spusť test — musí selhat**

Run: `swift test --filter WindowLabelTests`
Expected: FAIL ("cannot find 'WindowLabel'").

- [ ] **Step 3: Napiš `Sources/StatusBarKit/Formatting/WindowLabel.swift`**

```swift
public enum WindowLabel {
    public static func text(for kind: WindowKind) -> String {
        switch kind {
        case .rolling5h: return "5h okno"
        case .weekly(let scope):
            if let scope { return "Týden · \(scope)" }
            return "Týden"
        }
    }
}
```

- [ ] **Step 4: Spusť test — musí projít**

Run: `swift test --filter WindowLabelTests`
Expected: PASS (1 test).

- [ ] **Step 5: Napiš `Sources/StatusBarApp/UsageViewModel.swift`**

```swift
import SwiftUI
import StatusBarKit

/// Tenký převod úrovně na barvu pro SwiftUI.
enum UsageColor {
    static func color(forFraction f: Double) -> Color {
        switch UsageLevel.level(forPercent: Int((f * 100).rounded())) {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
```

- [ ] **Step 6: Napiš `Sources/StatusBarApp/PopoverView.swift`**

```swift
import SwiftUI
import StatusBarKit

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Spotřeba").font(.headline)
                Spacer()
                Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()

            if store.orderedUsages.isEmpty {
                Text("Načítám…").foregroundStyle(.secondary)
                    .padding(14)
            } else {
                ForEach(store.orderedUsages, id: \.providerId) { usage in
                    ProviderCard(usage: usage)
                    Divider()
                }
            }

            HStack {
                Spacer()
                Button("Konec", action: onQuit).buttonStyle(.borderless).font(.caption)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .frame(width: 320)
    }
}

private struct ProviderCard: View {
    let usage: ProviderUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(usage.providerId == .claudeCode ? Color(red: 0.85, green: 0.46, blue: 0.34)
                                                              : Color(red: 0.06, green: 0.64, blue: 0.50))
                    .frame(width: 9, height: 9)
                Text(usage.displayName).fontWeight(.semibold)
                Spacer()
            }
            switch usage.status {
            case .unavailable(let msg):
                Text(msg).font(.caption).foregroundStyle(.secondary)
            case .degraded(let msg):
                Text(msg).font(.caption2).foregroundStyle(.orange)
                windowsList
            case .ok:
                windowsList
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private var windowsList: some View {
        ForEach(Array(usage.windows.enumerated()), id: \.offset) { _, w in
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(WindowLabel.text(for: w.kind)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((w.usedFraction*100).rounded()))%").font(.caption).fontWeight(.semibold)
                    if let r = w.resetAt {
                        Text("· \(ResetFormatter.short(until: r, now: Date()))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: min(w.usedFraction, 1.0))
                    .tint(UsageColor.color(forFraction: w.usedFraction))
            }
        }
    }
}
```

- [ ] **Step 7: Uprav `MenuBarController.swift` — připoj popover na klik**

Přidej do `MenuBarController` (vlastnost + akce). Nahraď tělo `init` tak, aby tlačítko mělo akci, a doplň `togglePopover`:

```swift
// přidej vlastnost:
private let popover = NSPopover()

// na konci init, po render(...) a nastavení cancellable:
popover.behavior = .transient
popover.contentSize = NSSize(width: 320, height: 200)
popover.contentViewController = NSHostingController(rootView:
    PopoverView(store: store,
                onRefresh: onRefresh,
                onQuit: { NSApp.terminate(nil) }))
statusItem.button?.target = self
statusItem.button?.action = #selector(togglePopover)
```

A přidej metodu a import:

```swift
import SwiftUI   // nahoru k ostatním importům

@objc private func togglePopover() {
    guard let button = statusItem.button else { return }
    if popover.isShown {
        popover.performClose(nil)
    } else {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
```

- [ ] **Step 8: Spusť všechny testy + manuální smoke test**

```bash
swift test
./scripts/make-app.sh debug
open StatusBar.app
```
Expected:
- `swift test` projde celý (všechny tasky).
- Klik na widget v liště otevře popover s kartami Claude / Codex, bary s procenty a (kde jsou) odpočty resetů.
- Tlačítko ↻ vynutí refresh, „Konec" appku ukončí.

- [ ] **Step 9: Commit**

```bash
git add Sources/StatusBarApp/PopoverView.swift Sources/StatusBarApp/UsageViewModel.swift Sources/StatusBarKit/Formatting/WindowLabel.swift Sources/StatusBarApp/MenuBarController.swift Tests/StatusBarKitTests/WindowLabelTests.swift
git commit -m "feat: SwiftUI popover (panel A) s kartami a odpočty resetů"
```

---

## Hotová definice MVP v0.1

Po dokončení Tasku 10:
- V liště se zobrazují dvě procenta (Claude / Codex), barevně dle úrovně.
- Klik otevře panel s kartami, 5h/týdenními okny a odpočty resetů.
- Claude data z `~/.claude/.usage_cache.json`, Codex z nejnovější session.
- Chybějící/stará data degradují elegantně (`—` / ⚠︎), bez pádů.
- Jádro plně pokryté `swift test`.

## Co je MIMO v0.1 (další plány)
- **v0.2:** OpenAI API útrata (Admin API), „Dnes" tokeny z `~/.claude/projects/**/*.jsonl`, `PricingEstimator`, souhrn „Dnes celkem".
- **v0.3:** notifikace (prahy), přepínatelné styly lišty (B/C/D), obrazovka Nastavení, spouštět při přihlášení (`SMAppService`).
- **v1.0:** podpis, notarizace (`notarytool`), auto-update (Sparkle), Homebrew cask, README/dokumentace, veřejné vydání.
