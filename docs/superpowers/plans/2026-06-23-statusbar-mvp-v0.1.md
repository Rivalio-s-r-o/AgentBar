# Plan: StatusBar MVP v0.1

> Forged by plan-forge on 2026-06-23 · mode: AUDIT · depth: standard
> Executor profile: levný agent / junior vývojář bez kontextu projektu, s právem zapisovat do repa `~/Projects/StatusBar`, spouštět `swift`/`xcodebuild`/`git` a (jednorázově, v Tasku 0) `sudo xcode-select`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## 1. Objective & Definition of Done

- **Objective:** Nativní macOS menu bar app, která v liště ukazuje spotřebu/limity Claude Code a Codexu (styl A — dvě procenta) a po rozkliknutí panel s 5h/týdenními okny a odpočty resetů.
- **Definition of done (v0.1, ověřitelné):**
  1. `swift build` přeloží knihovnu i app bez chyb; `swift test` projde všemi testy (po Tasku 0 s nainstalovaným Xcode).
  2. `./scripts/make-app.sh debug && open StatusBar.app` → v menu baru se objeví widget se dvěma segmenty (Claude / Codex), barevně dle úrovně; bez ikony v Docku.
  3. Klik na widget otevře popover s kartami Claude/Codex, u každé **jen 5h a týdenní okna** s procentem a (kde data dovolí) odpočtem resetu.
  4. Chybějící/poškozená/stará data → poskytovatel ukáže `—`/⚠︎ s tooltipem, app nespadne; ostatní poskytovatel funguje dál.
  - **Vědomý descope (H6):** Řádky „Dnes" (tokeny) a „Dnes celkem ≈ $" z mockupu panelu A jsou **mimo v0.1** — patří do v0.2. Panel v0.1 = pouze okna. Tohle je záměrné zúžení, ne nedodělaný mockup.

## 2. Context & Constraints

- **Stack:** Swift 6 (`swift-tools-version: 6.0`), SwiftPM se dvěma cíli — knihovna `StatusBarKit` (čistá logika, testovatelná) a executable `StatusBarApp` (AppKit `NSStatusItem` + SwiftUI popover). Test framework: **Swift Testing** (`import Testing`, `@Test`, `#expect`).
- **Platforma:** macOS 14+.
- **Toolchain (ověřeno 2026-06-23):** Na stroji je Swift 6.3.2, ale jen **Command Line Tools** — `swift build`/`swift run` fungují (vč. AppKit/SwiftUI), ale **`swift test` selže** (`no such module 'Testing'` i `'XCTest'`). Proto **Task 0 instaluje plný Xcode**. Bez Tasku 0 nelze spustit žádný test.
- **Read-only:** Číst pouze `~/.claude/.usage_cache.json` a soubory `~/.codex/sessions/**/*.jsonl`. Nikdy do těchto stromů nezapisovat. Nikdy nelogovat surový obsah session souborů (obsahují konverzace) — jen rozparsovaná číselná okna.
- **Robustnost:** Žádné modály, žádné pády. Každý poskytovatel mapuje chybu na `.degraded`/`.unavailable`.
- **Jednotky:** `usedFraction` je desetinné 0.0–1.0+ (procenta /100). Zdroje uvádějí procenta. Hodnoty >100 % (overage) jsou validní.
- **Žádné vymyšlené hodnoty:** chybí-li údaj (např. plán), pole je `nil`.
- Commit po každém dokončeném tasku.

## 3. Assumptions

| # | Assumption | Status | Verified how / by which step |
|---|------------|--------|------------------------------|
| A1 | `~/.claude/.usage_cache.json` má pole `data.limits[]` s `kind`/`percent`/`resets_at`/`scope`/`is_active` | **verified** | Přečteno na stroji 2026-06-23 (Task 2 fixtura je redigovaná kopie) |
| A2 | Claude `resets_at` je ISO-8601 s frakcí a offsetem `+00:00`; `ISO8601DateFormatter` s `.withFractionalSeconds` ho parsuje (i 6 číslic) | **verified** | Empiricky zkompilováno a spuštěno 2026-06-23 |
| A3 | Codex okno je `{used_percent, window_minutes, resets_at}`, kde `resets_at` je **absolutní Unix epoch (Int)**; `resets_in_seconds` neexistuje | **verified** | `grep` napříč sessions: 0× `resets_in_seconds`, 7289× `resets_at`; vzorek přečten |
| A4 | `primary` NENÍ vždy 5h — okno se musí určit podle `window_minutes` (~300→5h, ~10080→týden) | **verified** | Nejnovější session měla `primary.window_minutes=10080` |
| A5 | Nejnovější session soubor často má `primary/secondary = null`; platná data mohou být ve starším souboru | **verified** | Nejnovější soubor na stroji má null limity, o 20 min starší má data |
| A6 | `swift test` vyžaduje plný Xcode; CLT nestačí | **verified** | `import Testing`/`import XCTest` pod CLT → „no such module" |
| A7 | AppKit+SwiftUI+`NSStatusItem`/`NSHostingController`/`NSPopover` se přeloží i pod CLT | **verified** | `swiftc -typecheck` prošel 2026-06-23 |
| A8 | `static let` non-Sendable formátteru je chyba pod Swift 6 | **verified** | `swift build` selhal na přesně tomto patternu |
| A9 | Codex data uživatele jsou ~46 dní stará → Codex bude `degraded`, dokud nespustí `codex` | **verified** | mtime nejnovější session ≈ 2026-05-08 |
| A10 | Plán Codexu lze získat z `plan_type` v události (`"plus"`) | **verified** | Přečteno ve vzorku |

## 4. Considered Alternatives

- **Struktura — SwiftPM (zvoleno) vs Xcode projekt (.xcodeproj).** SwiftPM dává čistě testovatelné jádro a buildy přes `swift build`/`run` bez GUI kroků (executor-friendly, lepší diffy). `.xcodeproj` by přidal GUI-only kroky a křehký pbxproj; jedinou výhodu (test bundle) stejně řeší až Xcode, který instalujeme v Tasku 0. → **SwiftPM**.
- **Claude zdroj limitů — `limits[]` z cache (zvoleno) vs per-key pole vs OAuth endpoint.** `limits[]` nese server-spočtené `percent`/`scope`/`is_active`/`resets_at` — stabilnější a bohatší než křehká per-key pole (`five_hour`/`seven_day`). OAuth endpoint = síť + token z Keychainu + větší blast radius; necháme jako fallback pro v0.2. Cache má nulovou síť, jen přidáme freshness guard. → **`limits[]` + freshness guard**.
- **Codex zdroj — session JSONL (zvoleno) vs jiný.** V `~/.codex` není žádný dedikovaný rate-limit cache soubor; jediný lokální zdroj jsou sessions. Riziko (zastarává) mitigujeme skenem N nejnovějších sessionů a stavem `degraded`. → **session JSONL, opravený výběr**.
- **Test loop — Xcode prereq (zvoleno) vs `swift run` smoke-runner.** Oba test frameworky vyžadují Xcode; uživatel ho stejně instaluje. Standardní pro open-source. → **Xcode jako Task 0**.

## 5. Guardrails

- **Forbidden actions:** Zápis do `~/.claude` nebo `~/.codex` (jakýkoliv). Logování/tisk surového obsahu session souborů. Čtení `~/.codex/auth.json` nebo Keychainu. Přidávání síťových volání ve v0.1.
- **⚠ Irreversible/escalated operations:** Task 0 spouští `sudo xcode-select -s /Applications/Xcode.app` (mění aktivní toolchain systému). Gate: provést až po ověření, že `/Applications/Xcode.app` existuje; zaznamenat předchozí hodnotu `xcode-select -p` pro případný návrat.
- **Global stop conditions:** Pokud `swift build` selže z důvodu mimo právě editovaný soubor → ZASTAV a nahlas (nepřepisuj nesouvisející kód). Pokud test selže jinak než očekávaným `#expect` → ZASTAV a nahlas výstup.
- **Kill criteria (odsouhlaseno na CP2):** Pokud po **Tasku 5** nejde z žádné reálné session na stroji (ani po čerstvém běhu `codex`) získat non-null Codex okna, NEBO selže instalace Xcode v Tasku 0 → ZASTAV celý plán a vrať se do forge přehodnotit zdroj Codex dat (OAuth/API). Časový strop: nefunguje-li MVP do **2026-07-07** (~2 týdny), zpět do forge.

