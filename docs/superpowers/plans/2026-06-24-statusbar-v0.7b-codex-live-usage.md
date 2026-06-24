# StatusBar v0.7b — Živé Codex/OpenAI limity — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Codex limity z živého `chatgpt.com/backend-api/wham/usage` (čerstvá %, správné resety, plán „Plus") s fallbackem na stávající session JSONL; default chování (bez živého zdroje) beze změny.

**Architecture:** Mirror v0.6. Kit (pure): `CodexUsageAPIParser` (parse wham/usage JSON → existující `CodexSnapshot`) + `CodexPlan.label` + `CodexUsageSource` protokol; `CodexCollector` zkusí živý zdroj → fallback na JSONL. App: `CodexAuth` (čte `~/.codex/auth.json`) + `LiveCodexUsageSource` (soubor+URLSession). Token jen in-memory.

**Tech Stack:** Swift 6 (strict concurrency), SwiftPM (`StatusBarKit` + `StatusBarApp`), URLSession, Swift Testing (`@Test`/`#expect`).

## Global Constraints

- Swift 6 strict concurrency. Non-Sendable `static let` formátter NEpoužívat (vytvářet lokálně).
- `StatusBarKit` zůstává pure — žádný `import AppKit`/`SwiftUI`/`Security`/síť. Síť+soubor auth JEN v `StatusBarApp`.
- **Bezpečnost:** access_token i account_id z `~/.codex/auth.json` se NIKDY nelogují, neukládají, neposílají jinam — jen in-memory pro volání uživatelova vlastního usage endpointu.
- **Fallback:** jakékoli selhání živého zdroje (chybějící/expirovaný token, ≠200, offline, prázdná data) → `nil` → stávající JSONL cesta. Žádný pád, žádná regrese chování v0.1–v0.7a.
- **`CodexPlan.label` se aplikuje JEN v `CodexCollector`** při stavbě `ProviderUsage` (na obou cestách — živé i JSONL), NIKDY v parserech. Důsledek na testy: `CodexRateLimitParserTests` testuje `snap.planType == "plus"` na PARSERU → zůstává raw, zelený; `CodexCollectorTests` planLabel assertion `== "plus"` → **aktualizovat na `== "Plus"`** (záměrná změna, ne regrese).
- Endpoint: **`https://chatgpt.com/backend-api/wham/usage`** (NE `/api/codex/usage` — vrací 403 přes WAF). Hlavičky: `Authorization: Bearer <access_token>`, `chatgpt-account-id: <account_id>`, `User-Agent: codex_cli_rs/0.135.0`, `Accept: application/json`. `timeoutInterval = 10`.
- Okno: `limit_window_seconds < 86400` → `.rolling5h`, jinak `.weekly(scope: nil)`. `usedFraction = used_percent/100`. `resetAt = Date(timeIntervalSince1970: reset_at)`.
- `CodexCollector.init` dostane nový **defaultovaný** parametr `liveSource: (any CodexUsageSource)? = nil` → stávající volání (`CodexCollector()`, testy) kompilují beze změny.
- **Testy jsou volné `@Test func` bez `@Suite`/typu:** ověřuj VŽDY plným `swift test`, NIKDY `swift test --filter <NázevSouboru>` (nematchne nic → falešný PASS).
- **App smoke:** agentova brána = `swift build && swift test` + `bash scripts/make-app.sh` (exit 0). Agent NESMÍ spouštět výslednou `.app` (GUI by visel). Vizuál ověří uživatel.
- České UI/test názvy s diakritikou. Bundle verze → `0.7.1` (`Resources/Info.plist`, obě pole).
- TDD, časté commity, DRY, YAGNI.

