# StatusBar v0.5 — Líný sken today + polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Sken dnešních tokenů spouštět jen při otevření popoveru / manuálním refreshi (ne každých 60s); background refresh zachová poslední „Dnes" (žádné blikání). Plus polish z review.

**Architecture:** `UsageProvider.fetch(includeToday:)` gatuje sken v collectorech; `RefreshCoordinator.refreshNow(includeToday:)` drží cache `lastToday` a při `false` ji přiloží. AppDelegate: timer/start=`false`, klik/refresh=`true`. Jádro plně unit-testované.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing, AppKit/SwiftUI. macOS 14+. Navazuje na v0.4 (`main` na `aee90a5`; větev `feat/v0.5-lazy-scan`).

## Global Constraints
- macOS 14+, Swift 6, Swift Testing. Čtení jen pro čtení; žádný zápis do `~/.claude`/`~/.codex`; žádné logování surového obsahu.
- **Migrace signatury `fetch` zasáhne tato místa** (enumerováno): deklarace v `UsageProvider`, `ClaudeCodeCollector`, `CodexCollector`, `RefreshCoordinatorTests` Stub; call-site v `RefreshCoordinator`; call-sites v `ClaudeCodeCollectorTests` (3×), `CodexCollectorTests` (2×); `refreshNow` call-sites v `AppDelegate` (3×).
- `refreshNow(includeToday: Bool = true)` — default `true` (zpětná kompatibilita testu `refreshNowNaplníStoreJednímZápisem`).
- Limit-část (parsery, `UsageStore`) i UI se jinak nemění; v0.3 alert-path (`onRefreshed`) zůstává.
- TDD stub-first (SwiftPM kompiluje celý cíl; „red" = selhaný `#expect`). Commit po každém tasku.

---

### Task 1: Líný sken today (protokol + collectory + koordinátor + wiring)

**Files:**
- Modify: `Sources/StatusBarKit/Providers/UsageProvider.swift`
- Modify: `Sources/StatusBarKit/Providers/ClaudeCodeCollector.swift`
- Modify: `Sources/StatusBarKit/Providers/CodexCollector.swift`
- Modify: `Sources/StatusBarKit/Store/RefreshCoordinator.swift`
- Modify: `Sources/StatusBarApp/AppDelegate.swift`
- Modify: `Tests/StatusBarKitTests/RefreshCoordinatorTests.swift` (Stub signatura + nové preserve testy)
- Modify: `Tests/StatusBarKitTests/ClaudeCodeCollectorTests.swift` (call-sites + gate test)
- Modify: `Tests/StatusBarKitTests/CodexCollectorTests.swift` (call-sites)

**Interfaces:**
- Produces: `UsageProvider.fetch(includeToday: Bool)`; `RefreshCoordinator.refreshNow(includeToday: Bool = true)` s cache `lastToday`.

- [ ] **Step 1: Modify `UsageProvider.swift` — signatura.**

Najdi přesně (`old_string`):
```swift
    func fetch() async -> ProviderUsage
```
nahraď (`new_string`):
```swift
    func fetch(includeToday: Bool) async -> ProviderUsage
```

- [ ] **Step 2: Modify `ClaudeCodeCollector.swift` — gate sken.**

Najdi přesně (`old_string`):
```swift
    public func fetch() async -> ProviderUsage {
```
nahraď (`new_string`):
```swift
    public func fetch(includeToday: Bool) async -> ProviderUsage {
```
A najdi přesně (`old_string`):
```swift
            let today = ClaudeTokenScanner().todayUsage(now: now)
```
nahraď (`new_string`):
```swift
            let today = includeToday ? ClaudeTokenScanner().todayUsage(now: now) : nil
```

- [ ] **Step 3: Modify `CodexCollector.swift` — gate sken.**

Najdi přesně (`old_string`):
```swift
    public func fetch() async -> ProviderUsage {
```
nahraď (`new_string`):
```swift
    public func fetch(includeToday: Bool) async -> ProviderUsage {
```
A najdi přesně (`old_string`):
```swift
            let today = CodexTokenScanner().todayUsage(now: now)
```
nahraď (`new_string`):
```swift
            let today = includeToday ? CodexTokenScanner().todayUsage(now: now) : nil
```

- [ ] **Step 4: Modify `RefreshCoordinator.swift` — signatura + průchod `includeToday` (BEZ cache — stub pro preserve).** Nahraď CELÝ obsah souboru:

```swift
import Foundation

@MainActor
public final class RefreshCoordinator {
    private let store: UsageStore
    private let providers: [any UsageProvider]
    private var lastToday: [ProviderID: TodayUsage] = [:]
    /// Zavolá se po každém refreshi s novými daty (default no-op). App vrstva sem napojí vyhodnocení upozornění.
    public var onRefreshed: ([ProviderUsage]) -> Void = { _ in }
    public init(store: UsageStore, providers: [any UsageProvider]) { self.store = store; self.providers = providers }
    public func refreshNow(includeToday: Bool = true) async {
        var results: [ProviderUsage] = []
        await withTaskGroup(of: ProviderUsage.self) { group in
            for p in providers { group.addTask { await p.fetch(includeToday: includeToday) } }
            for await u in group { results.append(u) }
        }
        // STUB: zatím bez cache/preserve (doplní Step 8)
        store.replaceAll(results)
        onRefreshed(results)
    }
}
```

- [ ] **Step 5: Modify testy — aktualizuj call-sites na novou signaturu (aby cíl kompiloval).**
  - `RefreshCoordinatorTests.swift`: ve `Stub` nahraď `func fetch() async -> ProviderUsage {` za `func fetch(includeToday: Bool) async -> ProviderUsage {`. (Volání `.refreshNow()` nech — default `true`.)
  - `ClaudeCodeCollectorTests.swift`: nahraď všechny 3× `.fetch()` za `.fetch(includeToday: false)`.
  - `CodexCollectorTests.swift`: nahraď obě 2× `.fetch()` za `.fetch(includeToday: false)`.

- [ ] **Step 6: Build + Run → GREEN baseline.** `swift build` čistý; `swift test` → 43/43 (chování zachováno; preserve logika ještě není, ale není pro ni test).
- [ ] **Step 7: Přidej nové testy do `RefreshCoordinatorTests.swift`** (na konec souboru). Pozn.: `TodayStub` vrací today jen při `includeToday: true`:

```swift
private struct TodayStub: UsageProvider {
    let id: ProviderID
    func fetch(includeToday: Bool) async -> ProviderUsage {
        let today = includeToday
            ? TodayUsage(perModel: [ModelTokens(modelName: "x", tokens: TokenUsage(input: 100))], estimatedCost: 1)
            : nil
        return ProviderUsage(providerId: id, displayName: id.rawValue, planLabel: nil,
            windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.5, resetAt: nil)],
            status: .ok, lastUpdated: Date(), today: today)
    }
}

@MainActor @Test func líneRefreshZachováTodayMeziSkeny() async {
    let store = UsageStore()
    let coord = RefreshCoordinator(store: store, providers: [TodayStub(id: .claudeCode)])
    await coord.refreshNow(includeToday: true)
    #expect(store.providers[.claudeCode]?.today != nil)        // čerstvý sken
    await coord.refreshNow(includeToday: false)
    #expect(store.providers[.claudeCode]?.today != nil)        // NEzmizelo (cache)
}

@MainActor @Test func líneRefreshBezPředchozíhoSkenuNemáToday() async {
    let store = UsageStore()
    let coord = RefreshCoordinator(store: store, providers: [TodayStub(id: .claudeCode)])
    await coord.refreshNow(includeToday: false)
    #expect(store.providers[.claudeCode]?.today == nil)        // nic k zachování
}
```

A přidej do `ClaudeCodeCollectorTests.swift` gate test (deterministický — sken se nespustí). Využij existující helper `copyFixtureToTemp()` v tom souboru:

```swift
@Test func collectorIncludeTodayFalseNemáToday() async throws {
    let tmp = try copyFixtureToTemp()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let u = await ClaudeCodeCollector(cachePath: tmp, staleAfter: .greatestFiniteMagnitude).fetch(includeToday: false)
    #expect(u.today == nil)   // includeToday=false → scanner se nespustí
}
```

- [ ] **Step 8: Run → RED.** `swift test --filter RefreshCoordinatorTests` → Expected: `líneRefreshZachováTodayMeziSkeny` FAIL (po `false` refreshi je today `nil` — stub bez cache), ostatní PASS.
- [ ] **Step 9: Implementuj cache/preserve** — v `RefreshCoordinator.refreshNow` nahraď STUB blok:

```swift
        // STUB: zatím bez cache/preserve (doplní Step 8)
        store.replaceAll(results)
        onRefreshed(results)
```
za:
```swift
        if includeToday {
            for r in results {
                if let t = r.today { lastToday[r.providerId] = t } else { lastToday.removeValue(forKey: r.providerId) }
            }
        } else {
            results = results.map { $0.with(today: lastToday[$0.providerId]) }
        }
        store.replaceAll(results)
        onRefreshed(results)
```

- [ ] **Step 10: Run → GREEN.** `swift test` → Expected: vše PASS (43 + 3 nové = 46).
- [ ] **Step 11: Modify `AppDelegate.swift` — wiring `true`/`false`.**

Najdi přesně (`old_string`):
```swift
        menuBar = MenuBarController(store: store, onClick: { [weak self] in
            Task { await self?.coordinator.refreshNow() }
        }, onOpenSettings: { [weak self] in
            self?.settings.show()
        })
        Task { await coordinator.refreshNow() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.coordinator.refreshNow() }
        }
```
nahraď (`new_string`):
```swift
        menuBar = MenuBarController(store: store, onClick: { [weak self] in
            Task { await self?.coordinator.refreshNow(includeToday: true) }   // popover/refresh → skenuj today
        }, onOpenSettings: { [weak self] in
            self?.settings.show()
        })
        Task { await coordinator.refreshNow(includeToday: false) }            // start: jen limity (rychle)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.coordinator.refreshNow(includeToday: false) }   // background: jen limity
        }
```

- [ ] **Step 12: Build + smoke.** `swift test` → 46/46. `swift build` čistý. `./scripts/make-app.sh debug && open StatusBar.app` → app naběhne; menu bar limity hned; po otevření popoveru se „Dnes" naskenuje a zobrazí; popnutý popover „Dnes" nebliká při background refreshi.
- [ ] **Step 13: Commit.**

```bash
git add Sources/StatusBarKit/Providers/UsageProvider.swift Sources/StatusBarKit/Providers/ClaudeCodeCollector.swift Sources/StatusBarKit/Providers/CodexCollector.swift Sources/StatusBarKit/Store/RefreshCoordinator.swift Sources/StatusBarApp/AppDelegate.swift Tests/StatusBarKitTests
git commit -m "feat: líný sken today — sken jen při otevření popoveru, background zachová Dnes"
```

**Verify success (Task 1):** `swift test` 46/46; `swift build` čistý; app naběhne.
**On failure:** kterýkoli `old_string` nesedí → přečti reálný soubor, aplikuj princip. ZASTAV, neimprovizuj.

---

### Task 2: Polish — `gpt-5.x` komentář + negativní `CodexTokenScanner` testy + midnight-clear test

**Files:**
- Modify: `Sources/StatusBarKit/Pricing/PricingTable.swift`
- Modify: `Tests/StatusBarKitTests/CodexTokenScannerTests.swift`
- Modify: `Tests/StatusBarKitTests/RefreshCoordinatorTests.swift` (test midnight-clearing větve)

- [ ] **Step 1: Modify `PricingTable.swift` — komentář k dead-code větvím.**

Najdi přesně (`old_string`):
```swift
        if m.contains("codex")  { return ModelPricing(input: d("1.75"), output: d("14"), cacheWrite: d("0"),    cacheRead: d("0.175")) }
```
nahraď (`new_string`):
```swift
        if m.contains("codex")  { return ModelPricing(input: d("1.75"), output: d("14"), cacheWrite: d("0"),    cacheRead: d("0.175")) }
        // Pozn.: gpt-5.x větve níže nejsou aktuálně dosažitelné za běhu — CodexTokenScanner emituje model "codex"
        // (Codex info neuvádí název modelu). Ponechány pro budoucí přímé OpenAI API použití a korektnost tabulky.
```

- [ ] **Step 2: Přidej negativní testy do `CodexTokenScannerTests.swift`** (na konec souboru):

```swift
@Test func codexScannerVčerejšíMtimeIgnoruje() throws {
    let cal = Calendar.current
    var comps = DateComponents(); comps.year = 2026; comps.month = 6; comps.day = 23; comps.hour = 12
    let now = cal.date(from: comps)!
    let včera = cal.date(byAdding: .day, value: -1, to: now)!
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("codexNeg-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let file = tmp.appendingPathComponent("rollout.jsonl")
    let jsonl = #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":200,"reasoning_output_tokens":0,"total_tokens":1200}}}}"#
    try jsonl.data(using: .utf8)!.write(to: file)
    try FileManager.default.setAttributes([.modificationDate: včera], ofItemAtPath: file.path)
    #expect(CodexTokenScanner(sessionsDir: tmp).todayUsage(now: now) == nil)   // mtime < dayStart → soubor přeskočen
}

@Test func codexScannerPrázdnýAdresářNil() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("codexEmpty-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let cal = Calendar.current
    var comps = DateComponents(); comps.year = 2026; comps.month = 6; comps.day = 23; comps.hour = 12
    #expect(CodexTokenScanner(sessionsDir: tmp).todayUsage(now: cal.date(from: comps)!) == nil)
}
```

- [ ] **Step 3: Přidej test midnight-clearing větve do `RefreshCoordinatorTests.swift`** (na konec). Toggling stub: 1. `true`-sken vrátí today, 2. `true`-sken vrátí nil (simulace nového dne) → cache se vyčistí (`removeValue`):

```swift
private final class TogglingTodayStub: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    private let lock = NSLock()
    private var calls = 0
    init(id: ProviderID) { self.id = id }
    func fetch(includeToday: Bool) async -> ProviderUsage {
        lock.lock(); calls += 1; let n = calls; lock.unlock()
        let today: TodayUsage? = (includeToday && n == 1)
            ? TodayUsage(perModel: [ModelTokens(modelName: "x", tokens: TokenUsage(input: 100))], estimatedCost: 1)
            : nil
        return ProviderUsage(providerId: id, displayName: id.rawValue, planLabel: nil,
            windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.5, resetAt: nil)],
            status: .ok, lastUpdated: Date(), today: today)
    }
}

@MainActor @Test func druhýTrueSkenSNilVyčistíCache() async {
    let store = UsageStore()
    let coord = RefreshCoordinator(store: store, providers: [TogglingTodayStub(id: .claudeCode)])
    await coord.refreshNow(includeToday: true)    // 1. sken → today
    #expect(store.providers[.claudeCode]?.today != nil)
    await coord.refreshNow(includeToday: true)    // 2. sken → nil → cache vyčištěna (removeValue)
    #expect(store.providers[.claudeCode]?.today == nil)
    await coord.refreshNow(includeToday: false)   // background → cache prázdná → today nil (žádný stale)
    #expect(store.providers[.claudeCode]?.today == nil)
}
```

- [ ] **Step 4: Run → GREEN.** `swift test` → Expected: vše PASS (46 + 2 negativní + 1 clearing = 49). `swift build` čistý.
- [ ] **Step 5: Commit.**

```bash
git add Sources/StatusBarKit/Pricing/PricingTable.swift Tests/StatusBarKitTests/CodexTokenScannerTests.swift Tests/StatusBarKitTests/RefreshCoordinatorTests.swift
git commit -m "polish: gpt-5.x komentář + negativní Codex scanner testy + midnight-clear test"
```

**Verify success (Task 2):** `swift test` 49/49; `swift build` čistý.

---

## Guardrails
- Nezapínat login item; neměnit limit-parsery ani UI; nepushovat (merge lokálně, push na souhlas uživatele).
- Stop: `old_string` nesedí → ZASTAV; existující testy padají → ZASTAV (regrese).
- Kill criteria: pokud preserve logika nejde udělat deterministicky / cíl nekompiluje do 2 pokusů → STOP, report.

## Rollback & Recovery
Aditivní/refaktor na větvi `feat/v0.5-lazy-scan`. Zahodit: `git checkout main && git branch -D feat/v0.5-lazy-scan`. Per-task `git revert`.

## Audit Trail (plan-forge AUDIT)
- Lenses 1–7. Hlavní pozornost: migrace signatury (enumerováno všech 5 test call-sites + 1 src), preserve-přes-půlnoc (mitigováno: `true` sken přepíše cache i na nil). Žádné CRIT/HIGH.
- Tabletop dry run: T1 signatura→collectory→koordinátor(stub)→testy compile→RED preserve→impl preserve→AppDelegate wiring. Identifikátory konzistentní (`includeToday`, `lastToday`, `with(today:)`).
- Decisions (autonomně k tomuto rozsahu): start/timer=false, klik/refresh=true; default `refreshNow(includeToday:true)`; collector gate test přes fixturu; merge bez push.

## Hotová definice v0.5
- Today-sken jen při otevření popoveru / refreshi; background (60s) jen limity, „Dnes" se zachová (žádné blikání).
- Koordinátorová cache + preserve pokryté unit testy; gate (`includeToday:false`→`today=nil`) testovaný; negativní Codex scanner testy; `gpt-5.x` komentář.
- `swift test` 48/48; app naběhne; limit/UI logika beze změny.

## Mimo v0.5 (další fáze)
- **v0.6:** přepínatelné styly lišty (B/C/D) + přepínatelné zbývající/vyčerpané %; OpenAI API (až Admin klíč).