## 6. Executor Preamble

> **Instrukce pro vykonavatele — předej spolu s celým plánem:**
> - Vykonávej kroky přesně v pořadí; nikdy nepřeskakuj, neslučuj ani nepřeskupuj. Začni Taskem 0.
> - Před každým krokem ověř jeho Preconditions; po každém kroku spusť „Verify success" a výsledek nahlas.
> - U TDD tasků platí: napřed vznikne stub (cíl se přeloží), test je proto **RED na assertu** (ne compile error). Pak doplň implementaci → GREEN.
> - Selže-li ověření jinak než očekávaným RED, nebo nastane globální stop podmínka (sekce 5), ZASTAV a nahlas stav — nikdy neimprovizuj.
> - Sekce 1 (definice hotového) je kompas; pokud realita ujíždí od záměru i při zelených checkech, ZASTAV a nahlas.
> - Kroky ⚠ proveď až po splnění brány.
> - Odškrtávej `- [x]` přímo v plánu. Formát hlášení: číslo kroku · akce · výstup ověření · stav (OK/FAILED/HALTED).

## 7. Execution Steps

### Task 0: ⚠ Instalace Xcode a přepnutí toolchainu

**Files:** žádné (systémový setup).

- [ ] **Action:** Ověř, zda `swift test` reálně kompiluje s modulem `Testing` (NE přes `--help` — to dává falešné OK, protože help modul nepotřebuje). Použij reálný probe ze sekce „Verify success" níže. Pokud selže na `no such module 'Testing'`: nainstaluj plný Xcode z App Store (nebo `xcodes`), pak ⚠ `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` a `sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch`.
- **Preconditions:** `/Applications/Xcode.app` existuje (jinak ZASTAV — viz Kill criteria). Před `xcode-select` si zaznamenej `xcode-select -p`.
- [ ] **Verify success:** `xcrun --find swift` ukazuje cestu uvnitř `Xcode.app`; a tato sekvence projde:
  ```bash
  mkdir -p /tmp/xctest-probe/Sources/P /tmp/xctest-probe/Tests/PTests
  cd /tmp/xctest-probe
  printf 'public func two() -> Int { 2 }\n' > Sources/P/P.swift
  printf '// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name:"P",targets:[.target(name:"P"),.testTarget(name:"PTests",dependencies:["P"])])\n' > Package.swift
  printf 'import Testing\n@testable import P\n@Test func t(){ #expect(two()==2) }\n' > Tests/PTests/T.swift
  swift test 2>&1 | tail -3
  ```
  Expected: `Test run with 1 test ... passed`.
- **On failure:** Pokud `swift test` stále hlásí „no such module 'Testing'", Xcode není správně vybraný → zkontroluj `xcode-select -p`. Pokud Xcode nelze nainstalovat → ZASTAV (Kill criteria).

---

### Task 1: Scaffold balíku + doménový model

**Files:**
- Create: `Package.swift`, `Sources/StatusBarKit/Models/ProviderUsage.swift`, `Tests/StatusBarKitTests/ProviderUsageTests.swift`, `Tests/StatusBarKitTests/Fixtures/.gitkeep`
- Modify: `.gitignore`

**Interfaces produkované:** `ProviderID`, `WindowKind`, `ProviderStatus`, `UsageWindow`, `ProviderUsage` (+ `nearestLimitFraction`, `nearestLimitPercent`, `static unavailable(...)`).

- [ ] **Step 1: `Package.swift`** (vytvoř)

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatusBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "StatusBarKit"),
        .executableTarget(name: "StatusBarApp", dependencies: ["StatusBarKit"]),
        .testTarget(
            name: "StatusBarKitTests",
            dependencies: ["StatusBarKit"],
            resources: [.copy("Fixtures")]   // adresář Fixtures/ musí existovat už teď (viz Step 2)
        ),
    ]
)
```

- [ ] **Step 2: Vytvoř prázdný `Tests/StatusBarKitTests/Fixtures/.gitkeep`** (M5 — `.copy` na neexistující cestu = build error)

Obsah souboru: jeden prázdný řádek.

- [ ] **Step 3: `.gitignore`** (přidej na konec)

```
.build/
*.app
DerivedData/
.swiftpm/
```

- [ ] **Step 4: Stub modelu `Sources/StatusBarKit/Models/ProviderUsage.swift`** (kompiluje se, computed property je schválně špatně → test bude RED)

```swift
import Foundation

public enum ProviderID: String, Sendable, CaseIterable {
    case claudeCode
    case codex
}

public enum WindowKind: Sendable, Equatable {
    case rolling5h
    case weekly(scope: String?)
}

public enum ProviderStatus: Sendable, Equatable {
    case ok
    case degraded(String)
    case unavailable(String)
}

public struct UsageWindow: Sendable, Equatable {
    public let kind: WindowKind
    public let usedFraction: Double
    public let resetAt: Date?
    public init(kind: WindowKind, usedFraction: Double, resetAt: Date?) {
        self.kind = kind; self.usedFraction = usedFraction; self.resetAt = resetAt
    }
}

public struct ProviderUsage: Sendable, Equatable {
    public let providerId: ProviderID
    public let displayName: String
    public let planLabel: String?
    public let windows: [UsageWindow]
    public let status: ProviderStatus
    public let lastUpdated: Date
    public init(providerId: ProviderID, displayName: String, planLabel: String?,
                windows: [UsageWindow], status: ProviderStatus, lastUpdated: Date) {
        self.providerId = providerId; self.displayName = displayName; self.planLabel = planLabel
        self.windows = windows; self.status = status; self.lastUpdated = lastUpdated
    }

    public var nearestLimitFraction: Double { 0 }            // STUB — schválně špatně
    public var nearestLimitPercent: Int { 0 }               // STUB

    public static func unavailable(_ id: ProviderID, displayName: String, reason: String, now: Date) -> ProviderUsage {
        ProviderUsage(providerId: id, displayName: displayName, planLabel: nil,
                      windows: [], status: .unavailable(reason), lastUpdated: now)
    }
}
```

- [ ] **Step 5: Test `Tests/StatusBarKitTests/ProviderUsageTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func nearestLimitPercentVracíMaximumZOken() {
    let u = ProviderUsage(providerId: .claudeCode, displayName: "Claude Code", planLabel: nil,
        windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.08, resetAt: nil),
                  UsageWindow(kind: .weekly(scope: nil), usedFraction: 0.61, resetAt: nil)],
        status: .ok, lastUpdated: Date(timeIntervalSince1970: 0))
    #expect(u.nearestLimitPercent == 61)
}

@Test func overagePřes100Procent() {  // M2
    let u = ProviderUsage(providerId: .codex, displayName: "Codex", planLabel: nil,
        windows: [UsageWindow(kind: .rolling5h, usedFraction: 1.05, resetAt: nil)],
        status: .ok, lastUpdated: Date(timeIntervalSince1970: 0))
    #expect(u.nearestLimitPercent == 105)
}

@Test func bezOkenJeNula() {
    let u = ProviderUsage.unavailable(.codex, displayName: "Codex", reason: "x", now: Date(timeIntervalSince1970: 0))
    #expect(u.nearestLimitPercent == 0)
}
```

- [ ] **Step 6: Run → RED.** `swift test --filter ProviderUsageTests` → Expected: 2 testy FAIL (`nearestLimitPercent` vrací 0), 1 PASS (bezOken).
- [ ] **Step 7: Implementuj computed properties** — nahraď oba STUB řádky:

```swift
    public var nearestLimitFraction: Double { windows.map(\.usedFraction).max() ?? 0 }
    public var nearestLimitPercent: Int { Int((nearestLimitFraction * 100).rounded()) }