## Guardrails
- **Zakázané akce:** logovat/ukládat token nebo account_id; psát do `~/.codex`; dát `StatusBarKit` síťovou/souborovou auth závislost; měnit chování JSONL fallbacku nad rámec `CodexPlan.label`.
- **Žádná nevratná operace** — aditivní kód + napojení; rollback = `git revert`/`git checkout`.
- **Stop podmínky:** selže-li ověření kroku, postupuj dle „On failure"; nikdy neimprovizuj náhradní endpoint/API.
- **Kill criterion:** když Task 1 Kit testy nejdou zezelenat ani po 2 pokusech implementera → ZASTAV a nahlas.

---

### Task 1: Kit — `CodexUsageAPIParser` + `CodexPlan`

**Files:**
- Create: `Sources/StatusBarKit/Providers/CodexUsageAPIParser.swift`
- Create: `Sources/StatusBarKit/Providers/CodexPlan.swift`
- Create (fixture): `Tests/StatusBarKitTests/Fixtures/codex-wham-usage.json`
- Create (test): `Tests/StatusBarKitTests/CodexUsageAPITests.swift`

**Interfaces:**
- Consumes: `CodexSnapshot {windows: [UsageWindow], planType: String?}` (existuje v `CodexRateLimitParser.swift`), `UsageWindow`, `WindowKind`.
- Produces:
  - `public enum CodexUsageAPIParser { public static func parse(_ data: Data) -> CodexSnapshot? }`
  - `public enum CodexPlan { public static func label(forPlanType raw: String?) -> String? }`

- [ ] **Step 1: Napiš fixturu `codex-wham-usage.json` (redahovaný reálný tvar ze spiku)**

Create `Tests/StatusBarKitTests/Fixtures/codex-wham-usage.json`:

```json
{
  "plan_type": "plus",
  "rate_limit": {
    "allowed": true,
    "limit_reached": false,
    "primary_window":   { "used_percent": 1,  "limit_window_seconds": 18000,  "reset_after_seconds": 18000,  "reset_at": 1782312918 },
    "secondary_window": { "used_percent": 12, "limit_window_seconds": 604800, "reset_after_seconds": 147918, "reset_at": 1782442836 }
  },
  "code_review_rate_limit": null,
  "additional_rate_limits": null,
  "credits": { "has_credits": false, "unlimited": false, "balance": "0" }
}
```

- [ ] **Step 2: Napiš `CodexPlan.swift`**

Create `Sources/StatusBarKit/Providers/CodexPlan.swift`:

```swift
import Foundation

public enum CodexPlan {
    /// Mapuje `plan_type` z wham/usage na čitelný štítek. nil/"" → nil.
    public static func label(forPlanType raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "plus":       return "Plus"
        case "pro":        return "Pro"
        case "free":       return "Free"
        case "team":       return "Team"
        case "enterprise": return "Enterprise"
        default:           return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }
}
```

- [ ] **Step 3: Napiš `CodexUsageAPIParser.swift`**

Create `Sources/StatusBarKit/Providers/CodexUsageAPIParser.swift`:

```swift
import Foundation

/// Parsuje odpověď živého Codex usage endpointu (chatgpt.com/backend-api/wham/usage)
/// do existujícího CodexSnapshot. nil = bez čerstvých dat → fallback na JSONL.
public enum CodexUsageAPIParser {
    private struct Response: Decodable {
        let plan_type: String?
        let rate_limit: RateLimit?
    }
    private struct RateLimit: Decodable {
        let primary_window: Window?
        let secondary_window: Window?
    }
    private struct Window: Decodable {
        let used_percent: Double?
        let limit_window_seconds: Double?
        let reset_at: Double?
    }

    private static func window(from w: Window) -> UsageWindow? {
        guard let pct = w.used_percent else { return nil }
        // Okno dle limit_window_seconds: 18000 (5h) vs 604800 (týden). Práh 1 den.
        let kind: WindowKind = (w.limit_window_seconds ?? 0) < 86400 ? .rolling5h : .weekly(scope: nil)
        let reset = w.reset_at.map { Date(timeIntervalSince1970: $0) }
        return UsageWindow(kind: kind, usedFraction: pct / 100.0, resetAt: reset)
    }

    public static func parse(_ data: Data) -> CodexSnapshot? {
        guard let r = try? JSONDecoder().decode(Response.self, from: data),
              let rl = r.rate_limit else { return nil }
        var windows: [UsageWindow] = []
        if let p = rl.primary_window, let w = window(from: p) { windows.append(w) }
        if let s = rl.secondary_window, let w = window(from: s) { windows.append(w) }
        guard !windows.isEmpty else { return nil }
        return CodexSnapshot(windows: windows, planType: r.plan_type)
    }
}
```

