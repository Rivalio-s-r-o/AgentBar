# StatusBar v0.8a — Reálná cena + error-path testy — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Denní „útrata ≈ $" ukazuje jen reálné (input+output) tokeny (bez cache), plus doplnit ~12 error-path testů v Kit vrstvě.

**Architecture:** Přidat `PricingEstimator.estimateReal` (jen input+output); scannery ji použijí, takže `TodayUsage.estimatedCost` nese reálnou cenu; popover beze změny kódu. Plná `estimate` zůstává jako utilita. Druhý task přidá error-path testy (parser/pricing/collector cesty).

**Tech Stack:** Swift 6 (strict concurrency), SwiftPM (`StatusBarKit` + `StatusBarApp`), Swift Testing (`@Test`/`#expect`).

## Global Constraints

- Swift 6 strict concurrency. `StatusBarKit` zůstává pure (žádný AppKit/SwiftUI/Security/síť).
- **`estimateReal` = jen `input×p.input + output×p.output`** (cacheWrite a cacheRead ZÁMĚRNĚ vynechány). `PricingEstimator.estimate` (plná, vč. cache) zůstává BEZE ZMĚNY jako utilita.
- **`TodayUsage.estimatedCost` field se NEpřejmenovává** — po změně scannerů nese reálnou cenu; `PopoverView` se NEmění.
- Žádný existující test se nesmí rozbít (ověřeno): `PricingEstimatorTests` testuje `estimate` (plnou, zachována) exaktně; scanner testy testují jen `estimatedCost > 0` (fixtury mají nenulové input/output → reálná cena `> 0`); `TokenUsageTests`/`RefreshCoordinatorTests` konstruují `TodayUsage(...estimatedCost: literál)` (nezávislé).
- **Testy jsou volné `@Test func` bez `@Suite`/typu:** ověřuj VŽDY plným `swift test`, NIKDY `swift test --filter <NázevSouboru>`.
- Error-path testy jsou pure Kit, inline `Data(...)` (bez nových fixtur), vzor stávajících testů. České názvy testů s diakritikou.
- Bundle verze → `0.7.2` (`Resources/Info.plist`, obě pole).
- TDD, časté commity, DRY, YAGNI.

## Guardrails
- **Zakázané:** přejmenovat/odstranit `estimatedCost` nebo `estimate` (plnou); sahat na pricing tabulku (ceny); měnit popover layout.
- **Rollback:** aditivní; `git revert`/`git checkout`.
- **Stop:** selže-li error-path test na chování (odhalí reálný bug v parseru), ZASTAV a nahlas — neopravuj parser bez konzultace (může jít o záměrné chování vs. test).
- **Kill criterion:** Task 1 testy nezelené po 2 pokusech → stop.

---

### Task 1: `PricingEstimator.estimateReal` + scannery (reálná cena)

**Files:**
- Modify: `Sources/StatusBarKit/Pricing/PricingEstimator.swift`
- Modify: `Sources/StatusBarKit/Providers/ClaudeTokenScanner.swift:33`
- Modify: `Sources/StatusBarKit/Providers/CodexTokenScanner.swift:33`
- Modify: `Sources/StatusBarKit/Models/TokenUsage.swift` (doc komentář u `TodayUsage.estimatedCost`)
- Modify (test): `Tests/StatusBarKitTests/PricingEstimatorTests.swift`

**Interfaces:**
- Consumes: `TokenUsage` (`input`, `output`, `cacheWrite`, `cacheRead`), `ModelTokens` (`modelName`, `tokens`), `PricingTable.pricing(forModel:)`.
- Produces: `PricingEstimator.estimateReal(_ tokens: TokenUsage, model: String) -> Decimal` a `estimateReal(_ perModel: [ModelTokens]) -> Decimal`.

- [ ] **Step 1: Napiš failing test do `PricingEstimatorTests.swift`**

Přidej na konec `Tests/StatusBarKitTests/PricingEstimatorTests.swift`:

```swift
@Test func odhadReálnýJenInputOutput() {
    // input 1M + output 1M + cacheRead 100M na Opus → reálná cena = 5 + 25 = 30 (cache ignorována)
    let t = TokenUsage(input: 1_000_000, output: 1_000_000, cacheWrite: 1_000_000, cacheRead: 100_000_000)
    #expect(PricingEstimator.estimateReal(t, model: "claude-opus-4-8") == Decimal(30))
}

@Test func odhadReálnýNeznámýModelJeNula() {
    #expect(PricingEstimator.estimateReal(TokenUsage(input: 1_000_000), model: "neznamy-xyz") == 0)
}

@Test func odhadReálnýPerModelSečte() {
    let perModel = [
        ModelTokens(modelName: "claude-sonnet-4-6", tokens: TokenUsage(input: 1_000_000, cacheRead: 9_000_000)),  // real 3.0, cache ignor.
        ModelTokens(modelName: "claude-haiku-4-5", tokens: TokenUsage(output: 1_000_000)),                          // real 5.0
    ]
    #expect(PricingEstimator.estimateReal(perModel) == Decimal(8))
}
```

- [ ] **Step 2: Spusť test — musí selhat (estimateReal neexistuje)**

Run: `swift test`
Expected: FAIL — kompilace: `type 'PricingEstimator' has no member 'estimateReal'`. (Pozn. F1: NEpoužívej `--filter`.)

- [ ] **Step 3: Přidej `estimateReal` do `PricingEstimator.swift`**

V `Sources/StatusBarKit/Pricing/PricingEstimator.swift` přidej do `enum PricingEstimator` (za stávající `estimate(_:)` overloady) tyto dvě funkce:

```swift
    /// Reálná cena: jen input+output tokeny (přijaté+odeslané), BEZ cache. Pro „co nejvíc reálná spotřeba".
    public static func estimateReal(_ tokens: TokenUsage, model: String) -> Decimal {
        guard let p = PricingTable.pricing(forModel: model) else { return 0 }
        let perMillion = Decimal(1_000_000)
        func part(_ count: UInt, _ price: Decimal) -> Decimal { (Decimal(count) / perMillion) * price }
        return part(tokens.input, p.input) + part(tokens.output, p.output)
    }
    public static func estimateReal(_ perModel: [ModelTokens]) -> Decimal {
        perModel.reduce(Decimal(0)) { $0 + estimateReal($1.tokens, model: $1.modelName) }
    }
```

- [ ] **Step 4: Spusť test — musí projít**

Run: `swift test`
Expected: PASS (3 nové testy zelené).

- [ ] **Step 5: Přepni scannery na `estimateReal`**

V `Sources/StatusBarKit/Providers/ClaudeTokenScanner.swift` na řádku 33 změň:

```swift
        return TodayUsage(perModel: perModel, estimatedCost: PricingEstimator.estimateReal(perModel))
```

V `Sources/StatusBarKit/Providers/CodexTokenScanner.swift` na řádku 33 změň:

```swift
        return TodayUsage(perModel: perModel, estimatedCost: PricingEstimator.estimateReal(perModel))
```

- [ ] **Step 6: Doplň doc komentář v `TokenUsage.swift`**

V `Sources/StatusBarKit/Models/TokenUsage.swift` u `public let estimatedCost: Decimal` (v `TodayUsage`) přidej nad/za něj komentář:

```swift
    public let estimatedCost: Decimal   // reálná cena: jen input+output, BEZ cache (PricingEstimator.estimateReal)
```

- [ ] **Step 7: Spusť celý balík + build (žádná regrese)**

Run: `swift build && swift test`
Expected: Build complete (0 warnings); všechny testy PASS — vč. `ClaudeTokenScannerTests`/`CodexTokenScannerTests` (`estimatedCost > 0` stále drží, protože fixtury mají reálné tokeny) a `PricingEstimatorTests` (plná `estimate` beze změny).

- [ ] **Step 8: Commit**

