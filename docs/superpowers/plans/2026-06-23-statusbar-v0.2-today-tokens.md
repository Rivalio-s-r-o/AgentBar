# StatusBar v0.2 — Dnešní tokeny & odhady cen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> Forged by plan-forge on 2026-06-23 · mode: AUDIT · depth: standard (7 lenses)
> Executor profile: subagent-driven — levní implementeři (Sonnet) podle přesného zadání + reviewer (Opus). Předpokládej nulový kontext projektu; dělej přesně, co je napsáno.

**Goal:** Do popoveru přidat ke kartám Claude a Codex řádek „Dnes" (tokeny + odhad ceny v API cenách), u Claude rozpad podle modelu, a do hlavičky souhrn „Dnes celkem ≈ $X".

**Architecture:** Nové čisté jednotky v `StatusBarKit` (`TokenUsage`/`ModelTokens`/`TodayUsage` model, `PricingTable`/`PricingEstimator`, `ClaudeTokenScanner`, `CodexTokenScanner`). `ProviderUsage` se rozšíří o volitelné `today: TodayUsage?` + copy-helper `with(today:)`, který collectory vyplní při `fetch()`. Limit-část z v0.1 zůstává nedotčená. UI vrstva (`PopoverView`) dostane řádky „Dnes" a hlavičkový souhrn.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing, AppKit/SwiftUI. macOS 14+. Navazuje na v0.1 (`main` na commitu `21c7f2c`).

## Global Constraints

- Cílová platforma macOS 14+, Swift 6 (`swift-tools-version: 6.0`), Swift Testing (`@Test`/`#expect`), `swift test` (vyžaduje Xcode — je nainstalovaný).
- **Čtení jen pro čtení**; nikdy nezapisovat do `~/.claude` ani `~/.codex`; nikdy nelogovat/printovat surový obsah konverzací — parsery extrahují **jen číselná/enum pole**, žádné `print` celých řádků.
- Nečíst `~/.codex/auth.json` ani Keychain. Scannery sahají jen na `~/.claude/projects` a `~/.codex/sessions`.
- „Dnes" = kalendářní den v lokální zóně (`Calendar.current`, půlnoc lokálně).
- `≈ $` je ODHAD v API cenách (paušál se platí tak jako tak); v UI vizuálně odlišené znakem `≈`.
- Výkon: scanner čte JEN soubory s dnešním `contentModificationDate` (jinak by četl GB historie); pre-filtr řádků substringem jako u v0.1 Codex parseru.
- Selhání scanneru nesmí shodit limit-část — `today` zůstane `nil`; UI řádek „Dnes" se pak nezobrazí.
- **Pricing tabulka (ověřeno 2026-06-23, $ za 1M tokenů — input / output / cache-write / cache-read):**
  - Claude Opus (`claude-opus-4-8`/`4-7`/`4-6`): 5.00 / 25.00 / 6.25 / 0.50
  - Claude Sonnet (`claude-sonnet-4-6`): 3.00 / 15.00 / 3.75 / 0.30
  - Claude Haiku (`claude-haiku-4-5`): 1.00 / 5.00 / 1.25 / 0.10
  - Codex (`*codex*`, default Codex model): 1.75 / 14.00 / — / 0.175 (gpt-5.3-codex; cache-write se u Codexu nepoužívá → 0)
  - gpt-5.5: 5.00 / 30.00 / — / 0.50 · gpt-5.4: 2.50 / 15.00 / — / 0.25
- TDD stub-first (SwiftPM kompiluje celý cíl jako jeden celek; „red" = selhaný `#expect`, NE compile error → vždy nejdřív stub, pak test, pak impl). Commit po každém tasku.

---

## Assumptions

| # | Předpoklad | Status | Ověřeno jak / kterým krokem |
|---|------------|--------|------------------------------|
| A1 | `Package.swift` má `resources: [.copy("Fixtures")]` → `Bundle.module` + `subdirectory:"Fixtures"` funguje | **verified** | přečten `Package.swift` (řádek 13) + `Tests/.../Fixtures/` existuje + baseline `swift test` zelený |
| A2 | Baseline `swift build`/`swift test` zelené (20 testů, 0 suites) | **verified** | spuštěno v Phase 1 (exit 0, „20 tests in 0 suites passed") |
| A3 | `swift test --filter <NázevSouboru>` spustí volné `@Test func` v tom souboru | **verified** | probnuto: `--filter FormattingTests` → 5 testů z toho souboru |
| A4 | Claude assistant JSONL má `type/timestamp/message.model/message.usage.{input_tokens,output_tokens,cache_creation_input_tokens,cache_read_input_tokens}` | **verified** | ověřeno na stroji v0.2 brainstormingu (uloženo v paměti `statusbar-data-and-pricing`) |
| A5 | Codex `payload.info.total_token_usage` je kumulativní per session (`input_tokens`,`cached_input_tokens`,`output_tokens`,`reasoning_output_tokens`) | **verified** | ověřeno na živých datech (paměť) |
| A6 | Reálné inity `ProviderUsage`/`ClaudeCodeCollector`/`CodexCollector`/`PopoverView` odpovídají edit-kotvám níže | **verified** | všechny 4 soubory přečteny v Phase 1; old_string bloky zkopírovány verbatim |
| A7 | Codex/gpt ceny (Codex 1.75/14, gpt-5.x) jsou aktuální | **accepted-by-user** (CP2) | drží se „≈"; revidovat v budoucnu přes claude-api skill + OpenAI pricing |
| A8 | Claude Opus/Sonnet/Haiku input/output ceny | **verified** | shoda s claude-api cached model table (Opus 5/25, Sonnet 3/15, Haiku 1/5) |

## Considered Alternatives

**Kde počítat `today` (vybráno při CP2 → varianta A):**

- **A) V `collector.fetch()` při každém 60s refreshi (vybráno).** Jednoduchý datový tok, `today` putuje stejnou cestou jako limity. Sken se omezuje na dnešní-mtime soubory, takže je levný i při zavřeném popoveru. Blast radius: žádný — additivní pole.
- B) Líně až při otevření popoveru. Ušetří sken, když se nikdo nedívá, ale komplikuje tok (UI spouští sken, cache invalidace). Odloženo na v0.3, pokud se 60s sken ukáže jako problém.

**Granularita Codex „dnes" (vybráno → A, accept):**

- **A) Suma finálních kumulativních `total_token_usage` dnešních sessionů (vybráno).** Jednoduché. Známé omezení: session začatá *včera* a pokračující dnes přičte i včerejší tokeny do „dnes" (F3). Pro v0.2 akceptováno + zdokumentováno komentářem; UI drží „≈".
- B) Počítat denní delta (poslední total − total před půlnocí). Přesnější, ale vyžaduje per-řádkové timestampy a víc parsování. Odloženo.

## Guardrails