- [ ] **Step 4: Napiš testy `CodexUsageAPITests.swift`**

Create `Tests/StatusBarKitTests/CodexUsageAPITests.swift`:

```swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func codexAPIParserVytvoříOkna() throws {
    let url = Bundle.module.url(forResource: "codex-wham-usage", withExtension: "json", subdirectory: "Fixtures")!
    let snap = CodexUsageAPIParser.parse(try Data(contentsOf: url))
    #expect(snap != nil)
    #expect(snap?.planType == "plus")
    #expect(snap?.windows.count == 2)
    #expect(snap?.windows.contains { $0.kind == .rolling5h && abs($0.usedFraction - 0.01) < 0.0001 } == true)
    #expect(snap?.windows.contains { $0.kind == .weekly(scope: nil) && abs($0.usedFraction - 0.12) < 0.0001 } == true)
    let p = snap?.windows.first { $0.kind == .rolling5h }
    #expect(p?.resetAt == Date(timeIntervalSince1970: 1782312918))
}

@Test func codexAPIParserChybíRateLimit() {
    let data = Data(#"{"plan_type":"plus"}"#.utf8)
    #expect(CodexUsageAPIParser.parse(data) == nil)
}

@Test func codexAPIParserJenPrimary() {
    let data = Data(#"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":50,"limit_window_seconds":18000,"reset_at":111}}}"#.utf8)
    let snap = CodexUsageAPIParser.parse(data)
    #expect(snap?.windows.count == 1)
    #expect(snap?.windows.first?.kind == .rolling5h)
    #expect(snap?.planType == "pro")
}

@Test func codexAPIParserPrázdnáDataNil() {
    #expect(CodexUsageAPIParser.parse(Data("nesmysl".utf8)) == nil)
}

@Test func codexPlanLabelMapování() {
    #expect(CodexPlan.label(forPlanType: "plus") == "Plus")
    #expect(CodexPlan.label(forPlanType: "pro") == "Pro")
    #expect(CodexPlan.label(forPlanType: "free") == "Free")
    #expect(CodexPlan.label(forPlanType: nil) == nil)
    #expect(CodexPlan.label(forPlanType: "") == nil)
    #expect(CodexPlan.label(forPlanType: "business") == "Business")
}
```

- [ ] **Step 5: Spusť testy — musí projít**

Run: `swift test`
Expected: PASS, vč. 6 nových testů. (Pozn.: NEpoužívej `--filter` na jméno souboru — testy jsou volné `@Test func`.)

- [ ] **Step 6: Ověř čistý build**

Run: `swift build`
Expected: Build complete, žádné warningy.

- [ ] **Step 7: Commit**

```bash
git add Sources/StatusBarKit/Providers/CodexUsageAPIParser.swift Sources/StatusBarKit/Providers/CodexPlan.swift Tests/StatusBarKitTests/Fixtures/codex-wham-usage.json Tests/StatusBarKitTests/CodexUsageAPITests.swift
git commit -m "feat: CodexUsageAPIParser (wham/usage → CodexSnapshot) + CodexPlan.label"
```

---

### Task 2: Kit — `CodexUsageSource` + `CodexCollector` integrace

**Files:**
- Create: `Sources/StatusBarKit/Providers/CodexUsageSource.swift`
- Modify: `Sources/StatusBarKit/Providers/CodexCollector.swift`
- Modify (test): `Tests/StatusBarKitTests/CodexCollectorTests.swift`