```

- [ ] **Step 8: Run → GREEN.** `swift test --filter ProviderUsageTests` → Expected: 3 PASS.
- [ ] **Step 9: Commit.** `git add Package.swift .gitignore Sources/StatusBarKit/Models Tests/StatusBarKitTests && git commit -m "feat: scaffold SwiftPM + doménový model ProviderUsage"`
- **On failure:** Pokud Step 6 hlásí compile error (ne assert-fail) → cíl se nepřeložil; oprav typy, ne testy. ZASTAV při nejasnosti.

---

### Task 2: Claude parser z `limits[]` (H3) + lokální formatter (H1)

**Files:**
- Create: `Sources/StatusBarKit/Providers/ClaudeUsageCacheParser.swift`, `Tests/StatusBarKitTests/Fixtures/claude-usage-cache.json`, `Tests/StatusBarKitTests/ClaudeUsageCacheParserTests.swift`

**Interfaces:** `enum ClaudeUsageCacheParser { static func parse(_ data: Data) throws -> ProviderUsage }`.

Pozn.: Fixtura je **redigovaná kopie** reálného `data.limits[]` ze stroje (ne 1:1 celý soubor — reálný má i `extra_usage`/`spend`/další klíče, které v0.1 ignorujeme; `Decodable` extra klíče přeskočí).

- [ ] **Step 1: Fixtura `Tests/StatusBarKitTests/Fixtures/claude-usage-cache.json`**

```json
{"timestamp": 1782223012.474268, "data": {"limits": [
  {"kind":"session","group":"session","percent":8,"severity":"normal","resets_at":"2026-06-23T14:59:59.461210+00:00","scope":null,"is_active":true},
  {"kind":"weekly_all","group":"weekly","percent":2,"severity":"normal","resets_at":"2026-06-30T11:59:59.461233+00:00","scope":null,"is_active":false},
  {"kind":"weekly_scoped","group":"weekly","percent":12,"severity":"normal","resets_at":"2026-06-30T12:00:00.461241+00:00","scope":{"model":{"id":null,"display_name":"Sonnet"},"surface":null},"is_active":false}
]}}
```

- [ ] **Step 2: Stub parseru `Sources/StatusBarKit/Providers/ClaudeUsageCacheParser.swift`**

```swift
import Foundation

public enum ClaudeUsageCacheParser {
    public static func parse(_ data: Data) throws -> ProviderUsage {
        // STUB — vrátí prázdno, aby test byl RED
        return ProviderUsage(providerId: .claudeCode, displayName: "Claude Code", planLabel: nil,
                             windows: [], status: .ok, lastUpdated: Date(timeIntervalSince1970: 0))
    }
}
```

- [ ] **Step 3: Test `Tests/StatusBarKitTests/ClaudeUsageCacheParserTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

private func fixture(_ n: String) throws -> Data {
    try Data(contentsOf: Bundle.module.url(forResource: n, withExtension: "json", subdirectory: "Fixtures")!)
}

@Test func parseClaudeLimitsVytvoříOkna() throws {
    let u = try ClaudeUsageCacheParser.parse(fixture("claude-usage-cache"))
    #expect(u.providerId == .claudeCode)
    #expect(u.status == .ok)

    let five = u.windows.first { $0.kind == .rolling5h }
    #expect(abs((five?.usedFraction ?? -1) - 0.08) < 0.0001)
    #expect(five?.resetAt != nil)

    let weekAll = u.windows.first { $0.kind == .weekly(scope: nil) }
    #expect(abs((weekAll?.usedFraction ?? -1) - 0.02) < 0.0001)

    let weekSonnet = u.windows.first { $0.kind == .weekly(scope: "Sonnet") }
    #expect(abs((weekSonnet?.usedFraction ?? -1) - 0.12) < 0.0001)

    #expect(abs(u.lastUpdated.timeIntervalSince1970 - 1782223012.474268) < 0.001)
}

@Test func parseClaudeChybnýJSONHodí() {
    #expect(throws: (any Error).self) { _ = try ClaudeUsageCacheParser.parse(Data("nonsense".utf8)) }
}
```

- [ ] **Step 4: Run → RED.** `swift test --filter ClaudeUsageCacheParserTests` → Expected: `parseClaudeLimits...` FAIL (prázdná okna), `chybnýJSON` FAIL (stub nehodí).
- [ ] **Step 5: Implementuj parser** — nahraď celé tělo souboru:

```swift
import Foundation

public enum ClaudeUsageCacheParser {

    private struct Cache: Decodable { let timestamp: Double; let data: CacheData }
    private struct CacheData: Decodable { let limits: [LimitEntry] }
    private struct LimitEntry: Decodable {
        let kind: String
        let percent: Double
        let resets_at: String?
        let scope: Scope?
    }
    private struct Scope: Decodable { let model: Model? }
    private struct Model: Decodable { let display_name: String? }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    public static func parse(_ data: Data) throws -> ProviderUsage {
        let cache = try JSONDecoder().decode(Cache.self, from: data)
        let windows: [UsageWindow] = cache.data.limits.compactMap { e in
            let kind: WindowKind
            switch e.kind {
            case "session":       kind = .rolling5h
            case "weekly_all":    kind = .weekly(scope: nil)
            case "weekly_scoped": kind = .weekly(scope: e.scope?.model?.display_name)
            default: return nil
            }
            return UsageWindow(kind: kind, usedFraction: e.percent / 100.0, resetAt: parseDate(e.resets_at))
        }
        return ProviderUsage(providerId: .claudeCode, displayName: "Claude Code", planLabel: nil,
                             windows: windows, status: .ok,
                             lastUpdated: Date(timeIntervalSince1970: cache.timestamp))
    }
}
```

- [ ] **Step 6: Run → GREEN.** `swift test --filter ClaudeUsageCacheParserTests` → Expected: 2 PASS.
- [ ] **Step 7: Commit.** `git add Sources/StatusBarKit/Providers/ClaudeUsageCacheParser.swift Tests/StatusBarKitTests && git commit -m "feat: Claude parser z autoritativního limits[] + lokální ISO formatter"`

---

### Task 3: `UsageProvider` protokol + `ClaudeCodeCollector` s freshness (H5)

**Files:**
- Create: `Sources/StatusBarKit/Providers/UsageProvider.swift`, `Sources/StatusBarKit/Providers/ClaudeCodeCollector.swift`, `Tests/StatusBarKitTests/ClaudeCodeCollectorTests.swift`

**Interfaces:** `protocol UsageProvider: Sendable { var id: ProviderID { get }; func fetch() async -> ProviderUsage }`; `struct ClaudeCodeCollector: UsageProvider { init(cachePath: URL?, staleAfter: TimeInterval) }`.

- [ ] **Step 1: `Sources/StatusBarKit/Providers/UsageProvider.swift`**

```swift
import Foundation

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func fetch() async -> ProviderUsage
}
```

- [ ] **Step 2: Stub `Sources/StatusBarKit/Providers/ClaudeCodeCollector.swift`**

```swift
import Foundation

public struct ClaudeCodeCollector: UsageProvider {
    public let id: ProviderID = .claudeCode
    private let cachePath: URL
    private let staleAfter: TimeInterval

    public init(cachePath: URL? = nil, staleAfter: TimeInterval = 6 * 3600) {
        self.cachePath = cachePath ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.usage_cache.json")
        self.staleAfter = staleAfter
    }

    public func fetch() async -> ProviderUsage {
        return .unavailable(.claudeCode, displayName: "Claude Code", reason: "stub", now: Date()) // STUB
    }
}
```

- [ ] **Step 3: Test `Tests/StatusBarKitTests/ClaudeCodeCollectorTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

private func copyFixtureToTemp(now: Date) throws -> URL {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cc-\(UUID().uuidString).json")
    let src = Bundle.module.url(forResource: "claude-usage-cache", withExtension: "json", subdirectory: "Fixtures")!
    try FileManager.default.copyItem(at: src, to: tmp)
    return tmp
}

@Test func collectorPřečteCache() async throws {
    let tmp = try copyFixtureToTemp(now: Date())
    defer { try? FileManager.default.removeItem(at: tmp) }
    // staleAfter obrovský => i stará fixtura je ok
    let u = await ClaudeCodeCollector(cachePath: tmp, staleAfter: .greatestFiniteMagnitude).fetch()
    #expect(u.status == .ok)
    #expect(u.windows.isEmpty == false)
}