- **Zakázané akce:** žádný zápis do `~/.claude`/`~/.codex`; žádné mazání souborů; žádný `print`/log surového obsahu JSONL řádků; nesahat na `auth.json`/Keychain; neměnit lištu ani limit-část v0.1 (parsery limitů, `CodexRateLimitParser`, `ClaudeUsageCacheParser`, `UsageStore`, `RefreshCoordinator`, `MenuBarController`).
- **⚠ Nevratné operace:** žádné v tomto plánu (čistě additivní, jen čtení cizích souborů + zápis vlastních zdrojáků/testů).
- **Globální stop podmínky:** Pokud `swift build` po edit-kroku selže kvůli nesedící edit-kotvě (old_string nenalezen) → ZASTAV, znovu si přečti reálný soubor a oprav podle skutečného obsahu, NEimprovizuj nový tvar. Pokud baseline 20 v0.1 testů začne padat → ZASTAV (regrese limit-části), nepokračuj na další task.
- **Kill criteria (CP2 → akceptováno):** Pokud se po hardeningu Claude „Dnes" nepodaří naplnit z reálných čerstvých dat do 2 implementačních pokusů, NEBO cenovou matematiku/scannery nelze udělat deterministicky v testech → STOP a přehodnotit přístup (ne retry kroku). Časový rámec: v rámci této + bezprostředně následující session; přesah → eskalovat uživateli.

## Executor Preamble

> **Instrukce pro vykonavatele — předej spolu s celým plánem (resp. s task-brief daného tasku):**
> - Vykonávej kroky přesně v pořadí; nepřeskakuj, neslučuj, nepřeskupuj.
> - Stub-first: u každé nové jednotky nejdřív STUB (kompiluje, vrací prázdno), pak test, pak impl. „RED" = selhaný `#expect`, NE compile error.
> - Edit-kroky mají `old_string` zkopírovaný verbatim z reálného souboru — používej přesné nahrazení. Když `old_string` nesedí, ZASTAV a přečti reálný soubor (viz stop podmínky), neimprovizuj.
> - Po každém kroku spusť uvedený „Verify" příkaz a výsledek nahlas. Formát hlášení: číslo kroku · akce · výstup ověření · stav (OK/FAILED/HALTED).
> - Nikdy nelogovat surový obsah JSONL řádků (jen čísla). Nezapisovat do `~/.claude`/`~/.codex`.
> - Před Task 1: ujisti se, že pracuješ na větvi `feat/v0.2-today-tokens` (vytvoř z `main`, pokud neexistuje), NE na `main`.

**Pre-flight (orchestrátor, jednou před Task 1):**
```bash
git checkout -b feat/v0.2-today-tokens 2>/dev/null || git checkout feat/v0.2-today-tokens
swift test 2>&1 | tail -3   # Expected: "20 tests ... passed"
```

---

## Execution Steps

### Task 1: Doménový model tokenů + PricingTable + PricingEstimator

**Files:**
- Create: `Sources/StatusBarKit/Models/TokenUsage.swift`
- Create: `Sources/StatusBarKit/Pricing/PricingTable.swift`
- Create: `Sources/StatusBarKit/Pricing/PricingEstimator.swift`
- Modify: `Sources/StatusBarKit/Models/ProviderUsage.swift` (přidat `today: TodayUsage?` + `with(today:)`)
- Test: `Tests/StatusBarKitTests/TokenUsageTests.swift`
- Test: `Tests/StatusBarKitTests/PricingEstimatorTests.swift`

**Interfaces:**
- Produces: `TokenUsage` (`input/output/cacheWrite/cacheRead: UInt`, `totalTokens`, `+`, `.zero`), `ModelTokens` (`modelName`, `tokens`), `TodayUsage` (`perModel`, `estimatedCost: Decimal`, computed `total`), `ProviderUsage.today: TodayUsage?`, `ProviderUsage.with(today:) -> ProviderUsage`, `ModelPricing`, `PricingTable.pricing(forModel:) -> ModelPricing?`, `PricingEstimator.estimate(_:model:) -> Decimal` a `estimate(_ perModel: [ModelTokens]) -> Decimal`.

- [ ] **Step 1: Stub `Sources/StatusBarKit/Models/TokenUsage.swift`**

```swift
import Foundation

public struct TokenUsage: Sendable, Equatable {
    public let input: UInt
    public let output: UInt
    public let cacheWrite: UInt
    public let cacheRead: UInt
    public init(input: UInt = 0, output: UInt = 0, cacheWrite: UInt = 0, cacheRead: UInt = 0) {
        self.input = input; self.output = output; self.cacheWrite = cacheWrite; self.cacheRead = cacheRead
    }
    public static let zero = TokenUsage()
    public var totalTokens: UInt { 0 }   // STUB
    public static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        TokenUsage()                       // STUB
    }
}

public struct ModelTokens: Sendable, Equatable {
    public let modelName: String
    public let tokens: TokenUsage
    public init(modelName: String, tokens: TokenUsage) { self.modelName = modelName; self.tokens = tokens }
}

public struct TodayUsage: Sendable, Equatable {
    public let perModel: [ModelTokens]
    public let estimatedCost: Decimal
    public init(perModel: [ModelTokens], estimatedCost: Decimal) {
        self.perModel = perModel; self.estimatedCost = estimatedCost
    }
    public var total: TokenUsage { perModel.reduce(.zero) { $0 + $1.tokens } }
}
```

- [ ] **Step 2: Modify `ProviderUsage.swift` — přidat `today` + `with(today:)`.** (F1/F8: přesná edit-kotva podle reálného kompaktního initu.)

Najdi přesně tento blok (`old_string`):

```swift
    public let status: ProviderStatus
    public let lastUpdated: Date
    public init(providerId: ProviderID, displayName: String, planLabel: String?,
                windows: [UsageWindow], status: ProviderStatus, lastUpdated: Date) {
        self.providerId = providerId; self.displayName = displayName; self.planLabel = planLabel
        self.windows = windows; self.status = status; self.lastUpdated = lastUpdated
    }
```

a nahraď ho (`new_string`):

```swift
    public let status: ProviderStatus
    public let lastUpdated: Date
    public let today: TodayUsage?
    public init(providerId: ProviderID, displayName: String, planLabel: String?,
                windows: [UsageWindow], status: ProviderStatus, lastUpdated: Date,
                today: TodayUsage? = nil) {
        self.providerId = providerId; self.displayName = displayName; self.planLabel = planLabel
        self.windows = windows; self.status = status; self.lastUpdated = lastUpdated
        self.today = today
    }

    public func with(today: TodayUsage?) -> ProviderUsage {
        ProviderUsage(providerId: providerId, displayName: displayName, planLabel: planLabel,
                      windows: windows, status: status, lastUpdated: lastUpdated, today: today)
    }
```

(`static func unavailable` zůstává beze změny — `today` se naplní defaultem `nil`. `Equatable` se dosyntetizuje; v0.1 konstrukce bez `today` dál fungují díky defaultu.)