```bash
git add Sources/StatusBarKit/Pricing/PricingEstimator.swift Sources/StatusBarKit/Providers/ClaudeTokenScanner.swift Sources/StatusBarKit/Providers/CodexTokenScanner.swift Sources/StatusBarKit/Models/TokenUsage.swift Tests/StatusBarKitTests/PricingEstimatorTests.swift
git commit -m "feat: reálná cena (estimateReal jen input+output), scannery ji použijí"
```

---

### Task 2: Error-path testy + verze 0.7.2

**Files:**
- Modify (test): `Tests/StatusBarKitTests/ClaudeUsageAPITests.swift`
- Modify (test): `Tests/StatusBarKitTests/ClaudeUsageCacheParserTests.swift`
- Modify (test): `Tests/StatusBarKitTests/CodexUsageAPITests.swift`
- Modify (test): `Tests/StatusBarKitTests/CodexRateLimitParserTests.swift`
- Modify (test): `Tests/StatusBarKitTests/PricingEstimatorTests.swift`
- Modify (test): `Tests/StatusBarKitTests/ClaudeCodeCollectorTests.swift`
- Modify: `Resources/Info.plist` (verze 0.7.2)

**Interfaces:**
- Consumes: `ClaudeUsageCacheParser.parseAPIWindows(_:)` (throws `[UsageWindow]`), `ClaudeUsageCacheParser.parse(_:)` (throws `ProviderUsage`), `CodexUsageAPIParser.parse(_:) -> CodexSnapshot?`, `CodexRateLimitParser.latestSnapshot(fromJSONL:) -> CodexSnapshot?`, `PricingTable.pricing(forModel:) -> ModelPricing?`, `PricingEstimator.estimate(_:model:)`, `ClaudeCodeCollector`.
- Produces: pouze testy (žádné nové produkční API).

- [ ] **Step 1: Claude API parser error testy → `ClaudeUsageAPITests.swift`**

Přidej na konec `Tests/StatusBarKitTests/ClaudeUsageAPITests.swift`:

```swift
@Test func apiParserHodíChybnýJSON() {
    #expect(throws: (any Error).self) { _ = try ClaudeUsageCacheParser.parseAPIWindows(Data("nonsense".utf8)) }
}

@Test func apiParserPrázdnéLimitsPrázdnéPole() throws {
    let w = try ClaudeUsageCacheParser.parseAPIWindows(Data(#"{"limits":[]}"#.utf8))
    #expect(w.isEmpty)
}

@Test func apiParserNeznámýKindIgnorován() throws {
    // kind "daily" není mapován → přeskočí; "session" zůstane
    let json = #"{"limits":[{"kind":"daily","percent":50},{"kind":"session","percent":20}]}"#
    let w = try ClaudeUsageCacheParser.parseAPIWindows(Data(json.utf8))
    #expect(w.count == 1)
    #expect(w.first?.kind == .rolling5h)
}
```

- [ ] **Step 2: Claude cache parser strukturální error test → `ClaudeUsageCacheParserTests.swift`**

Přidej na konec `Tests/StatusBarKitTests/ClaudeUsageCacheParserTests.swift`:

```swift
@Test func parseClaudeStrukturálněNeúplnýHodí() {
    // validní JSON, ale chybí povinné pole "data" → DecodingError (jiný případ než "nonsense")
    #expect(throws: (any Error).self) { _ = try ClaudeUsageCacheParser.parse(Data(#"{"timestamp":123.0}"#.utf8)) }
}
```

- [ ] **Step 3: Codex API parser edge testy → `CodexUsageAPITests.swift`**

Přidej na konec `Tests/StatusBarKitTests/CodexUsageAPITests.swift`:

```swift
@Test func codexAPIParserUsedPercentNilOknoNil() {
    // primary bez used_percent → okno se nevytvoří; žádné secondary → nil
    let data = Data(#"{"plan_type":"plus","rate_limit":{"primary_window":{"limit_window_seconds":18000,"reset_at":1}}}"#.utf8)
    #expect(CodexUsageAPIParser.parse(data) == nil)
}

@Test func codexAPIParserLimitWindowSecondsNilJe5h() {
    // primary bez limit_window_seconds → (nil ?? 0) < 86400 → .rolling5h
    let data = Data(#"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":50,"reset_at":1}}}"#.utf8)
    let snap = CodexUsageAPIParser.parse(data)
    #expect(snap?.windows.count == 1)
    #expect(snap?.windows.first?.kind == .rolling5h)
}
```