@Test func collectorStaráCacheJeDegraded() async throws {  // H5
    let tmp = try copyFixtureToTemp(now: Date())
    defer { try? FileManager.default.removeItem(at: tmp) }
    // fixtura má timestamp z minulosti => staleAfter 1 s => degraded
    let u = await ClaudeCodeCollector(cachePath: tmp, staleAfter: 1).fetch()
    if case .degraded = u.status {} else { Issue.record("čekán .degraded, byl \(u.status)") }
}

@Test func collectorChybějícíSouborUnavailable() async {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).json")
    let u = await ClaudeCodeCollector(cachePath: missing, staleAfter: 999).fetch()
    if case .unavailable = u.status {} else { Issue.record("čekán .unavailable") }
}
```

- [ ] **Step 4: Run → RED.** `swift test --filter ClaudeCodeCollectorTests` → Expected: `přečteCache` a `staráCache` FAIL (stub), `chybějícíSoubor` PASS.
- [ ] **Step 5: Implementuj `fetch()`** — nahraď tělo metody:

```swift
    public func fetch() async -> ProviderUsage {
        let now = Date()
        guard let data = try? Data(contentsOf: cachePath) else {
            return .unavailable(.claudeCode, displayName: "Claude Code",
                reason: "Soubor \(cachePath.lastPathComponent) nenalezen. Otevři Claude Code a spusť /usage.", now: now)
        }
        do {
            let usage = try ClaudeUsageCacheParser.parse(data)
            let age = now.timeIntervalSince(usage.lastUpdated)
            if age > staleAfter {
                return ProviderUsage(providerId: usage.providerId, displayName: usage.displayName,
                    planLabel: usage.planLabel, windows: usage.windows,
                    status: .degraded("Data stará \(Int(age/60)) min — otevři Claude Code."),
                    lastUpdated: usage.lastUpdated)
            }
            return usage
        } catch {
            return .unavailable(.claudeCode, displayName: "Claude Code",
                reason: "Cache nelze přečíst: \(error.localizedDescription)", now: now)
        }
    }
```

- [ ] **Step 6: Run → GREEN.** `swift test --filter ClaudeCodeCollectorTests` → Expected: 3 PASS.
- [ ] **Step 7: Commit.** `git add Sources/StatusBarKit/Providers Tests/StatusBarKitTests && git commit -m "feat: UsageProvider + ClaudeCodeCollector s freshness guardem"`

---

### Task 4: Codex parser — `resets_at` epoch (C1) + okno dle `window_minutes` (C2)

**Files:**
- Create: `Sources/StatusBarKit/Providers/CodexRateLimitParser.swift`, `Tests/StatusBarKitTests/Fixtures/codex-session-with-limits.jsonl`, `Tests/StatusBarKitTests/Fixtures/codex-session-null-limits.jsonl`, `Tests/StatusBarKitTests/CodexRateLimitParserTests.swift`

**Interfaces:** `struct CodexSnapshot: Sendable, Equatable { let windows: [UsageWindow]; let planType: String? }`; `enum CodexRateLimitParser { static func latestSnapshot(fromJSONL data: Data) -> CodexSnapshot? }`.

Pozn.: Fixtura `with-limits` je **reálný tvar** ze stroje (`resets_at` = Unix epoch Int, `window_minutes` 300/10080, `plan_type`). Okno se určuje podle `window_minutes`, NE podle pozice primary/secondary (A4).

- [ ] **Step 1: Fixtura `codex-session-with-limits.jsonl`**

```
{"timestamp":"2026-04-16T13:57:00.000Z","type":"session_meta","payload":{"id":"x"}}
{"timestamp":"2026-04-16T13:58:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":40.0,"window_minutes":300,"resets_at":1776353000},"secondary":{"used_percent":55.0,"window_minutes":10080,"resets_at":1776362000},"plan_type":"plus"}}}
{"timestamp":"2026-04-16T14:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":83.0,"window_minutes":300,"resets_at":1776353068},"secondary":{"used_percent":14.0,"window_minutes":10080,"resets_at":1776362552},"plan_type":"plus"}}}
```

- [ ] **Step 2: Fixtura `codex-session-null-limits.jsonl`**

```
{"timestamp":"2026-04-16T14:05:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":null,"secondary":null,"credits":null,"plan_type":"plus"}}}
```

- [ ] **Step 3: Stub `Sources/StatusBarKit/Providers/CodexRateLimitParser.swift`**

```swift
import Foundation

public struct CodexSnapshot: Sendable, Equatable {
    public let windows: [UsageWindow]
    public let planType: String?
    public init(windows: [UsageWindow], planType: String?) { self.windows = windows; self.planType = planType }
}

public enum CodexRateLimitParser {
    public static func latestSnapshot(fromJSONL data: Data) -> CodexSnapshot? { nil }  // STUB
}
```

- [ ] **Step 4: Test `Tests/StatusBarKitTests/CodexRateLimitParserTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

private func fx(_ n: String) throws -> Data {
    try Data(contentsOf: Bundle.module.url(forResource: n, withExtension: "jsonl", subdirectory: "Fixtures")!)
}

@Test func parserVezmePosledníUdálostAMapujePodleWindowMinutes() throws {
    let snap = CodexRateLimitParser.latestSnapshot(fromJSONL: try fx("codex-session-with-limits"))
    #expect(snap != nil)
    #expect(snap?.planType == "plus")

    // poslední událost: primary 83 % (300 min => 5h), secondary 14 % (10080 => týden)
    let five = snap?.windows.first { $0.kind == .rolling5h }
    #expect(abs((five?.usedFraction ?? -1) - 0.83) < 0.0001)
    // resets_at je absolutní epoch 1776353068
    #expect(abs((five?.resetAt?.timeIntervalSince1970 ?? 0) - 1776353068) < 0.5)

    let week = snap?.windows.first { $0.kind == .weekly(scope: nil) }
    #expect(abs((week?.usedFraction ?? -1) - 0.14) < 0.0001)
}

@Test func parserBezLimitůVrátíNil() throws {
    #expect(CodexRateLimitParser.latestSnapshot(fromJSONL: try fx("codex-session-null-limits")) == nil)
}
```

- [ ] **Step 5: Run → RED.** `swift test --filter CodexRateLimitParserTests` → Expected: `vezmePoslední...` FAIL (stub nil), `bezLimitů` PASS.
- [ ] **Step 6: Implementuj parser** — nahraď celé tělo souboru (ponech `CodexSnapshot`):

```swift
import Foundation

public struct CodexSnapshot: Sendable, Equatable {
    public let windows: [UsageWindow]
    public let planType: String?
    public init(windows: [UsageWindow], planType: String?) { self.windows = windows; self.planType = planType }
}

public enum CodexRateLimitParser {

    private struct Line: Decodable { let type: String?; let payload: Payload? }
    private struct Payload: Decodable { let type: String?; let rate_limits: RateLimits? }
    private struct RateLimits: Decodable { let primary: Window?; let secondary: Window?; let plan_type: String? }
    private struct Window: Decodable { let used_percent: Double?; let window_minutes: Double?; let resets_at: Double? }

    private static func window(from w: Window) -> UsageWindow? {
        guard let pct = w.used_percent else { return nil }
        // Okno určuj podle window_minutes: ~300 (5h) vs ~10080 (týden). Práh 1 den.
        let kind: WindowKind = (w.window_minutes ?? 0) < 1440 ? .rolling5h : .weekly(scope: nil)
        let reset = w.resets_at.map { Date(timeIntervalSince1970: $0) }
        return UsageWindow(kind: kind, usedFraction: pct / 100.0, resetAt: reset)
    }