- [ ] **Step 3: Test `Tests/StatusBarKitTests/TokenUsageTests.swift`**

```swift
import Testing
@testable import StatusBarKit

@Test func tokenUsageSoučetACelkem() {
    let a = TokenUsage(input: 10, output: 5, cacheWrite: 2, cacheRead: 100)
    let b = TokenUsage(input: 1, output: 1, cacheWrite: 0, cacheRead: 3)
    let s = a + b
    #expect(s == TokenUsage(input: 11, output: 6, cacheWrite: 2, cacheRead: 103))
    #expect(s.totalTokens == 11 + 6 + 2 + 103)
}

@Test func todayUsageTotalSečteModely() {
    let t = TodayUsage(perModel: [
        ModelTokens(modelName: "Opus", tokens: TokenUsage(input: 100, output: 50)),
        ModelTokens(modelName: "Sonnet", tokens: TokenUsage(input: 10, output: 5)),
    ], estimatedCost: 0)
    #expect(t.total == TokenUsage(input: 110, output: 55))
}
```

- [ ] **Step 4: Run → RED.** `swift test --filter TokenUsageTests`
  Expected: FAIL (`totalTokens`/`+` stub vrací 0/zero, takže `tokenUsageSoučetACelkem` padne).
- [ ] **Step 5: Implementuj** — nahraď dva STUB v `TokenUsage`:

```swift
    public var totalTokens: UInt { input + output + cacheWrite + cacheRead }
    public static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        TokenUsage(input: a.input + b.input, output: a.output + b.output,
                   cacheWrite: a.cacheWrite + b.cacheWrite, cacheRead: a.cacheRead + b.cacheRead)
    }
```

- [ ] **Step 6: Run → GREEN.** `swift test --filter TokenUsageTests` → Expected: 2 PASS.
- [ ] **Step 7: Stub `Sources/StatusBarKit/Pricing/PricingTable.swift`**

```swift
import Foundation

public struct ModelPricing: Sendable, Equatable {
    public let input: Decimal      // $ / 1M
    public let output: Decimal
    public let cacheWrite: Decimal
    public let cacheRead: Decimal
    public init(input: Decimal, output: Decimal, cacheWrite: Decimal, cacheRead: Decimal) {
        self.input = input; self.output = output; self.cacheWrite = cacheWrite; self.cacheRead = cacheRead
    }
}

public enum PricingTable {
    public static func pricing(forModel model: String) -> ModelPricing? { nil }   // STUB
}
```

- [ ] **Step 8: Stub `Sources/StatusBarKit/Pricing/PricingEstimator.swift`**

```swift
import Foundation

public enum PricingEstimator {
    public static func estimate(_ tokens: TokenUsage, model: String) -> Decimal { 0 }   // STUB
    public static func estimate(_ perModel: [ModelTokens]) -> Decimal {
        perModel.reduce(Decimal(0)) { $0 + estimate($1.tokens, model: $1.modelName) }
    }
}
```

- [ ] **Step 9: Test `Tests/StatusBarKitTests/PricingEstimatorTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func odhadOpusCacheAware() {
    // 1M input + 1M output + 1M cacheRead na Opus (5 / 25 / cacheRead 0.5)
    let t = TokenUsage(input: 1_000_000, output: 1_000_000, cacheWrite: 0, cacheRead: 1_000_000)
    let cost = PricingEstimator.estimate(t, model: "claude-opus-4-8")
    #expect(cost == Decimal(5) + Decimal(25) + Decimal(string: "0.5")!)  // 30.5
}

@Test func odhadNeznámýModelJeNula() {
    #expect(PricingEstimator.estimate(TokenUsage(input: 1_000_000), model: "neznamy-xyz") == 0)
}

@Test func odhadPerModelSečte() {
    let perModel = [
        ModelTokens(modelName: "claude-sonnet-4-6", tokens: TokenUsage(input: 1_000_000)),  // 3.0
        ModelTokens(modelName: "claude-haiku-4-5", tokens: TokenUsage(output: 1_000_000)),   // 5.0
    ]
    #expect(PricingEstimator.estimate(perModel) == Decimal(8))
}
```

- [ ] **Step 10: Run → RED.** `swift test --filter PricingEstimatorTests` → Expected: FAIL (stub vrací 0).
- [ ] **Step 11: Implementuj `PricingTable`** — nahraď `pricing(forModel:)`:

```swift
    public static func pricing(forModel model: String) -> ModelPricing? {
        let m = model.lowercased()
        func d(_ s: String) -> Decimal { Decimal(string: s)! }
        if m.contains("opus")   { return ModelPricing(input: d("5"),    output: d("25"), cacheWrite: d("6.25"), cacheRead: d("0.5")) }
        if m.contains("sonnet") { return ModelPricing(input: d("3"),    output: d("15"), cacheWrite: d("3.75"), cacheRead: d("0.3")) }
        if m.contains("haiku")  { return ModelPricing(input: d("1"),    output: d("5"),  cacheWrite: d("1.25"), cacheRead: d("0.1")) }
        if m.contains("codex")  { return ModelPricing(input: d("1.75"), output: d("14"), cacheWrite: d("0"),    cacheRead: d("0.175")) }
        if m.contains("gpt-5.5"){ return ModelPricing(input: d("5"),    output: d("30"), cacheWrite: d("0"),    cacheRead: d("0.5")) }
        if m.contains("gpt-5")  { return ModelPricing(input: d("2.5"),  output: d("15"), cacheWrite: d("0"),    cacheRead: d("0.25")) }
        return nil
    }
```

- [ ] **Step 12: Implementuj `PricingEstimator.estimate(_:model:)`** — nahraď STUB:

```swift
    public static func estimate(_ tokens: TokenUsage, model: String) -> Decimal {
        guard let p = PricingTable.pricing(forModel: model) else { return 0 }
        let perMillion = Decimal(1_000_000)
        func part(_ count: UInt, _ price: Decimal) -> Decimal { (Decimal(count) / perMillion) * price }
        return part(tokens.input, p.input) + part(tokens.output, p.output)
             + part(tokens.cacheWrite, p.cacheWrite) + part(tokens.cacheRead, p.cacheRead)
    }
```

- [ ] **Step 13: Run → GREEN.** `swift test` → Expected: VŠECHNY testy PASS (vč. dosavadních 20 z v0.1 = celkem 25).
- [ ] **Step 14: Commit.**

```bash
git add Sources/StatusBarKit/Models Sources/StatusBarKit/Pricing Tests/StatusBarKitTests
git commit -m "feat: model tokenů + PricingTable/PricingEstimator + ProviderUsage.today"
```

**Verify success (Task 1):** `swift test` → 25 PASS, `swift build` čistý.
**On failure:** nesedící `old_string` v Step 2 → přečti reálný `ProviderUsage.swift`, najdi skutečný init, uprav podle něj (zachovej přidání `today` pole + `with`). Nepokračuj na Task 2, dokud Task 1 není GREEN.

---