**Interfaces:**
- Consumes: `CodexSnapshot` (Task 1), `CodexPlan.label(forPlanType:)` (Task 1), `CodexRateLimitParser.latestSnapshot(fromJSONL:)`, `CodexTokenScanner`.
- Produces:
  - `public protocol CodexUsageSource: Sendable { func fetchFresh() async -> CodexSnapshot? }`
  - `CodexCollector.init(sessionsDir:staleAfter:maxFilesToScan:liveSource:)` (nový defaultovaný `liveSource: (any CodexUsageSource)? = nil`).

- [ ] **Step 1: Napiš `CodexUsageSource.swift`**

Create `Sources/StatusBarKit/Providers/CodexUsageSource.swift`:

```swift
import Foundation

/// Zdroj ČERSTVÝCH Codex limitů (živé wham/usage API). Implementace v app vrstvě;
/// nil = nezdařilo se → fallback na session JSONL.
public protocol CodexUsageSource: Sendable {
    func fetchFresh() async -> CodexSnapshot?
}
```

- [ ] **Step 2: Napiš failing testy do `CodexCollectorTests.swift`**

Přidej na konec `Tests/StatusBarKitTests/CodexCollectorTests.swift`:

```swift
private struct FakeCodexSource: CodexUsageSource {
    let snap: CodexSnapshot?
    func fetchFresh() async -> CodexSnapshot? { snap }
}

@Test func collectorPoužijeŽivýZdroj() async {
    let snap = CodexSnapshot(windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.05, resetAt: nil)], planType: "plus")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cx-live-\(UUID().uuidString)")
    let u = await CodexCollector(sessionsDir: root, liveSource: FakeCodexSource(snap: snap)).fetch(includeToday: false)
    if case .ok = u.status {} else { Issue.record("čekán .ok z živého zdroje") }
    #expect(u.planLabel == "Plus")          // CodexPlan.label aplikován v collectoru
    #expect(u.windows.count == 1)
    #expect(u.windows.first?.kind == .rolling5h)
}

@Test func collectorFallbackNaJSONLKdyžŽivýNil() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cx-fb-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try place("codex-session-with-limits", into: root, sub: "a/s.jsonl", mtime: Date(timeIntervalSince1970: 1000))
    let u = await CodexCollector(sessionsDir: root, staleAfter: .greatestFiniteMagnitude,
                                 liveSource: FakeCodexSource(snap: nil)).fetch(includeToday: false)
    #expect(u.windows.contains { $0.kind == .rolling5h })
    #expect(u.planLabel == "Plus")          // retrofit: "plus" → "Plus"
}
```

Zároveň v témže souboru **aktualizuj stávající assertion** v testu `collectorPřeskočíNejnovějšíNullSessionAVezmeStarší`:

```swift
    #expect(u.planLabel == "Plus")
```