    public static func latestSnapshot(fromJSONL data: Data) -> CodexSnapshot? {
        let decoder = JSONDecoder()
        var last: RateLimits?
        for raw in data.split(separator: UInt8(ascii: "\n")) {
            guard !raw.isEmpty,
                  let line = try? decoder.decode(Line.self, from: Data(raw)),
                  line.type == "event_msg", line.payload?.type == "token_count",
                  let rl = line.payload?.rate_limits,
                  rl.primary != nil || rl.secondary != nil
            else { continue }
            last = rl
        }
        guard let rl = last else { return nil }
        var windows: [UsageWindow] = []
        if let p = rl.primary, let w = window(from: p) { windows.append(w) }
        if let s = rl.secondary, let w = window(from: s) { windows.append(w) }
        guard !windows.isEmpty else { return nil }
        return CodexSnapshot(windows: windows, planType: rl.plan_type)
    }
}
```

- [ ] **Step 7: Run → GREEN.** `swift test --filter CodexRateLimitParserTests` → Expected: 2 PASS.
- [ ] **Step 8: Commit.** `git add Sources/StatusBarKit/Providers/CodexRateLimitParser.swift Tests/StatusBarKitTests && git commit -m "feat: Codex parser — resets_at epoch + okno dle window_minutes"`

---

### Task 5: `CodexCollector` — sken N nejnovějších sessionů (C3) + stream (H4)

**Files:**
- Create: `Sources/StatusBarKit/Providers/CodexCollector.swift`, `Tests/StatusBarKitTests/CodexCollectorTests.swift`

**Interfaces:** `struct CodexCollector: UsageProvider { init(sessionsDir: URL?, staleAfter: TimeInterval, maxFilesToScan: Int) }`.

- [ ] **Step 1: Stub `Sources/StatusBarKit/Providers/CodexCollector.swift`**

```swift
import Foundation

public struct CodexCollector: UsageProvider {
    public let id: ProviderID = .codex
    private let sessionsDir: URL
    private let staleAfter: TimeInterval
    private let maxFilesToScan: Int

    public init(sessionsDir: URL? = nil, staleAfter: TimeInterval = 24 * 3600, maxFilesToScan: Int = 10) {
        self.sessionsDir = sessionsDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        self.staleAfter = staleAfter
        self.maxFilesToScan = maxFilesToScan
    }

    public func fetch() async -> ProviderUsage {
        return .unavailable(.codex, displayName: "Codex", reason: "stub", now: Date()) // STUB
    }
}
```

- [ ] **Step 2: Test `Tests/StatusBarKitTests/CodexCollectorTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

private func place(_ fixture: String, into dir: URL, sub: String, mtime: Date) throws {
    let dest = dir.appendingPathComponent(sub)
    try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
    let src = Bundle.module.url(forResource: fixture, withExtension: "jsonl", subdirectory: "Fixtures")!
    try FileManager.default.copyItem(at: src, to: dest)
    try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: dest.path)
}

@Test func collectorPřeskočíNejnovějšíNullSessionAVezmeStarší() async throws {  // C3
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cx-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    // novější soubor = null limity; starší = platná data
    try place("codex-session-with-limits", into: root, sub: "a/older.jsonl", mtime: Date(timeIntervalSince1970: 1000))
    try place("codex-session-null-limits", into: root, sub: "a/newer.jsonl", mtime: Date(timeIntervalSince1970: 2000))

    let u = await CodexCollector(sessionsDir: root, staleAfter: .greatestFiniteMagnitude, maxFilesToScan: 10).fetch()
    #expect(u.windows.contains { $0.kind == .rolling5h })
    #expect(u.planLabel == "plus")
}

@Test func collectorBezSessionUnavailable() async {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cx-empty-\(UUID().uuidString)")
    let u = await CodexCollector(sessionsDir: root, staleAfter: 999, maxFilesToScan: 10).fetch()
    if case .unavailable = u.status {} else { Issue.record("čekán .unavailable") }
}
```

- [ ] **Step 3: Run → RED.** `swift test --filter CodexCollectorTests` → Expected: `přeskočí...` FAIL (stub), `bezSession` PASS.
- [ ] **Step 4: Implementuj `fetch()`** — nahraď tělo metody + přidej privátní helper:

```swift
    public func fetch() async -> ProviderUsage {
        let now = Date()
        let files = newestSessionFiles(limit: maxFilesToScan)   // od nejnovějšího
        guard !files.isEmpty else {
            return .unavailable(.codex, displayName: "Codex",
                reason: "Žádná session v ~/.codex/sessions. Spusť jednou `codex`.", now: now)
        }
        for f in files {
            guard let data = try? Data(contentsOf: f.url) else { continue }   // číst, NElogovat obsah
            guard let snap = CodexRateLimitParser.latestSnapshot(fromJSONL: data) else { continue }
            let age = now.timeIntervalSince(f.modified)
            let status: ProviderStatus = age > staleAfter
                ? .degraded("Data stará \(Int(age/3600)) h — spusť `codex` pro aktualizaci.")
                : .ok
            return ProviderUsage(providerId: .codex, displayName: "Codex",
                planLabel: snap.planType, windows: snap.windows, status: status, lastUpdated: f.modified)
        }
        return .unavailable(.codex, displayName: "Codex",
            reason: "V posledních \(maxFilesToScan) sessionech nejsou žádné limity.", now: now)
    }

    private func newestSessionFiles(limit: Int) -> [(url: URL, modified: Date)] {
        guard let en = FileManager.default.enumerator(at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var all: [(URL, Date)] = []
        for case let url as URL in en where url.pathExtension == "jsonl" {
            if let m = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                all.append((url, m))
            }
        }
        return all.sorted { $0.1 > $1.1 }.prefix(limit).map { (url: $0.0, modified: $0.1) }
    }
```

- [ ] **Step 5: Run → GREEN.** `swift test --filter CodexCollectorTests` → Expected: 2 PASS.
- [ ] **Step 6: ⚠ Reálná verifikace na stroji (A3/A5/Kill criteria).** Spusť jednou `codex` v terminálu (ať zapíše čerstvou session), pak:
  ```bash
  swift run StatusBarApp & sleep 3; kill %1 2>/dev/null  # nebo dočasný debug print v fetch()
  ```
  Lépe: dočasně přidej do `CodexCollector.fetch()` `print("CODEX windows=\(snap.windows.count) plan=\(snap.planType ?? "?")")` a spusť `swift run StatusBarApp` (po Tasku 9). Expected: aspoň 1 okno. **Pokud ani po čerstvém `codex` běhu nejsou okna → ZASTAV (Kill criteria).** Bez čerstvého běhu je `degraded`/`—` OČEKÁVANÝ stav (data uživatele jsou ~46 dní stará) — nehledej v tom bug. Debug print pak odstraň.
- [ ] **Step 7: Commit.** `git add Sources/StatusBarKit/Providers/CodexCollector.swift Tests/StatusBarKitTests && git commit -m "feat: CodexCollector — sken N nejnovějších sessionů, plan label"`

---

### Task 6: `UsageStore` + dávkový `replaceAll` (M3)

**Files:** Create: `Sources/StatusBarKit/Store/UsageStore.swift`, `Tests/StatusBarKitTests/UsageStoreTests.swift`

**Interfaces:** `@MainActor final class UsageStore: ObservableObject` s `@Published private(set) var providers: [ProviderID: ProviderUsage]`, `replaceAll(_ usages: [ProviderUsage])`, `orderedUsages`, `worstPercent`.

- [ ] **Step 1: Stub `Sources/StatusBarKit/Store/UsageStore.swift`**

```swift
import Foundation
import Combine

@MainActor
public final class UsageStore: ObservableObject {
    @Published public private(set) var providers: [ProviderID: ProviderUsage] = [:]
    public init() {}
    public func replaceAll(_ usages: [ProviderUsage]) { }   // STUB
    public var orderedUsages: [ProviderUsage] { [] }        // STUB
    public var worstPercent: Int { 0 }                      // STUB
}
```

- [ ] **Step 2: Test `Tests/StatusBarKitTests/UsageStoreTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