### Task 2: `ClaudeTokenScanner` (dnešní tokeny z ~/.claude/projects) + napojení

**Files:**
- Create: `Sources/StatusBarKit/Providers/ClaudeTokenParser.swift`
- Create: `Sources/StatusBarKit/Providers/ClaudeTokenScanner.swift`
- Modify: `Sources/StatusBarKit/Providers/ClaudeCodeCollector.swift` (vyplnit `today` v OBOU větvích)
- Create: `Tests/StatusBarKitTests/Fixtures/claude-project-session.jsonl`
- Test: `Tests/StatusBarKitTests/ClaudeTokenParserTests.swift`
- Test: `Tests/StatusBarKitTests/ClaudeTokenScannerTests.swift`

**Interfaces:**
- Consumes: `TokenUsage`, `ModelTokens`, `TodayUsage`, `PricingEstimator`.
- Produces: `enum ClaudeTokenParser { static func sumByModel(fromJSONL data: Data, dayStart: Date, dayEnd: Date) -> [String: TokenUsage] }`; `struct ClaudeTokenScanner { init(projectsDir: URL?); func todayUsage(now: Date, calendar: Calendar) -> TodayUsage? }`.

Pozn.: Reálná assistant zpráva má `type=="assistant"`, `timestamp` (ISO 8601 s ms, `Z`), `message.model` (např. `claude-opus-4-8`) a `message.usage` s `input_tokens`/`output_tokens`/`cache_creation_input_tokens`/`cache_read_input_tokens`. Mapování: input→input_tokens, output→output_tokens, cacheWrite→cache_creation_input_tokens, cacheRead→cache_read_input_tokens. (U Claude jsou tyto čtyři kbelíky disjunktní — `input_tokens` neobsahuje cache.)

- [ ] **Step 1: Fixtura `Tests/StatusBarKitTests/Fixtures/claude-project-session.jsonl`** (pevné UTC datum 2026-06-23; test si den nastaví podle něj)

```
{"type":"assistant","timestamp":"2026-06-23T10:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":10,"cache_read_input_tokens":1000}}}
{"type":"user","timestamp":"2026-06-23T10:00:01.000Z","message":{"role":"user"}}
{"type":"assistant","timestamp":"2026-06-23T11:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":20,"output_tokens":8,"cache_creation_input_tokens":0,"cache_read_input_tokens":5}}}
{"type":"assistant","timestamp":"2026-06-22T23:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"input_tokens":999,"output_tokens":999,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
```

- [ ] **Step 2: Stub `Sources/StatusBarKit/Providers/ClaudeTokenParser.swift`**

```swift
import Foundation

public enum ClaudeTokenParser {
    public static func sumByModel(fromJSONL data: Data, dayStart: Date, dayEnd: Date) -> [String: TokenUsage] {
        [:]   // STUB
    }
}
```

- [ ] **Step 3: Test `Tests/StatusBarKitTests/ClaudeTokenParserTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func sumByModelJenDnešní() throws {
    let url = Bundle.module.url(forResource: "claude-project-session", withExtension: "jsonl", subdirectory: "Fixtures")!
    let data = try Data(contentsOf: url)
    // den 2026-06-23 v UTC (fixtura má UTC timestampy)
    let iso = ISO8601DateFormatter()
    let dayStart = iso.date(from: "2026-06-23T00:00:00Z")!
    let dayEnd = iso.date(from: "2026-06-24T00:00:00Z")!
    let sums = ClaudeTokenParser.sumByModel(fromJSONL: data, dayStart: dayStart, dayEnd: dayEnd)

    // Opus: jen dnešní řádek (ne ten z 06-22)
    #expect(sums["claude-opus-4-8"] == TokenUsage(input: 100, output: 50, cacheWrite: 10, cacheRead: 1000))
    #expect(sums["claude-sonnet-4-6"] == TokenUsage(input: 20, output: 8, cacheWrite: 0, cacheRead: 5))
}
```

- [ ] **Step 4: Run → RED.** `swift test --filter ClaudeTokenParserTests` → Expected: FAIL (stub `[:]`).
- [ ] **Step 5: Implementuj parser** — nahraď celé tělo souboru:

```swift
import Foundation

public enum ClaudeTokenParser {
    private struct Line: Decodable {
        let type: String?; let timestamp: String?; let message: Msg?
    }
    private struct Msg: Decodable { let model: String?; let usage: Usage? }
    private struct Usage: Decodable {
        let input_tokens: UInt?; let output_tokens: UInt?
        let cache_creation_input_tokens: UInt?; let cache_read_input_tokens: UInt?
    }
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    public static func sumByModel(fromJSONL data: Data, dayStart: Date, dayEnd: Date) -> [String: TokenUsage] {
        let needle = Data("\"assistant\"".utf8)
        let decoder = JSONDecoder()
        var result: [String: TokenUsage] = [:]
        for raw in data.split(separator: UInt8(ascii: "\n")) {
            let line = Data(raw)
            guard line.range(of: needle) != nil,
                  let l = try? decoder.decode(Line.self, from: line),
                  l.type == "assistant",
                  let ts = l.timestamp.flatMap({ iso.date(from: $0) }) ?? l.timestamp.flatMap({ ISO8601DateFormatter().date(from: $0) }),
                  ts >= dayStart, ts < dayEnd,
                  let model = l.message?.model, let u = l.message?.usage
            else { continue }
            let usage = TokenUsage(
                input: u.input_tokens ?? 0, output: u.output_tokens ?? 0,
                cacheWrite: u.cache_creation_input_tokens ?? 0, cacheRead: u.cache_read_input_tokens ?? 0)
            result[model, default: .zero] = (result[model] ?? .zero) + usage
        }
        return result
    }
}
```

- [ ] **Step 6: Run → GREEN.** `swift test --filter ClaudeTokenParserTests` → Expected: PASS.
- [ ] **Step 7: Stub `Sources/StatusBarKit/Providers/ClaudeTokenScanner.swift`**

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
        nil   // STUB
    }
}
```

- [ ] **Step 8: Test `Tests/StatusBarKitTests/ClaudeTokenScannerTests.swift`** (F-ST: deterministicky — temp adresář + nastavené mtime; nezávislé na reálných datech/hodinách)

```swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func claudeScannerJenDnešníZTempAdresáře() throws {
    let cal = Calendar.current
    var comps = DateComponents(); comps.year = 2026; comps.month = 6; comps.day = 23; comps.hour = 12
    let now = cal.date(from: comps)!
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let tsDnes = iso.string(from: now)
    let tsVčera = iso.string(from: cal.date(byAdding: .day, value: -1, to: now)!)

    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("claudeScan-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let file = tmp.appendingPathComponent("session.jsonl")
    let jsonl = """
    {"type":"assistant","timestamp":"\(tsDnes)","message":{"model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":10,"cache_read_input_tokens":1000}}}
    {"type":"assistant","timestamp":"\(tsVčera)","message":{"model":"claude-opus-4-8","usage":{"input_tokens":999,"output_tokens":999,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
    """
    try jsonl.data(using: .utf8)!.write(to: file)
    try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)

    let today = ClaudeTokenScanner(projectsDir: tmp).todayUsage(now: now)
    let t = try #require(today)                       // nesmí být nil (jinak F1-styl tichý výpadek)
    #expect(t.perModel.count == 1)
    #expect(t.perModel.first?.modelName == "claude-opus-4-8")
    #expect(t.perModel.first?.tokens == TokenUsage(input: 100, output: 50, cacheWrite: 10, cacheRead: 1000))
    #expect(t.estimatedCost > 0)
}
```

- [ ] **Step 9: Run → RED.** `swift test --filter ClaudeTokenScannerTests` → Expected: FAIL (`#require(today)` padne, stub vrací nil).
- [ ] **Step 10: Implementuj scanner** — nahraď tělo `todayUsage`:

```swift
    public func todayUsage(now: Date, calendar: Calendar = .current) -> TodayUsage? {
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }

        var byModel: [String: TokenUsage] = [:]
        if let en = FileManager.default.enumerator(at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let url as URL in en where url.pathExtension == "jsonl" {
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                guard let mod, mod >= dayStart else { continue }   // jen dnes upravené soubory
                guard let data = try? Data(contentsOf: url) else { continue }
                for (model, usage) in ClaudeTokenParser.sumByModel(fromJSONL: data, dayStart: dayStart, dayEnd: dayEnd) {
                    byModel[model, default: .zero] = (byModel[model] ?? .zero) + usage
                }
            }
        }
        guard !byModel.isEmpty else { return nil }
        let perModel = byModel.map { ModelTokens(modelName: $0.key, tokens: $0.value) }
            .sorted { $0.modelName < $1.modelName }
        return TodayUsage(perModel: perModel, estimatedCost: PricingEstimator.estimate(perModel))
    }
```

- [ ] **Step 11: Run → GREEN.** `swift test --filter ClaudeTokenScannerTests` → Expected: PASS.
- [ ] **Step 12: Modify `ClaudeCodeCollector.fetch()` — vyplnit `today` v OBOU větvích (ok i degraded).** (F1: ok-větev je `return usage`, NE konstruktor — proto `usage.with(today:)`.)

Najdi přesně tento blok (`old_string`):

```swift
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
```

a nahraď ho (`new_string`):

```swift
        do {
            let usage = try ClaudeUsageCacheParser.parse(data)
            let today = ClaudeTokenScanner().todayUsage(now: now)
            let age = now.timeIntervalSince(usage.lastUpdated)
            if age > staleAfter {
                return ProviderUsage(providerId: usage.providerId, displayName: usage.displayName,
                    planLabel: usage.planLabel, windows: usage.windows,
                    status: .degraded("Data stará \(Int(age/60)) min — otevři Claude Code."),
                    lastUpdated: usage.lastUpdated, today: today)
            }
            return usage.with(today: today)
        } catch {
```

(Cesta `.unavailable` zůstává beze změny — `today = nil` přes default.)

- [ ] **Step 13: Run testy + build + smoke.** `swift test` → Expected: vše PASS (28: 25 + parser + scanner test… přesný počet hlaš jako informaci). `swift build` čistý. Smoke (přímo ověří ok-větev F1 na reálných čerstvých datech): `./scripts/make-app.sh debug && open StatusBar.app` → Claude karta ukáže řádek „Dnes" (pokud jsi dnes používal Claude Code; jinak řádek chybí — to je OK).
- [ ] **Step 14: Commit.**

```bash
git add Sources/StatusBarKit/Providers/ClaudeTokenParser.swift Sources/StatusBarKit/Providers/ClaudeTokenScanner.swift Sources/StatusBarKit/Providers/ClaudeCodeCollector.swift Tests/StatusBarKitTests
git commit -m "feat: ClaudeTokenScanner — dnešní tokeny per model + napojení do collectoru"
```

**Verify success (Task 2):** `swift test` vše PASS; `ClaudeTokenScannerTests` zelený (today != nil); collector ok-větev vrací `usage.with(today: today)`.
**Reviewer gate (povinné):** potvrď v diffu, že **OBĚ** větve (ok i degraded) naplňují `today`; ok-větev je `usage.with(today: today)`, NE holé `return usage`. Pokud ne → failed spec review.
**On failure:** `old_string` v Step 12 nesedí → přečti reálný `ClaudeCodeCollector.swift`, najdi skutečné větve a aplikuj princip (today v ok i degraded). ZASTAV, neimprovizuj.

---

### Task 3: `CodexTokenScanner` (dnešní tokeny z ~/.codex/sessions) + napojení

**Files:**
- Create: `Sources/StatusBarKit/Providers/CodexTokenParser.swift`
- Create: `Sources/StatusBarKit/Providers/CodexTokenScanner.swift`
- Modify: `Sources/StatusBarKit/Providers/CodexCollector.swift` (vyplnit `today`)
- Create: `Tests/StatusBarKitTests/Fixtures/codex-session-tokens.jsonl`
- Test: `Tests/StatusBarKitTests/CodexTokenParserTests.swift`
- Test: `Tests/StatusBarKitTests/CodexTokenScannerTests.swift`

**Interfaces:**
- Consumes: `TokenUsage`, `TodayUsage`, `PricingEstimator`.
- Produces: `enum CodexTokenParser { static func lastTotal(fromJSONL data: Data) -> TokenUsage? }`; `struct CodexTokenScanner { init(sessionsDir: URL?, maxFilesToScan: Int); func todayUsage(now: Date, calendar: Calendar) -> TodayUsage? }`.

Pozn.: Codex událost `token_count` má `payload.info.total_token_usage` (kumulativně per session). Mapování na `TokenUsage`: cacheRead = cached_input_tokens; input = input_tokens − cached_input_tokens (nezáporně); output = output_tokens + reasoning_output_tokens; cacheWrite = 0. Model = „codex". Bereme POSLEDNÍ `token_count.info.total_token_usage` v souboru (kumulativní). **F3 (akceptováno):** session přes půlnoc přičte i včerejšek do „dnes" — zdokumentováno komentářem ve scanneru; UI drží „≈".

- [ ] **Step 1: Fixtura `Tests/StatusBarKitTests/Fixtures/codex-session-tokens.jsonl`**

```
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":400,"output_tokens":200,"reasoning_output_tokens":50,"total_tokens":1250}}}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":3000,"cached_input_tokens":1200,"output_tokens":600,"reasoning_output_tokens":100,"total_tokens":3700}}}}
```

- [ ] **Step 2: Stub `Sources/StatusBarKit/Providers/CodexTokenParser.swift`**

```swift
import Foundation

public enum CodexTokenParser {
    public static func lastTotal(fromJSONL data: Data) -> TokenUsage? { nil }   // STUB
}
```