- [ ] **Step 4: Codex JSONL rate-limit parser edge testy → `CodexRateLimitParserTests.swift`**

Přidej na konec `Tests/StatusBarKitTests/CodexRateLimitParserTests.swift`:

```swift
@Test func codexRateLimitParserJenSekundární() {
    let line = #"{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":null,"secondary":{"used_percent":30.0,"window_minutes":10080,"resets_at":1},"plan_type":"plus"}}}"#
    let snap = CodexRateLimitParser.latestSnapshot(fromJSONL: Data(line.utf8))
    #expect(snap?.windows.count == 1)
    #expect(snap?.windows.first?.kind == .weekly(scope: nil))
}

@Test func codexRateLimitParserObaUsedPercentNil() {
    // primary i secondary existují, ale oba bez used_percent → windows prázdné → nil
    let line = #"{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"window_minutes":300,"resets_at":1},"secondary":{"window_minutes":10080,"resets_at":1},"plan_type":"plus"}}}"#
    #expect(CodexRateLimitParser.latestSnapshot(fromJSONL: Data(line.utf8)) == nil)
}
```

- [ ] **Step 5: Pricing edge testy → `PricingEstimatorTests.swift`**

Přidej na konec `Tests/StatusBarKitTests/PricingEstimatorTests.swift`:

```swift
@Test func odhadCacheWriteSonnetHaiku() {
    // Sonnet cacheWrite 3.75 / 1M; Haiku cacheWrite 1.25 / 1M (plná estimate)
    #expect(PricingEstimator.estimate(TokenUsage(cacheWrite: 1_000_000), model: "claude-sonnet-4-6") == Decimal(string: "3.75")!)
    #expect(PricingEstimator.estimate(TokenUsage(cacheWrite: 1_000_000), model: "claude-haiku-4-5") == Decimal(string: "1.25")!)
}

@Test func pricingTableGPT5Větve() {
    let g5 = PricingTable.pricing(forModel: "gpt-5")
    #expect(g5?.input == Decimal(string: "2.5")!)
    #expect(g5?.output == Decimal(15))
    let g55 = PricingTable.pricing(forModel: "gpt-5.5")
    #expect(g55?.input == Decimal(5))
    #expect(g55?.output == Decimal(30))
}
```

- [ ] **Step 6: Collector prázdný-soubor test → `ClaudeCodeCollectorTests.swift`**

Přidej na konec `Tests/StatusBarKitTests/ClaudeCodeCollectorTests.swift`:

```swift
@Test func collectorPrázdnýSouborUnavailable() async throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cc-empty-\(UUID().uuidString).json")
    try Data().write(to: tmp)                       // existující 0-bajtový soubor
    defer { try? FileManager.default.removeItem(at: tmp) }
    let u = await ClaudeCodeCollector(cachePath: tmp, staleAfter: .greatestFiniteMagnitude).fetch(includeToday: false)
    if case .unavailable = u.status {} else { Issue.record("čekán .unavailable, byl \(u.status)") }
}
```

- [ ] **Step 7: Spusť celý balík — vše musí projít**

Run: `swift test`
Expected: PASS — 11 nových error-path testů zelených (celkem ~92 testů). Pokud kterýkoli SELŽE na chování (ne kompilaci), ZASTAV a nahlas — může jít o reálný bug nebo nepřesné očekávání (viz Guardrails).

- [ ] **Step 8: Bump verze v `Info.plist`**

V `Resources/Info.plist` změň obě pole na `0.7.2`:

```xml
  <key>CFBundleVersion</key><string>0.7.2</string>
  <key>CFBundleShortVersionString</key><string>0.7.2</string>
```

- [ ] **Step 9: Ověř build + test**