@MainActor @Test func storeReplaceAllAWorstPercent() {
    let store = UsageStore()
    store.replaceAll([
        ProviderUsage(providerId: .codex, displayName: "Codex", planLabel: nil,
            windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.78, resetAt: nil)], status: .ok, lastUpdated: Date()),
        ProviderUsage(providerId: .claudeCode, displayName: "Claude Code", planLabel: nil,
            windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.42, resetAt: nil)], status: .ok, lastUpdated: Date()),
    ])
    #expect(store.providers.count == 2)
    #expect(store.worstPercent == 78)
    #expect(store.orderedUsages.map(\.providerId) == [.claudeCode, .codex])  // pořadí dle ProviderID.allCases
}
```

- [ ] **Step 3: Run → RED.** `swift test --filter UsageStoreTests` → Expected: FAIL.
- [ ] **Step 4: Implementuj** — nahraď tři STUB členy:

```swift
    public func replaceAll(_ usages: [ProviderUsage]) {
        providers = Dictionary(uniqueKeysWithValues: usages.map { ($0.providerId, $0) })
    }
    public var orderedUsages: [ProviderUsage] { ProviderID.allCases.compactMap { providers[$0] } }
    public var worstPercent: Int { orderedUsages.map(\.nearestLimitPercent).max() ?? 0 }
```

- [ ] **Step 5: Run → GREEN.** `swift test --filter UsageStoreTests` → Expected: PASS.
- [ ] **Step 6: Commit.** `git add Sources/StatusBarKit/Store Tests/StatusBarKitTests && git commit -m "feat: UsageStore s dávkovým replaceAll"`

---

### Task 7: `RefreshCoordinator` — jeden zápis na refresh (M3)

**Files:** Create: `Sources/StatusBarKit/Store/RefreshCoordinator.swift`, `Tests/StatusBarKitTests/RefreshCoordinatorTests.swift`

**Interfaces:** `@MainActor final class RefreshCoordinator { init(store: UsageStore, providers: [any UsageProvider]); func refreshNow() async }`.

- [ ] **Step 1: Stub `Sources/StatusBarKit/Store/RefreshCoordinator.swift`**

```swift
import Foundation

@MainActor
public final class RefreshCoordinator {
    private let store: UsageStore
    private let providers: [any UsageProvider]
    public init(store: UsageStore, providers: [any UsageProvider]) { self.store = store; self.providers = providers }
    public func refreshNow() async { }   // STUB
}
```

- [ ] **Step 2: Test `Tests/StatusBarKitTests/RefreshCoordinatorTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

private struct Stub: UsageProvider {
    let id: ProviderID; let frac: Double
    func fetch() async -> ProviderUsage {
        ProviderUsage(providerId: id, displayName: id.rawValue, planLabel: nil,
            windows: [UsageWindow(kind: .rolling5h, usedFraction: frac, resetAt: nil)], status: .ok, lastUpdated: Date())
    }
}

@MainActor @Test func refreshNowNaplníStoreJednímZápisem() async {
    let store = UsageStore()
    await RefreshCoordinator(store: store, providers: [Stub(id: .claudeCode, frac: 0.3), Stub(id: .codex, frac: 0.9)]).refreshNow()
    #expect(store.providers.count == 2)
    #expect(store.worstPercent == 90)
}
```

- [ ] **Step 3: Run → RED.** `swift test --filter RefreshCoordinatorTests` → Expected: FAIL (count 0).
- [ ] **Step 4: Implementuj `refreshNow()`** — sbírej výsledky, pak JEDEN `replaceAll`:

```swift
    public func refreshNow() async {
        var results: [ProviderUsage] = []
        await withTaskGroup(of: ProviderUsage.self) { group in
            for p in providers { group.addTask { await p.fetch() } }
            for await u in group { results.append(u) }
        }
        store.replaceAll(results)
    }
```

- [ ] **Step 5: Run → GREEN.** `swift test --filter RefreshCoordinatorTests` → Expected: PASS.
- [ ] **Step 6: Commit.** `git add Sources/StatusBarKit/Store/RefreshCoordinator.swift Tests/StatusBarKitTests && git commit -m "feat: RefreshCoordinator — paralelní fetch, jeden zápis na refresh"`

---

### Task 8: Formátování lišty (styl A) + reset + popisky

**Files:** Create: `Sources/StatusBarKit/Formatting/{UsageLevel,MenuBarTitleBuilder,ResetFormatter,WindowLabel}.swift` (lze sloučit do jednoho), `Tests/StatusBarKitTests/FormattingTests.swift`

**Interfaces:** `enum UsageLevel { case normal,warning,critical; static func level(forPercent:) }`; `struct MenuBarSegment: Equatable { providerId; text; level }`; `enum MenuBarTitleBuilder { static func segments(for:) -> [MenuBarSegment] }`; `enum ResetFormatter { static func short(until:now:) -> String }`; `enum WindowLabel { static func text(for:) -> String }`.

- [ ] **Step 1: Stub `Sources/StatusBarKit/Formatting/Formatting.swift`**

```swift
import Foundation

public enum UsageLevel: Sendable, Equatable {
    case normal, warning, critical
    public static func level(forPercent p: Int) -> UsageLevel { .normal }   // STUB
}

public struct MenuBarSegment: Sendable, Equatable {
    public let providerId: ProviderID; public let text: String; public let level: UsageLevel
    public init(providerId: ProviderID, text: String, level: UsageLevel) {
        self.providerId = providerId; self.text = text; self.level = level
    }
}

public enum MenuBarTitleBuilder {
    public static func segments(for usages: [ProviderUsage]) -> [MenuBarSegment] { [] }   // STUB
}

public enum ResetFormatter {
    public static func short(until date: Date, now: Date) -> String { "" }   // STUB
}

public enum WindowLabel {
    public static func text(for kind: WindowKind) -> String { "" }   // STUB
}
```

- [ ] **Step 2: Test `Tests/StatusBarKitTests/FormattingTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func úrovněPodleProcent() {
    #expect(UsageLevel.level(forPercent: 10) == .normal)
    #expect(UsageLevel.level(forPercent: 80) == .warning)
    #expect(UsageLevel.level(forPercent: 95) == .critical)
    #expect(UsageLevel.level(forPercent: 130) == .critical)   // overage M2
}

@Test func segmentyStyluA() {
    let usages = [
        ProviderUsage(providerId: .claudeCode, displayName: "Claude Code", planLabel: nil,
            windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.42, resetAt: nil)], status: .ok, lastUpdated: Date()),
        ProviderUsage(providerId: .codex, displayName: "Codex", planLabel: nil,
            windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.92, resetAt: nil)], status: .ok, lastUpdated: Date()),
    ]
    let s = MenuBarTitleBuilder.segments(for: usages)
    #expect(s[0] == MenuBarSegment(providerId: .claudeCode, text: "42%", level: .normal))
    #expect(s[1] == MenuBarSegment(providerId: .codex, text: "92%", level: .critical))
}

@Test func segmentNedostupný() {
    let u = [ProviderUsage.unavailable(.claudeCode, displayName: "Claude Code", reason: "x", now: Date())]
    #expect(MenuBarTitleBuilder.segments(for: u)[0] == MenuBarSegment(providerId: .claudeCode, text: "—", level: .normal))
}

@Test func resetFormat() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(ResetFormatter.short(until: Date(timeIntervalSince1970: 2*3600+14*60), now: now) == "2h 14m")
    #expect(ResetFormatter.short(until: Date(timeIntervalSince1970: 41*60), now: now) == "41m")
    #expect(ResetFormatter.short(until: Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 100)) == "teď")
}