- [ ] **Step 3: Test `Tests/StatusBarKitTests/CodexTokenParserTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func codexBerePosledníTotal() throws {
    let url = Bundle.module.url(forResource: "codex-session-tokens", withExtension: "jsonl", subdirectory: "Fixtures")!
    let t = CodexTokenParser.lastTotal(fromJSONL: try Data(contentsOf: url))
    // poslední řádek: input 3000 (z toho cached 1200) → 1800, output 600+100=700
    #expect(t == TokenUsage(input: 1800, output: 700, cacheWrite: 0, cacheRead: 1200))
}

@Test func codexBezTokenCountNil() {
    let t = CodexTokenParser.lastTotal(fromJSONL: Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"other\"}}".utf8))
    #expect(t == nil)
}
```

- [ ] **Step 4: Run → RED.** `swift test --filter CodexTokenParserTests` → Expected: FAIL (stub nil — `codexBere…` selže, `bezTokenCount` projde).
- [ ] **Step 5: Implementuj parser** — nahraď celé tělo souboru:

```swift
import Foundation

public enum CodexTokenParser {
    private struct Line: Decodable { let type: String?; let payload: Payload? }
    private struct Payload: Decodable { let type: String?; let info: Info? }
    private struct Info: Decodable { let total_token_usage: Total? }
    private struct Total: Decodable {
        let input_tokens: UInt?; let cached_input_tokens: UInt?
        let output_tokens: UInt?; let reasoning_output_tokens: UInt?
    }

    public static func lastTotal(fromJSONL data: Data) -> TokenUsage? {
        let needle = Data("total_token_usage".utf8)
        let decoder = JSONDecoder()
        var last: Total?
        for raw in data.split(separator: UInt8(ascii: "\n")) {
            let line = Data(raw)
            guard line.range(of: needle) != nil,
                  let l = try? decoder.decode(Line.self, from: line),
                  l.type == "event_msg", l.payload?.type == "token_count",
                  let total = l.payload?.info?.total_token_usage
            else { continue }
            last = total
        }
        guard let t = last else { return nil }
        let cached = t.cached_input_tokens ?? 0
        let input = (t.input_tokens ?? 0) >= cached ? (t.input_tokens ?? 0) - cached : 0
        let output = (t.output_tokens ?? 0) + (t.reasoning_output_tokens ?? 0)
        return TokenUsage(input: input, output: output, cacheWrite: 0, cacheRead: cached)
    }
}
```

- [ ] **Step 6: Run → GREEN.** `swift test --filter CodexTokenParserTests` → Expected: 2 PASS.
- [ ] **Step 7: Stub `Sources/StatusBarKit/Providers/CodexTokenScanner.swift`**

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
    /// Sečte dnešní Codex tokeny (z dnešních sessionů, finální total per soubor). Nil, pokud nic.
    /// POZN. (F3, akceptováno): session přes půlnoc přičte i včerejší tokeny do „dnes" — kumulativní total.
    public func todayUsage(now: Date, calendar: Calendar = .current) -> TodayUsage? {
        nil   // STUB
    }
}
```

- [ ] **Step 8: Test `Tests/StatusBarKitTests/CodexTokenScannerTests.swift`** (F-ST: deterministicky)

```swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func codexScannerDnešníZTempAdresáře() throws {
    let cal = Calendar.current
    var comps = DateComponents(); comps.year = 2026; comps.month = 6; comps.day = 23; comps.hour = 12
    let now = cal.date(from: comps)!

    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("codexScan-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let file = tmp.appendingPathComponent("rollout.jsonl")
    let jsonl = """
    {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":400,"output_tokens":200,"reasoning_output_tokens":50,"total_tokens":1250}}}}
    {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":3000,"cached_input_tokens":1200,"output_tokens":600,"reasoning_output_tokens":100,"total_tokens":3700}}}}
    """
    try jsonl.data(using: .utf8)!.write(to: file)
    try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)

    let today = CodexTokenScanner(sessionsDir: tmp).todayUsage(now: now)
    let t = try #require(today)
    #expect(t.perModel == [ModelTokens(modelName: "codex", tokens: TokenUsage(input: 1800, output: 700, cacheWrite: 0, cacheRead: 1200))])
    #expect(t.estimatedCost > 0)
}
```

- [ ] **Step 9: Run → RED.** `swift test --filter CodexTokenScannerTests` → Expected: FAIL (`#require` padne, stub nil).
- [ ] **Step 10: Implementuj scanner** — nahraď tělo `todayUsage`:

```swift
    public func todayUsage(now: Date, calendar: Calendar = .current) -> TodayUsage? {
        let dayStart = calendar.startOfDay(for: now)
        var sum = TokenUsage.zero
        var any = false
        guard let en = FileManager.default.enumerator(at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        var files: [(URL, Date)] = []
        for case let url as URL in en where url.pathExtension == "jsonl" {
            if let m = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               m >= dayStart {
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
        return TodayUsage(perModel: perModel, estimatedCost: PricingEstimator.estimate(perModel))
    }
```

- [ ] **Step 11: Run → GREEN.** `swift test --filter CodexTokenScannerTests` → Expected: PASS.
- [ ] **Step 12: Modify `CodexCollector.fetch()` — vyplnit `today`.** (F11: jediný konstruktor v úspěšné větvi.)

Najdi přesně tento blok (`old_string`):

```swift
            let age = now.timeIntervalSince(f.modified)
            let status: ProviderStatus = age > staleAfter
                ? .degraded("Data stará \(Int(age/3600)) h — spusť `codex` pro aktualizaci.")
                : .ok
            return ProviderUsage(providerId: .codex, displayName: "Codex",
                planLabel: snap.planType, windows: snap.windows, status: status, lastUpdated: f.modified)
```

a nahraď ho (`new_string`):

```swift
            let age = now.timeIntervalSince(f.modified)
            let status: ProviderStatus = age > staleAfter
                ? .degraded("Data stará \(Int(age/3600)) h — spusť `codex` pro aktualizaci.")
                : .ok
            let today = CodexTokenScanner().todayUsage(now: now)
            return ProviderUsage(providerId: .codex, displayName: "Codex",
                planLabel: snap.planType, windows: snap.windows, status: status,
                lastUpdated: f.modified, today: today)
```

(Větve `.unavailable` nech beze změny — `today = nil`.)

- [ ] **Step 13: Run + build.** `swift test` → Expected: vše PASS. `swift build` čistý.
- [ ] **Step 14: Commit.**

```bash
git add Sources/StatusBarKit/Providers/CodexTokenParser.swift Sources/StatusBarKit/Providers/CodexTokenScanner.swift Sources/StatusBarKit/Providers/CodexCollector.swift Tests/StatusBarKitTests
git commit -m "feat: CodexTokenScanner — dnešní tokeny + napojení do collectoru"
```

**Verify success (Task 3):** `swift test` vše PASS; `CodexTokenScannerTests` zelený; collector vrací `today` v úspěšné větvi.
**On failure:** `old_string` v Step 12 nesedí → přečti reálný `CodexCollector.swift`, aplikuj princip (today do úspěšného konstruktoru). ZASTAV, neimprovizuj.