(původně `== "plus"` — `CodexPlan.label` teď mapuje na „Plus").

- [ ] **Step 3: Spusť testy — musí selhat**

Run: `swift test`
Expected: FAIL — kompilace (`CodexCollector` nemá `liveSource` parametr / `CodexUsageSource` neexistuje) nebo assertion `"Plus"` ≠ `"plus"`.

- [ ] **Step 4: Uprav `CodexCollector.swift` — živý zdroj → fallback + `CodexPlan.label`**

Nahraď celé tělo `Sources/StatusBarKit/Providers/CodexCollector.swift` tímto (přidá `liveSource`, větev živého zdroje, `CodexPlan.label` na obou cestách; `today` se počítá jednou nahoře — mirror `ClaudeCodeCollector`, laziness drží `includeToday`):

```swift
import Foundation

public struct CodexCollector: UsageProvider {
    public let id: ProviderID = .codex
    private let sessionsDir: URL
    private let staleAfter: TimeInterval
    private let maxFilesToScan: Int
    private let liveSource: (any CodexUsageSource)?

    public init(sessionsDir: URL? = nil, staleAfter: TimeInterval = 24 * 3600,
                maxFilesToScan: Int = 10, liveSource: (any CodexUsageSource)? = nil) {
        self.sessionsDir = sessionsDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        self.staleAfter = staleAfter
        self.maxFilesToScan = maxFilesToScan
        self.liveSource = liveSource
    }

    public func fetch(includeToday: Bool) async -> ProviderUsage {
        let now = Date()
        let today = includeToday ? CodexTokenScanner().todayUsage(now: now) : nil

        // 1) Živé wham/usage (čerstvé limity + plán). Selhání → nil → fallback na JSONL.
        if let snap = await liveSource?.fetchFresh() {
            return ProviderUsage(providerId: .codex, displayName: "Codex",
                planLabel: CodexPlan.label(forPlanType: snap.planType), windows: snap.windows,
                status: .ok, lastUpdated: now, today: today)
        }

        // 2) Fallback: session JSONL (stávající chování).
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
                planLabel: CodexPlan.label(forPlanType: snap.planType), windows: snap.windows,
                status: status, lastUpdated: f.modified, today: today)
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
}
```

- [ ] **Step 5: Spusť testy — musí projít**

Run: `swift test`
Expected: PASS — vč. 2 nových collector testů a aktualizovaného `collectorPřeskočíNejnovějšíNullSessionAVezmeStarší` (planLabel „Plus"). `CodexRateLimitParserTests` (testuje `snap.planType == "plus"` na PARSERU) zůstává zelený.

- [ ] **Step 6: Ověř čistý build**

Run: `swift build`
Expected: Build complete, žádné warningy (App stále staví — `CodexCollector()` bez `liveSource` díky defaultu).

- [ ] **Step 7: Commit**

```bash
git add Sources/StatusBarKit/Providers/CodexUsageSource.swift Sources/StatusBarKit/Providers/CodexCollector.swift Tests/StatusBarKitTests/CodexCollectorTests.swift
git commit -m "feat: CodexUsageSource + collector zkusí živé limity, fallback na JSONL"
```

---

### Task 3: App — `CodexAuth` + `LiveCodexUsageSource` + wiring + verze

**Files:**
- Create: `Sources/StatusBarApp/CodexAuth.swift`
- Create: `Sources/StatusBarApp/LiveCodexUsageSource.swift`
- Modify: `Sources/StatusBarApp/AppDelegate.swift` (napoj `liveSource` do `CodexCollector`)
- Modify: `Resources/Info.plist` (verze 0.7.1)

**Interfaces:**
- Consumes: `CodexUsageSource`, `CodexSnapshot`, `CodexUsageAPIParser.parse(_:)` (z Kitu).
- Produces: `CodexAuth.read() -> (accessToken: String, accountId: String)?`, `LiveCodexUsageSource: CodexUsageSource`.

> **Pozn.:** App vrstva nemá unit testy (soubor+síť). Ověření = `swift build && swift test` zelené + `bash scripts/make-app.sh` exit 0. **Agent NESMÍ spouštět výslednou `.app`.** Reálný runtime ověří uživatel.

- [ ] **Step 1: Napiš `CodexAuth.swift`**

Create `Sources/StatusBarApp/CodexAuth.swift`:

```swift
import Foundation

/// Přečte access_token + account_id z ~/.codex/auth.json (ChatGPT OAuth).
/// Token ani account_id se NIKDE neukládají ani neloguje.
enum CodexAuth {
    static func read() -> (accessToken: String, accountId: String)? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String, !token.isEmpty,
              let account = tokens["account_id"] as? String, !account.isEmpty
        else { return nil }
        return (token, account)
    }
}
```

- [ ] **Step 2: Napiš `LiveCodexUsageSource.swift`**

Create `Sources/StatusBarApp/LiveCodexUsageSource.swift`:

```swift
import Foundation
import StatusBarKit

/// Živý zdroj Codex limitů: ~/.codex/auth.json → GET wham/usage → CodexSnapshot.
/// Bez stavu (žádný Keychain → žádný ACL prompt). Token jen in-memory, NIKDY nelogován.
struct LiveCodexUsageSource: CodexUsageSource {
    func fetchFresh() async -> CodexSnapshot? {
        guard let auth = CodexAuth.read() else { return nil }
        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(auth.accountId, forHTTPHeaderField: "chatgpt-account-id")
        req.setValue("codex_cli_rs/0.135.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        guard let pair = try? await URLSession.shared.data(for: req),
              (pair.1 as? HTTPURLResponse)?.statusCode == 200,
              let snap = CodexUsageAPIParser.parse(pair.0),
              !snap.windows.isEmpty
        else { return nil }
        return snap
    }
}
```

- [ ] **Step 3: Napoj `liveSource` v `AppDelegate.swift`**

V `Sources/StatusBarApp/AppDelegate.swift` změň řádek vytvoření `CodexCollector()` v poli `providers`:

```swift
        coordinator = RefreshCoordinator(store: store, providers: [
            ClaudeCodeCollector(liveSource: LiveClaudeUsageSource()),
            CodexCollector(liveSource: LiveCodexUsageSource()),
        ])
```

- [ ] **Step 4: Bump verze v `Info.plist`**

V `Resources/Info.plist` změň obě pole na `0.7.1`:

```xml
  <key>CFBundleVersion</key><string>0.7.1</string>
  <key>CFBundleShortVersionString</key><string>0.7.1</string>
```

- [ ] **Step 5: Ověř čistý build + testy**

Run: `swift build && swift test`
Expected: Build complete (Kit+App, 0 warnings); všechny testy PASS.

- [ ] **Step 6: Postav `.app` artefakt (NEspouštět GUI)**

Run: `swift build -c release && bash scripts/make-app.sh`
Expected: `make-app.sh` doběhne exit 0 (`echo $?` == 0) a vyrobí `StatusBar.app`. **Agent NESMÍ `.app` spouštět** (GUI proces by visel). Nahlas cestu k `.app`.
On failure: selže-li build/make-app.sh, nahlas výstup a ZASTAV — neimprovizuj ruční bundle.

- [ ] **Step 7: Commit**

```bash
git add Sources/StatusBarApp/CodexAuth.swift Sources/StatusBarApp/LiveCodexUsageSource.swift Sources/StatusBarApp/AppDelegate.swift Resources/Info.plist
git commit -m "feat: LiveCodexUsageSource (auth.json + wham/usage) + napojení + verze 0.7.1"
```

---

## Verifikace (po všech taskách)
- `swift build` čistý (Kit+App), `swift test` zelený (stávající + ~8 nových testů).
- Default chování (bez živého zdroje, live=nil) = stávající JSONL cesta (degraded/unavailable jako dřív) + `planLabel` „Plus" místo „plus".
- GAP (ověří uživatel): reálný runtime request s živým tokenem + fresh číslo Codexu v liště (spike prokázal HTTP 200).

## Rollback & Recovery
Aditivní featura (nový kód + napojení live zdroje, žádná migrace). Rollback = `git revert`/`git checkout main -- <soubory>`. Live zdroj při jakémkoli selhání degraduje na stávající JSONL → bez živého tokenu se app chová jako v0.7a.

## Risk Register
| ID | Severity | Likelihood | Risk | Mitigace (krok) | Resolution |
|----|----------|------------|------|-----------------|------------|
| R1 | MED | M | endpoint/token nedostupné za běhu | fallback na JSONL (T2 S4), nikdy pád | mitigated |
| R2 | LOW | L | WAF blokne i wham/usage | ≠200 → nil → fallback (LiveCodexUsageSource) | mitigated |
| R3 | LOW | L | auth.json schéma se změní | CodexAuth vrátí nil → fallback | mitigated |
| R4 | LOW | M | retrofit CodexPlan.label „plus"→„Plus" rozbije test | CodexCollectorTests assertion aktualizován na „Plus" (T2 S2); parser test zůstává raw | fixed |