@Test func popiskyOken() {
    #expect(WindowLabel.text(for: .rolling5h) == "5h okno")
    #expect(WindowLabel.text(for: .weekly(scope: nil)) == "Týden")
    #expect(WindowLabel.text(for: .weekly(scope: "Sonnet")) == "Týden · Sonnet")
}
```

- [ ] **Step 3: Run → RED.** `swift test --filter FormattingTests` → Expected: FAIL.
- [ ] **Step 4: Implementuj** — nahraď čtyři STUB těla:

```swift
    // UsageLevel.level:
    public static func level(forPercent p: Int) -> UsageLevel {
        switch p { case ..<75: return .normal; case 75..<90: return .warning; default: return .critical }
    }
    // MenuBarTitleBuilder.segments:
    public static func segments(for usages: [ProviderUsage]) -> [MenuBarSegment] {
        usages.map { u in
            if case .unavailable = u.status { return MenuBarSegment(providerId: u.providerId, text: "—", level: .normal) }
            let p = u.nearestLimitPercent
            return MenuBarSegment(providerId: u.providerId, text: "\(p)%", level: UsageLevel.level(forPercent: p))
        }
    }
    // ResetFormatter.short:
    public static func short(until date: Date, now: Date) -> String {
        let s = Int(date.timeIntervalSince(now)); guard s > 0 else { return "teď" }
        let h = s/3600, m = (s%3600)/60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
    // WindowLabel.text:
    public static func text(for kind: WindowKind) -> String {
        switch kind { case .rolling5h: return "5h okno"
        case .weekly(let s): return s.map { "Týden · \($0)" } ?? "Týden" }
    }
```

- [ ] **Step 5: Run → GREEN.** `swift test` → Expected: VŠECHNY dosavadní testy PASS.
- [ ] **Step 6: Commit.** `git add Sources/StatusBarKit/Formatting Tests/StatusBarKitTests && git commit -m "feat: formátování lišty (styl A), resetu a popisků oken"`

---

### Task 9: App shell — `NSStatusItem`, časovač, packaging (M4)

**Files:** Create: `Sources/StatusBarApp/{main,AppDelegate,MenuBarController}.swift`, `Resources/Info.plist`, `scripts/make-app.sh`

**Interfaces:** spustitelná menu bar app; `MenuBarController(store:onClick:)` renderuje store → `NSStatusItem`. (Popover doplní Task 10.) UI = manuální smoke test.

- [ ] **Step 1: `Sources/StatusBarApp/main.swift`**

```swift
import AppKit
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 2: `Sources/StatusBarApp/AppDelegate.swift`**

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
        coordinator = RefreshCoordinator(store: store, providers: [ClaudeCodeCollector(), CodexCollector()])
        menuBar = MenuBarController(store: store, onClick: { [weak self] in
            Task { await self?.coordinator.refreshNow() }
        })
        Task { await coordinator.refreshNow() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.coordinator.refreshNow() }
        }
    }
}
```

- [ ] **Step 3: `Sources/StatusBarApp/MenuBarController.swift`** (v Tasku 10 sem přibude popover — viz Task 10 Step 7, který uvádí CELÉ výsledné tělo)

```swift
import AppKit
import Combine
import StatusBarKit

@MainActor
final class MenuBarController {
    private let store: UsageStore
    private let onClick: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellable: AnyCancellable?

    init(store: UsageStore, onClick: @escaping () -> Void) {
        self.store = store
        self.onClick = onClick
        render(store.orderedUsages)
        // replaceAll → jeden objectWillChange na refresh → jeden render (žádný flicker, M3)
        cancellable = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.render(self?.store.orderedUsages ?? []) }
        }
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleClick)
    }

    @objc private func handleClick() { onClick() }

    private func levelColor(_ l: UsageLevel) -> NSColor {
        switch l { case .normal: return .labelColor; case .warning: return .systemOrange; case .critical: return .systemRed }
    }
    private func dotColor(_ id: ProviderID) -> NSColor {
        switch id {
        case .claudeCode: return NSColor(red: 0.85, green: 0.46, blue: 0.34, alpha: 1)
        case .codex: return NSColor(red: 0.06, green: 0.64, blue: 0.50, alpha: 1)
        }
    }

    private func render(_ usages: [ProviderUsage]) {
        let segs = MenuBarTitleBuilder.segments(for: usages)
        let title = NSMutableAttributedString()
        for (i, s) in segs.enumerated() {
            if i > 0 { title.append(NSAttributedString(string: "  ")) }
            title.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: dotColor(s.providerId), .font: NSFont.systemFont(ofSize: 9)]))
            title.append(NSAttributedString(string: s.text, attributes: [.foregroundColor: levelColor(s.level), .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)]))
        }
        if segs.isEmpty { title.append(NSAttributedString(string: "StatusBar")) }
        statusItem.button?.attributedTitle = title
        statusItem.button?.toolTip = usages.map { u -> String in
            switch u.status {
            case .ok: return "\(u.displayName): \(u.nearestLimitPercent) %"
            case .degraded(let m): return "\(u.displayName): ⚠︎ \(m)"
            case .unavailable(let m): return "\(u.displayName): — \(m)"
            }
        }.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: `Resources/Info.plist`**

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

- [ ] **Step 5: `scripts/make-app.sh`** (M4 — ad-hoc podpis kvůli Gatekeeperu)

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
codesign --force --sign - "$APP"   # ad-hoc podpis, jinak Gatekeeper blokuje
echo "Hotovo: $APP"
```

- [ ] **Step 6: Build + smoke test.**
  ```bash
  chmod +x scripts/make-app.sh
  swift build
  ./scripts/make-app.sh debug
  open StatusBar.app
  ```
  Expected: v menu baru widget se dvěma segmenty (Claude % barevně; Codex pravděpodobně `—`/⚠︎, protože data uživatele jsou stará — **to je OČEKÁVANÉ**, viz Task 5 Step 6). Tooltip ukazuje stav. Žádná ikona v Docku. Při prvním spuštění může Gatekeeper vyžadovat pravý klik → Otevřít.
- [ ] **Step 7: Commit.** `git add Sources/StatusBarApp Resources/Info.plist scripts/make-app.sh && git commit -m "feat: menu bar app shell (NSStatusItem styl A) + podepsaný packaging"`

---

### Task 10: SwiftUI popover (panel A — jen okna)

**Files:** Create: `Sources/StatusBarApp/PopoverView.swift`, `Sources/StatusBarApp/UsageColor.swift`; Modify: `Sources/StatusBarApp/MenuBarController.swift` (celé nové tělo init níže — A10/M6).

**Interfaces:** SwiftUI `PopoverView(store:onRefresh:onQuit:)`; `enum UsageColor`.

- [ ] **Step 1: `Sources/StatusBarApp/UsageColor.swift`**

```swift
import SwiftUI
import StatusBarKit

enum UsageColor {
    static func color(forFraction f: Double) -> Color {
        switch UsageLevel.level(forPercent: Int((f * 100).rounded())) {
        case .normal: return .green; case .warning: return .orange; case .critical: return .red
        }
    }
}
```

- [ ] **Step 2: `Sources/StatusBarApp/PopoverView.swift`**

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
                Text("Spotřeba").font(.headline); Spacer()
                Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
            }.padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            if store.orderedUsages.isEmpty {
                Text("Načítám…").foregroundStyle(.secondary).padding(14)
            } else {
                ForEach(store.orderedUsages, id: \.providerId) { ProviderCard(usage: $0); Divider() }
            }
            HStack { Spacer(); Button("Konec", action: onQuit).buttonStyle(.borderless).font(.caption) }
                .padding(.horizontal, 14).padding(.vertical, 8)
        }.frame(width: 320)
    }
}

private struct ProviderCard: View {
    let usage: ProviderUsage
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(usage.providerId == .claudeCode ? Color(red:0.85,green:0.46,blue:0.34) : Color(red:0.06,green:0.64,blue:0.50)).frame(width: 9, height: 9)
                Text(usage.displayName).fontWeight(.semibold)
                if let p = usage.planLabel { Text(p).font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }
            switch usage.status {
            case .unavailable(let m): Text(m).font(.caption).foregroundStyle(.secondary)
            case .degraded(let m): Text(m).font(.caption2).foregroundStyle(.orange); windowsList
            case .ok: windowsList
            }
        }.padding(.horizontal, 14).padding(.vertical, 11)
    }
    private var windowsList: some View {
        ForEach(Array(usage.windows.enumerated()), id: \.offset) { _, w in
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(WindowLabel.text(for: w.kind)).font(.caption).foregroundStyle(.secondary); Spacer()
                    Text("\(Int((w.usedFraction*100).rounded()))%").font(.caption).fontWeight(.semibold)
                    if let r = w.resetAt { Text("· \(ResetFormatter.short(until: r, now: Date()))").font(.caption2).foregroundStyle(.secondary) }
                }
                ProgressView(value: min(w.usedFraction, 1.0)).tint(UsageColor.color(forFraction: w.usedFraction))  // clamp pro overage (M2)
            }
        }
    }
}
```