Run: `swift build && swift test`
Expected: Build complete (0 warnings); všechny testy PASS.

- [ ] **Step 10: Commit**

```bash
git add Tests/StatusBarKitTests/ClaudeUsageAPITests.swift Tests/StatusBarKitTests/ClaudeUsageCacheParserTests.swift Tests/StatusBarKitTests/CodexUsageAPITests.swift Tests/StatusBarKitTests/CodexRateLimitParserTests.swift Tests/StatusBarKitTests/PricingEstimatorTests.swift Tests/StatusBarKitTests/ClaudeCodeCollectorTests.swift Resources/Info.plist
git commit -m "test: error-path testy (parser/pricing/collector) + verze 0.7.2"
```

---

## Verifikace (po všech taskách)
- `swift build` čistý (Kit+App), `swift test` zelený (existující + ~14 nových testů).
- Zobrazená cena = reálná (input+output); plná cena s cache se nikde neukazuje.
- GAP (ověří uživatel): vizuál nižší (reálné) ceny v popoveru.

## Rollback & Recovery
Aditivní (estimateReal + testy + verze). Rollback = `git revert`/`git checkout main -- <soubory>`. Žádná migrace, žádný stav.

## Risk Register
| ID | Severity | Likelihood | Risk | Mitigace (krok) | Resolution |
|----|----------|------------|------|-----------------|------------|
| R1 | LOW | L | scanner test `> 0` se rozbije při 0 reálných tokenech | ověřeno: fixtury mají input/output > 0 (T1 S7) | mitigated |
| R2 | LOW | L | `estimateReal` mění semantiku `estimatedCost` → exaktní test | žádný test neasertuje exaktní scanner cenu; plná `estimate` zachována+testována | fixed |
| R3 | LOW | M | error-path test odhalí reálný bug v parseru | Guardrails stop-and-report; eskalovat při neshodě se specem | mitigated |

## Audit Trail
- **Lenses applied:** 1 red-team, 2 security (N/A — jen testy + pricing math, žádné secrets/síť/destruktivní operace), 3 assumptions, 4 dependencies, 5 alternatives, 6 cheap-executor, 7 goal-fit.
- **Empirická verifikace (klíčová):** všech 14 plánovaných asercí (3× estimateReal + 11 error-path) bylo dočasně přidáno do scratch test souboru (+ temp estimateReal) a spuštěno `swift test` proti reálnému kódu → **14/14 PASS**. Tím je vyloučeno nejvyšší riziko testově-těžkého plánu (chybné očekávání). Scratch revertnut, strom čistý, baseline zpět na 78.
- **Alternativy (lens 5):** (a) `estimateReal` jako samostatná funkce + `estimatedCost` field drží reálnou cenu *(zvoleno — minimální ripple, popover beze změny, plná `estimate` zachována)*; (b) parametr `includeCache` na `estimate` (méně čitelné call-sites); (c) přejmenovat field na `estimatedRealCost` (ripple do PopoverView). 
- **Findings:** 0 CRIT, 0 HIGH, 0 MED, 1 LOW (scanner-switch `>0` ověřen reasoningem, ne spuštěním — fixtury mají input/output > 0; Task 1 Step 7 potvrdí). 
- **Re-audit po hardeningu (R*):** none.
- **Tabletop dry run:** PASSED — build zelený po každém tasku (Task 1 aditivní estimateReal; Task 2 jen testy + verze); Task 2 nezávislý na Task 1; identifikátory konzistentní (`estimateReal`, `estimate`, `PricingTable.pricing`, `estimatedCost` field nezměněn).
- **Rozhodnutí:** spuštěno s defaulty dle uživatelovy delegace („můžeš to prohnat"); 0 nálezů k rozhodnutí; kill criterion (Task 1 testy nezelené po 2 pokusech → stop) v Guardrails.
- **K hlídání:** vizuál nižší reálné ceny (ověří uživatel); error-path test by mohl odhalit reálný bug v parseru → Guardrails stop-and-report (žádný se ale při verifikaci neprojevil).