---

### Task 4: UI — řádky „Dnes", rozpad modelů, hlavičkový souhrn

**Files:**
- Create: `Sources/StatusBarKit/Formatting/TokenFormatter.swift`
- Test: `Tests/StatusBarKitTests/TokenFormatterTests.swift`
- Modify: `Sources/StatusBarApp/PopoverView.swift` (řádky „Dnes" + rozpad + hlavička)

**Interfaces:**
- Consumes: `TokenUsage`, `TodayUsage`, `ModelTokens`, `UsageStore`, `ProviderUsage.today`.
- Produces: `enum TokenFormatter { static func compact(_ n: UInt) -> String; static func money(_ d: Decimal) -> String; static func modelShortName(_ raw: String) -> String }`.

- [ ] **Step 1: Stub `Sources/StatusBarKit/Formatting/TokenFormatter.swift`**

```swift
import Foundation

public enum TokenFormatter {
    public static func compact(_ n: UInt) -> String { "" }            // STUB
    public static func money(_ d: Decimal) -> String { "" }           // STUB
    public static func modelShortName(_ raw: String) -> String { "" } // STUB
}
```

- [ ] **Step 2: Test `Tests/StatusBarKitTests/TokenFormatterTests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func compactTokeny() {
    #expect(TokenFormatter.compact(950) == "950")
    #expect(TokenFormatter.compact(1_240_000) == "1.24M")
    #expect(TokenFormatter.compact(820_000) == "820K")
}

@Test func moneyDvěMísta() {
    #expect(TokenFormatter.money(Decimal(string: "9.804")!) == "$9.80")
    #expect(TokenFormatter.money(Decimal(0)) == "$0.00")
}

@Test func krátkýNázevModelu() {
    #expect(TokenFormatter.modelShortName("claude-opus-4-8") == "Opus")
    #expect(TokenFormatter.modelShortName("claude-sonnet-4-6") == "Sonnet")
    #expect(TokenFormatter.modelShortName("claude-haiku-4-5") == "Haiku")
    #expect(TokenFormatter.modelShortName("codex") == "Codex")
}
```

- [ ] **Step 3: Run → RED.** `swift test --filter TokenFormatterTests` → Expected: FAIL.
- [ ] **Step 4: Implementuj** — nahraď tři STUB:

```swift
    public static func compact(_ n: UInt) -> String {
        switch n {
        case 1_000_000...:
            let v = Double(n) / 1_000_000
            return String(format: "%.2fM", v)
        case 1_000...:
            return "\(n / 1000)K"
        default:
            return "\(n)"
        }
    }
    public static func money(_ d: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 2; nf.maximumFractionDigits = 2   // zaokrouhlí na 2 místa
        nf.groupingSeparator = ""; nf.decimalSeparator = "."
        return "$" + (nf.string(from: NSDecimalNumber(decimal: d)) ?? "0.00")
    }
    public static func modelShortName(_ raw: String) -> String {
        let m = raw.lowercased()
        if m.contains("opus") { return "Opus" }
        if m.contains("sonnet") { return "Sonnet" }
        if m.contains("haiku") { return "Haiku" }
        if m.contains("codex") { return "Codex" }
        return raw
    }
```

- [ ] **Step 5: Run → GREEN.** `swift test` → Expected: vše PASS.
- [ ] **Step 6a: Modify `PopoverView.swift` — přidej computed `dnesCelkem`.** (F2: `dnesCelkem` je NEvolitelný `Decimal` → podmínka je `if dnesCelkem > 0`, NE `if let`.)

Najdi přesně (`old_string`):

```swift
    let onRefresh: () -> Void
    let onQuit: () -> Void
```

a nahraď (`new_string`):

```swift
    let onRefresh: () -> Void
    let onQuit: () -> Void

    private var dnesCelkem: Decimal {
        store.orderedUsages.compactMap { $0.today?.estimatedCost }.reduce(Decimal(0), +)
    }
```

- [ ] **Step 6b: Modify `PopoverView.swift` — hlavička se souhrnem.** (F10: přesná kotva reálné hlavičky.)

Najdi přesně (`old_string`):

```swift
            HStack {
                Text("Spotřeba").font(.headline); Spacer()
                Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
            }.padding(.horizontal, 14).padding(.vertical, 10)
```

a nahraď (`new_string`):

```swift
            HStack {
                Text("Spotřeba").font(.headline)
                Spacer()
                if dnesCelkem > 0 {
                    Text("Dnes ≈ \(TokenFormatter.money(dnesCelkem))").font(.caption).foregroundStyle(.secondary)
                }
                Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
            }.padding(.horizontal, 14).padding(.vertical, 10)
```

- [ ] **Step 6c: Modify `PopoverView.swift` — `ProviderCard` switch + `todayRow`.**

Najdi přesně (`old_string`):

```swift
            switch usage.status {
            case .unavailable(let m): Text(m).font(.caption).foregroundStyle(.secondary)
            case .degraded(let m): Text(m).font(.caption2).foregroundStyle(.orange); windowsList
            case .ok: windowsList
            }
        }.padding(.horizontal, 14).padding(.vertical, 11)
    }
```

a nahraď (`new_string`):

```swift
            switch usage.status {
            case .unavailable(let m): Text(m).font(.caption).foregroundStyle(.secondary)
            case .degraded(let m): Text(m).font(.caption2).foregroundStyle(.orange); windowsList; todayRow
            case .ok: windowsList; todayRow
            }
        }.padding(.horizontal, 14).padding(.vertical, 11)
    }

    @ViewBuilder private var todayRow: some View {
        if let today = usage.today {
            Divider().padding(.vertical, 2)
            HStack {
                Text("Dnes").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(TokenFormatter.compact(today.total.totalTokens)) tok. ≈ \(TokenFormatter.money(today.estimatedCost))")
                    .font(.caption).fontWeight(.medium)
            }
            if usage.providerId == .claudeCode, today.perModel.count > 1 {
                Text(today.perModel.map { "\(TokenFormatter.modelShortName($0.modelName)) \(TokenFormatter.compact($0.tokens.totalTokens))" }
                        .joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
```

- [ ] **Step 7: Build + smoke.** `swift test` → Expected: vše PASS (jádro). `./scripts/make-app.sh debug && open StatusBar.app` → Claude karta ukáže řádek „Dnes: <tok> ≈ $…" + (je-li víc modelů dnes) rozpad „Opus … · Sonnet …"; hlavička ukáže „Dnes ≈ $…". Codex „Dnes" jen pokud dnes běžel (jinak řádek chybí — OK). `≈` značí odhad.
- [ ] **Step 8: Commit.**

```bash
git add Sources/StatusBarKit/Formatting/TokenFormatter.swift Sources/StatusBarApp/PopoverView.swift Tests/StatusBarKitTests
git commit -m "feat: popover řádky Dnes + rozpad modelů + hlavičkový souhrn"
```

**Verify success (Task 4):** `swift test` vše PASS; app se nabuildí a popover ukazuje „Dnes" + hlavičkový souhrn.
**On failure:** kterýkoli `old_string` v Step 6a–6c nesedí → přečti reálný `PopoverView.swift`, najdi skutečný blok a aplikuj princip. ZASTAV, neimprovizuj.

---

## Rollback & Recovery

Plán je čistě additivní a každý task je samostatný commit na větvi `feat/v0.2-today-tokens` (`main` zůstává nedotčená). Bezpečný návrat:

- **Rozbitý jednotlivý task:** `git checkout -- <soubory>` (před commitem) nebo `git revert <commit>` (po commitu) vrátí stav před daným taskem; v0.1 funguje dál.
- **Zahodit celou v0.2:** `git checkout main && git branch -D feat/v0.2-today-tokens` — žádné nevratné změny, žádné migrace, žádný stav mimo git.
- **Regrese limit-části:** pokud po některém kroku padají původní v0.1 testy (`collectorPřečteCache`, `parserVezmePosledníUdálost…` apod.) → `git checkout -- Sources/StatusBarKit/Providers` a zopakuj edit collectoru podle reálného obsahu; limit-parsery se NEsmí měnit.

## Risk Register

| ID | Severity | Likelihood | Risk | Mitigace (krok) | Resolution |
|----|----------|------------|------|------------------|------------|
| F1 | CRIT | H | Claude ok-větev `return usage` → `today` se nenaplní na čerstvých datech (tichý výpadek hlavní feature) | T2/S12 `usage.with(today:)` + T2 reviewer gate + T2/S13 smoke + T2/S8 scanner test | fixed-in T2/S12 |
| F2 | HIGH | H | `if let total = dnesCelkem` na nevolitelný `Decimal` → compile error | T4/S6a–6b: `dnesCelkem: Decimal` + `if dnesCelkem > 0` | fixed-in T4/S6 |
| F8 | HIGH | M | Edit-kotva initu `ProviderUsage` neseděla s reálným kódem | T1/S2 přesný old/new blok podle reálného souboru | fixed-in T1/S2 |
| F10 | MED | M | Edit-kotva hlavičky `PopoverView` neseděla | T4/S6b přesný old/new HStack | fixed-in T4/S6b |
| F11 | MED | M | Chyběly přesné edit-kotvy collectorů | T2/S12 + T3/S12 verbatim bloky | fixed-in T2/T3 |
| F3 | MED | M | Codex „dnes" nadpočítává sessiony přes půlnoc (kumulativní total) | accept + komentář ve scanneru (T3/S7) + UI „≈" | accepted-by-user (CP2) |
| F-ST | MED | M | Žádný test nehlídal naplnění `today` (díra, kde se schoval F1) | T2/S8 + T3/S8 deterministické scanner testy (temp dir + mtime) | fixed-in T2/S8, T3/S8 |
| F-SEC | LOW | L | Riziko logování surového obsahu JSONL | Guardrails + parsery dekódují jen číselná pole | mitigated (Guardrails) |
| A7 | MED | L | Codex/gpt ceny mohou být zastaralé | UI „≈"; revize v budoucnu | accepted-by-user (CP2) |
| F-perf | LOW | L | Sken Claude JSONL při každém 60s refreshi | jen dnešní-mtime soubory; alt. B odložena | accepted (alt A, CP2) |

## Audit Trail

- **Lenses applied:** 1 red-team, 2 security, 3 assumptions, 4 dependencies, 5 alternatives, 6 cheap-executor, 7 goal-fit. (Lens 4: žádné transition-window — feature je čistě additivní, jen jedno nové pole.)
- **Findings:** 1 CRIT, 2 HIGH, 4 MED, 2 LOW + 1 assumption → CRIT/HIGH/MED všechny fixed nebo accepted-by-user; LOW housekeeping (`.DS_Store`) mimo rozsah (CP2 → 1A).
- **Settled by tool (ne nálezy):** `Bundle.module`/resources (Package.swift ověřen), `swift test --filter <soubor>` matchuje volné testy (probnuto), baseline build/test zelené (20 testů).
- **Re-audit po hardeningu (R*):** R1 ordering `with(today:)` (T1) před užitím (T2) ✓; R2 scanner inity (`projectsDir`/`sessionsDir`) sedí s testy ✓; R3 `dnesCelkem` užívá `store` (PopoverView má `store`), `todayRow` užívá jen `usage` (ProviderCard má `usage`) ✓. Žádné nové CRIT/HIGH.
- **Tabletop dry run:** prošel — stav se řetězí korektně: T1 zavede `TokenUsage/+/total`, `TodayUsage`, `ProviderUsage.today`+`with`; T2 přidá Claude scanner a naplní `today` v ok i degraded; T3 totéž pro Codex; T4 zobrazí `today` (UI). Identifikátory konzistentní napříč tasky (`todayUsage(now:)`, `with(today:)`, `estimate(_:)`, `compact/money/modelShortName`).
- **Key changes vs. draft v0:** F1 → ok-větev `usage.with(today:)` + helper; F2 → `if dnesCelkem > 0`; F8/F10/F11 → přesné verbatim edit-kotvy; F-ST → 2 deterministické scanner testy; F3 → akceptováno + zdokumentováno; přidány forge sekce (Assumptions, Alternatives, Guardrails+kill criteria, Rollback, Risk Register).
- **Decisions made by user at CP2:** 1A (rozsah CRIT/HIGH+MED), 2A (Codex coarseness accept), 3A (scanner testy), 4A (today v fetch()), 5A (kill criteria accept).
- **Open items to watch during execution:** přesný počet testů v hlášeních (jen informativní); smoke v T2/S13 a T4/S7 reálně ověří F1 ok-větev na čerstvých datech.

---

## Hotová definice v0.2
- Popover ukazuje u Claude i Codex karty řádek „Dnes" (tokeny + ≈$ odhad); u Claude rozpad podle modelu.
- Hlavička ukazuje „Dnes ≈ $X" (součet Claude + Codex odhadů).
- Tokeny z lokálních souborů (jen dnešní-mtime), cache-aware odhad přes ověřenou `PricingTable`.
- Limit-část z v0.1 nezměněná; chybějící dnešní data → řádek se nezobrazí, žádný pád.
- Jádro (model, pricing, parsery, scannery, formatter) pokryté `swift test` vč. 2 deterministických scanner testů.

## Mimo v0.2 (další fáze)
- **v0.3:** OpenAI API útrata (až bude Admin klíč), notifikace (prahy), přepínatelné styly lišty (B/C/D), Nastavení, spouštět při přihlášení, líný sken today (alt. B), Codex denní delta (F3 alt. B).
- **v1.0:** podpis, notarizace, Sparkle, Homebrew, dokumentace, veřejné vydání.