- [ ] **Step 3: Nahraď CELÝ `MenuBarController.swift`** tímto (přidává popover; A10 — uvádím celé tělo, ne „přidej na konec"):

```swift
import AppKit
import Combine
import SwiftUI
import StatusBarKit

@MainActor
final class MenuBarController {
    private let store: UsageStore
    private let onRefresh: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?

    init(store: UsageStore, onClick: @escaping () -> Void) {
        self.store = store
        self.onRefresh = onClick
        render(store.orderedUsages)
        cancellable = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.render(self?.store.orderedUsages ?? []) }
        }
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 240)
        popover.contentViewController = NSHostingController(rootView:
            PopoverView(store: store, onRefresh: onClick, onQuit: { NSApp.terminate(nil) }))
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
    }

    @objc private func togglePopover() {
        guard let b = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            onRefresh()  // refresh při otevření
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func levelColor(_ l: UsageLevel) -> NSColor {
        switch l { case .normal: return .labelColor; case .warning: return .systemOrange; case .critical: return .systemRed }
    }
    private func dotColor(_ id: ProviderID) -> NSColor {
        switch id {
        case .claudeCode: return NSColor(red: 0.85, green: 0.46, blue: 0.34, alpha: 1)
        case .codex: return NSColor(red: 0.06, green: 0.64, blue: 0.50, alpha: 1)
        }
    }
    private func render(_ usages: [ProviderUsage]) {
        let segs = MenuBarTitleBuilder.segments(for: usages)
        let title = NSMutableAttributedString()
        for (i, s) in segs.enumerated() {
            if i > 0 { title.append(NSAttributedString(string: "  ")) }
            title.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: dotColor(s.providerId), .font: NSFont.systemFont(ofSize: 9)]))
            title.append(NSAttributedString(string: s.text, attributes: [.foregroundColor: levelColor(s.level), .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)]))
        }
        if segs.isEmpty { title.append(NSAttributedString(string: "StatusBar")) }
        statusItem.button?.attributedTitle = title
        statusItem.button?.toolTip = usages.map { u -> String in
            switch u.status {
            case .ok: return "\(u.displayName): \(u.nearestLimitPercent) %"
            case .degraded(let m): return "\(u.displayName): ⚠︎ \(m)"
            case .unavailable(let m): return "\(u.displayName): — \(m)"
            }
        }.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: `swift test` → GREEN** (žádné nové unit testy; ověř, že se nic nerozbilo). Expected: všechny testy PASS.
- [ ] **Step 5: Smoke test.** `./scripts/make-app.sh debug && open StatusBar.app` → klik na widget otevře popover s kartami; bary mají procenta, u Claude i odpočty resetů; ↻ refreshne, „Konec" ukončí.
- [ ] **Step 6: Commit.** `git add Sources/StatusBarApp && git commit -m "feat: SwiftUI popover (panel A — okna) + klikací popover v liště"`

## 8. Rollback & Recovery

- Každý task = samostatný commit. Návrat: `git revert <hash>` nebo `git reset --hard <hash předchozího tasku>` (jen lokální větev, nic nepublikováno).
- **Task 0** je jediný se systémovým dopadem: návrat `sudo xcode-select -s <předchozí cesta>` (zaznamenaná před změnou). Instalace Xcode je aditivní (nelze „rollbacknout" smysluplně, ani není třeba).
- Žádný krok nemění data uživatele ani vzdálené systémy → mimo Task 0 je vše plně reverzibilní přes git.

## 9. Risk Register

| ID | Severity | Likelihood | Risk | Mitigation (step) | Resolution |
|----|----------|------------|------|-------------------|------------|
| C1 | CRIT | Certain | Codex `resets_in_seconds` neexistuje → odpočet vždy prázdný | Task 4 dekóduje `resets_at` epoch | fixed-in-Task-4 |
| C2 | CRIT | Certain | `primary` ≠ vždy 5h → záměna oken | Task 4 mapuje dle `window_minutes` | fixed-in-Task-4 |
| C3 | CRIT | Certain | Nejnovější session má null limity → Codex `—` | Task 5 skenuje N nejnovějších | fixed-in-Task-5 |
| C4 | CRIT | Certain | `swift test` pod CLT nejede | Task 0 instaluje Xcode | fixed-in-Task-0 |
| H1 | HIGH | Certain | static formatter se nepřeloží (Swift 6) | Task 2 formatter lokálně | fixed-in-Task-2 |
| H2 | HIGH | Certain | SwiftPM whole-target → „red" je compile error | TDD stub-first ve všech taskách | fixed (stub-first) |
| H3 | HIGH | High | Křehká per-key pole, ignoruje `limits[]` | Task 2 čte `limits[]` | fixed-in-Task-2 (CP2: A) |
| H4 | HIGH | High | Slurpování konverzací do paměti/logu | Task 5: nelogovat obsah; guardrail | fixed-in-Task-5 |
| H5 | HIGH | High | Claude bez freshness guardu | Task 3 `staleAfter` → degraded | fixed-in-Task-3 |
| H6 | HIGH | Certain | Goal drift: panel slibuje „Dnes" | DoD §1 explicitní descope | accepted-by-user (CP2: A) |
| H7 | HIGH | High | Codex data 46 dní stará → trvale degraded | Task 5 Step 6 dokumentuje očekávané | accepted-by-user |
| M1 | MED | Med | Fixtura ≠ 1:1 realita | Task 2 pozn. „redigovaná kopie" | fixed-in-Task-2 |
| M2 | MED | Med | Overage >100 % netestováno | Task 1/8 test + clamp v ProgressView | fixed-in-Task-1/8/10 |
| M3 | MED | Med | Render uprostřed dávky (flicker) | `replaceAll` → jeden render | fixed-in-Task-6/7/9 |
| M4 | MED | Med | Nepodepsaná `.app` blokována Gatekeeperem | `codesign -s -` v make-app.sh | fixed-in-Task-9 |
| M5 | MED | Low | `.copy(Fixtures)` na neexistující cestu | Task 1 `.gitkeep` | fixed-in-Task-1 |
| M6 | MED | Low | Task 10 textová editace init → nekonzistence | Task 10 uvádí celé tělo | fixed-in-Task-10 |

## 10. Audit Trail

- **Lenses applied:** 1 red-team, 2 security, 3 assumptions, 4 dependencies, 5 alternatives, 6 executability (z velké části empiricky kompilací), 7 goal-fit. Lensy 2–5,7 běžely jako 3 nezávislé subagenty + autorské empirické ověření.
- **Findings:** 4 CRIT, 7 HIGH, 6 MED (+ LOW) → všechny CRIT/HIGH fixed nebo accepted-by-user; všechny vyjmenované MED fixed (fix-scope CP2: A).
- **Re-audit po hardeningu (R*):** viz tabletop dry-run níže.
- **Tabletop dry run:** proveden — sled stavů Task 0→10 ověřen, identifikátory konzistentní (`onClick`/`onRefresh`, `replaceAll`, `latestSnapshot`, `CodexSnapshot`, `staleAfter`). Nalezené drobnosti opraveny inline před dodáním.
- **Key changes vs draft v0:**
  - C1/C2 → Codex parser čte reálné `resets_at`+`window_minutes` (dřív vymyšlené `resets_in_seconds`).
  - C3 → CodexCollector skenuje N nejnovějších sessionů (dřív jen nejnovější soubor).
  - C4 → přidán Task 0 (Xcode) jako tvrdá podmínka testů.
  - H1 → lokální ISO formatter (dřív nepřeložitelný static).
  - H2 → TDD přefrázováno na stub-first (dřív „test selže" = compile error).
  - H3 → Claude čte autoritativní `limits[]` (dřív per-key pole).
  - H4/H5 → Codex nelogování obsahu + Claude freshness guard.
  - H6 → DoD explicitně zúženo (panel = jen okna ve v0.1).
- **Decisions by user at CP2:** fix-scope = CRIT+HIGH+MED; test loop = Xcode Task 0; Claude zdroj = `limits[]`; panel v0.1 = jen okna (descope). Kill criteria odsouhlasena.
- **Open items to watch:** Task 5 Step 6 reálné ověření Codexu na stroji (Kill criteria gate); Codex pro tohoto uživatele bude `degraded`, dokud nespustí `codex`.
