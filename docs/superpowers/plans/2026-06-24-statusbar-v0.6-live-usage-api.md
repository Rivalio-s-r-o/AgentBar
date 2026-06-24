# StatusBar v0.6 — Živé Claude usage API + cost fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Claude limity brát z živého `GET /api/oauth/usage` (token z Keychainu) s fallbackem na `.usage_cache.json`; zobrazit plán („Max"); a rozlišit reálné vs. cache tokeny v „Dnes".

**Architecture:** Parser API odpovědi + plán-label (čisté, Kit). `ClaudeUsageSource` protokol (Kit) + integrace do `ClaudeCodeCollector` (try live → fallback cache). `ClaudeKeychain` + `LiveClaudeUsageSource` (app: Security/URLSession), injektované do collectoru z `AppDelegate`. Cost fix = `TokenUsage.realTokens/cacheTokens` + popover.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing, AppKit/SwiftUI, Security, URLSession. macOS 14+. Navazuje na v0.5 (`main` na `9f6aeeb`; větev `feat/v0.6-live-usage-api`).

## Global Constraints
- macOS 14+, Swift 6. Pristine build (zero warnings).
- **OAuth token JEN in-memory, NIKDY nelogovat/neukládat/neposílat jinam.** Čteme uživatelův vlastní token (`Claude Code-credentials`) jen pro jeho vlastní usage endpoint.
- **Fallback na cache při JAKÉMKOLI selhání** (keychain odmítnut/chybí, token expirovaný/401, síť, parse) → `fetchFresh()` vrátí `nil` → `ClaudeCodeCollector` použije stávající `.usage_cache.json` cestu (chování v0.1–v0.5 beze změny).
- **`Security`/`URLSession`/Keychain jen v app targetu** (`ClaudeKeychain`, `LiveClaudeUsageSource`). `StatusBarKit` zůstává bez systémového přístupu (jen protokol + čisté parsery).
- Spike-ověřená fakta: endpoint `https://api.anthropic.com/api/oauth/usage`; hlavičky `Authorization: Bearer <t>`, `anthropic-beta: oauth-2025-04-20`, `anthropic-version: 2023-06-01`; odpověď **top-level** `{…, limits:[…]}` (BEZ `data`/`timestamp` wrapperu); `limits[]` položka stejná jako cache (`kind/percent/resets_at/scope`); plán z Keychain `claudeAiOauth.subscriptionType`.
- Výpočet ceny se NEMĚNÍ (je správný); mění se jen zobrazení tokenů. Commit po každém tasku.

---

### Task 1: `ClaudeUsageCacheParser.parseAPIWindows` + `ClaudePlan.label` (pure)

**Files:**
- Modify: `Sources/StatusBarKit/Providers/ClaudeUsageCacheParser.swift` (sdílený `windows(from:)` + `parseAPIWindows`)
- Create: `Sources/StatusBarKit/Providers/ClaudePlan.swift`
- Create: `Tests/StatusBarKitTests/Fixtures/claude-api-usage.json`
- Create: `Tests/StatusBarKitTests/ClaudeUsageAPITests.swift`

**Interfaces:**
- Produces: `ClaudeUsageCacheParser.parseAPIWindows(_ data: Data) throws -> [UsageWindow]`; `ClaudePlan.label(forSubscriptionType: String?) -> String?`.

- [ ] **Step 1: Modify `ClaudeUsageCacheParser.swift` — extrahuj sdílené mapování + přidej API parser.**

Najdi přesně (`old_string`):
```swift
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

a nahraď (`new_string`):
```swift
    private struct Scope: Decodable { let model: Model? }
    private struct Model: Decodable { let display_name: String? }
    private struct APIResponse: Decodable { let limits: [LimitEntry] }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    private static func windows(from limits: [LimitEntry]) -> [UsageWindow] {
        limits.compactMap { e in
            let kind: WindowKind
            switch e.kind {
            case "session":       kind = .rolling5h
            case "weekly_all":    kind = .weekly(scope: nil)
            case "weekly_scoped": kind = .weekly(scope: e.scope?.model?.display_name)
            default: return nil
            }
            return UsageWindow(kind: kind, usedFraction: e.percent / 100.0, resetAt: parseDate(e.resets_at))
        }
    }

    public static func parse(_ data: Data) throws -> ProviderUsage {
        let cache = try JSONDecoder().decode(Cache.self, from: data)
        return ProviderUsage(providerId: .claudeCode, displayName: "Claude Code", planLabel: nil,
                             windows: windows(from: cache.data.limits), status: .ok,
                             lastUpdated: Date(timeIntervalSince1970: cache.timestamp))
    }

    /// Parse top-level odpovědi živého API (`{limits:[…]}`, bez timestamp/data wrapperu).
    public static func parseAPIWindows(_ data: Data) throws -> [UsageWindow] {
        windows(from: try JSONDecoder().decode(APIResponse.self, from: data).limits)
    }
}
```

- [ ] **Step 2: Create `Sources/StatusBarKit/Providers/ClaudePlan.swift`**

```swift
import Foundation

public enum ClaudePlan {
    /// Mapuje `subscriptionType` z Keychainu na čitelný štítek. nil/"" → nil.
    public static func label(forSubscriptionType raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "max":        return "Max"
        case "pro":        return "Pro"
        case "free":       return "Free"
        case "team":       return "Team"
        case "enterprise": return "Enterprise"
        default:           return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }
}
```

- [ ] **Step 3: Fixtura `Tests/StatusBarKitTests/Fixtures/claude-api-usage.json`** (tvar reálné API odpovědi — top-level limits)

```
{"five_hour":{"utilization":13.0,"resets_at":"2026-06-24T10:09:59.738003+00:00"},"seven_day":{"utilization":8.0},"limits":[{"kind":"session","group":"session","percent":13,"severity":"normal","resets_at":"2026-06-24T10:09:59.738003+00:00","scope":null,"is_active":true},{"kind":"weekly_all","group":"weekly","percent":8,"severity":"normal","resets_at":"2026-06-30T11:59:59.738022+00:00","scope":null,"is_active":true},{"kind":"weekly_scoped","group":"weekly","percent":0,"severity":"normal","resets_at":"2026-06-30T12:00:00.461241+00:00","scope":{"model":{"display_name":"Sonnet"}},"is_active":true}],"spend":{}}
```

- [ ] **Step 4: Test `Tests/StatusBarKitTests/ClaudeUsageAPITests.swift`**

```swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func apiParserVytvoříOkna() throws {
    let url = Bundle.module.url(forResource: "claude-api-usage", withExtension: "json", subdirectory: "Fixtures")!
    let w = try ClaudeUsageCacheParser.parseAPIWindows(Data(contentsOf: url))
    #expect(w.count == 3)
    #expect(w.contains { $0.kind == .rolling5h && abs($0.usedFraction - 0.13) < 0.0001 })
    #expect(w.contains { $0.kind == .weekly(scope: nil) && abs($0.usedFraction - 0.08) < 0.0001 })
    #expect(w.contains { $0.kind == .weekly(scope: "Sonnet") })
}

@Test func plánLabelMapování() {
    #expect(ClaudePlan.label(forSubscriptionType: "max") == "Max")
    #expect(ClaudePlan.label(forSubscriptionType: "pro") == "Pro")
    #expect(ClaudePlan.label(forSubscriptionType: "free") == "Free")
    #expect(ClaudePlan.label(forSubscriptionType: nil) == nil)
    #expect(ClaudePlan.label(forSubscriptionType: "") == nil)
    #expect(ClaudePlan.label(forSubscriptionType: "custom") == "Custom")
}
```

- [ ] **Step 5: Run → GREEN.** `swift test --filter ClaudeUsageAPITests` → Expected: 2 PASS (parser je čistý refaktor + nový API parser; testy ověřují přímo finální stav). `swift test` → vše PASS (50 + 2 = 52). `swift build` čistý.
- [ ] **Step 6: Commit.**

```bash
git add Sources/StatusBarKit/Providers/ClaudeUsageCacheParser.swift Sources/StatusBarKit/Providers/ClaudePlan.swift Tests/StatusBarKitTests
git commit -m "feat: parser API usage odpovědi + ClaudePlan.label (čisté)"
```

**Verify success (Task 1):** `swift test` vše PASS; existující `ClaudeUsageCacheParserTests` (cache parser) dál zelené (refaktor zachoval chování). `swift build` čistý.
**On failure:** `old_string` nesedí → přečti reálný soubor, aplikuj princip (sdílené `windows(from:)`). ZASTAV.

---

### Task 2: `ClaudeUsageSource` protokol + integrace do `ClaudeCodeCollector`

**Files:**
- Create: `Sources/StatusBarKit/Providers/ClaudeUsageSource.swift`
- Modify: `Sources/StatusBarKit/Providers/ClaudeCodeCollector.swift`
- Modify: `Tests/StatusBarKitTests/ClaudeCodeCollectorTests.swift` (testy live + fallback)

**Interfaces:**
- Produces: `struct ClaudeLiveUsage { windows: [UsageWindow]; planLabel: String? }`; `protocol ClaudeUsageSource: Sendable { func fetchFresh() async -> ClaudeLiveUsage? }`; `ClaudeCodeCollector(cachePath:staleAfter:liveSource:)`.

- [ ] **Step 1: Create `Sources/StatusBarKit/Providers/ClaudeUsageSource.swift`**

```swift
import Foundation

public struct ClaudeLiveUsage: Sendable, Equatable {
    public let windows: [UsageWindow]
    public let planLabel: String?
    public init(windows: [UsageWindow], planLabel: String?) {
        self.windows = windows; self.planLabel = planLabel
    }
}

/// Zdroj ČERSTVÝCH Claude limitů (živé API). Implementace v app vrstvě; nil = nezdařilo se → fallback na cache.
public protocol ClaudeUsageSource: Sendable {
    func fetchFresh() async -> ClaudeLiveUsage?
}
```

- [ ] **Step 2: Modify `ClaudeCodeCollector.swift` — přidej `liveSource` + try-live-then-cache.** Nahraď CELÝ obsah souboru:

```swift
import Foundation

public struct ClaudeCodeCollector: UsageProvider {
    public let id: ProviderID = .claudeCode
    private let cachePath: URL
    private let staleAfter: TimeInterval
    private let liveSource: ClaudeUsageSource?

    public init(cachePath: URL? = nil, staleAfter: TimeInterval = 6 * 3600, liveSource: ClaudeUsageSource? = nil) {
        self.cachePath = cachePath ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.usage_cache.json")
        self.staleAfter = staleAfter
        self.liveSource = liveSource
    }

    public func fetch(includeToday: Bool) async -> ProviderUsage {
        let now = Date()
        let today = includeToday ? ClaudeTokenScanner().todayUsage(now: now) : nil

        // 1) Živé API (čerstvé limity + plán). Selhání → nil → fallback na cache.
        if let fresh = await liveSource?.fetchFresh() {
            return ProviderUsage(providerId: .claudeCode, displayName: "Claude Code",
                planLabel: fresh.planLabel, windows: fresh.windows, status: .ok,
                lastUpdated: now, today: today)
        }

        // 2) Fallback: lokální cache (stávající chování v0.1–v0.5).
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
                    lastUpdated: usage.lastUpdated, today: today)
            }
            return usage.with(today: today)
        } catch {
            return .unavailable(.claudeCode, displayName: "Claude Code",
                reason: "Cache nelze přečíst: \(error.localizedDescription)", now: now)
        }
    }
}
```

- [ ] **Step 3: Přidej testy do `ClaudeCodeCollectorTests.swift`** (na konec). Fake source:

```swift
private struct FakeClaudeSource: ClaudeUsageSource {
    let usage: ClaudeLiveUsage?
    func fetchFresh() async -> ClaudeLiveUsage? { usage }
}

@Test func collectorPoužijeŽivýZdroj() async {
    let fresh = ClaudeLiveUsage(
        windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.13, resetAt: nil)], planLabel: "Max")
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("none-\(UUID().uuidString).json")
    let u = await ClaudeCodeCollector(cachePath: missing, staleAfter: 999,
        liveSource: FakeClaudeSource(usage: fresh)).fetch(includeToday: false)
    #expect(u.status == .ok)                                  // živé, ne unavailable (i když cache chybí)
    #expect(u.planLabel == "Max")
    #expect(u.windows.first?.usedFraction == 0.13)
}

@Test func collectorFallbackNaCacheKdyžŽivýNil() async throws {
    let tmp = try copyFixtureToTemp()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let u = await ClaudeCodeCollector(cachePath: tmp, staleAfter: .greatestFiniteMagnitude,
        liveSource: FakeClaudeSource(usage: nil)).fetch(includeToday: false)
    #expect(u.status == .ok)                                  // fallback na cache
    #expect(u.windows.isEmpty == false)
}
```

- [ ] **Step 4: Run + build.** `swift test` → Expected: vše PASS (52 + 2 = 54; existující collector testy s default `liveSource: nil` dál zelené). `swift build` čistý.
- [ ] **Step 5: Commit.**

```bash
git add Sources/StatusBarKit/Providers/ClaudeUsageSource.swift Sources/StatusBarKit/Providers/ClaudeCodeCollector.swift Tests/StatusBarKitTests
git commit -m "feat: ClaudeUsageSource + collector zkusí živé limity, fallback na cache"
```

**Verify success (Task 2):** `swift test` vše PASS; live-success i fallback testy zelené.
**On failure:** ZASTAV, přečti reálný soubor.

---

### Task 3: `ClaudeKeychain` + `LiveClaudeUsageSource` (app) + wiring

**Files:**
- Create: `Sources/StatusBarApp/ClaudeKeychain.swift`
- Create: `Sources/StatusBarApp/LiveClaudeUsageSource.swift`
- Modify: `Sources/StatusBarApp/AppDelegate.swift` (injektovat live source)

**Interfaces:**
- Consumes: `ClaudeUsageSource`, `ClaudeUsageCacheParser.parseAPIWindows`, `ClaudePlan`.

- [ ] **Step 1: Create `Sources/StatusBarApp/ClaudeKeychain.swift`**

```swift
import Foundation
import Security

enum ClaudeKeychain {
    enum Result {
        case ok(accessToken: String, subscriptionType: String?)
        case userDenied    // ACL prompt zamítnut/zrušen → přestat otravovat (F-PROMPT)
        case unavailable   // item neexistuje / jiná chyba (neprompuje se)
    }
    /// Přečte Claude OAuth token + subscriptionType z Keychainu (service "Claude Code-credentials").
    /// Token se NIKDE neukládá ani neloguje.
    static func read() -> Result {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecUserCanceled || status == errSecAuthFailed { return .userDenied }
        guard status == errSecSuccess,
              let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return .unavailable }
        return .ok(accessToken: token, subscriptionType: oauth["subscriptionType"] as? String)
    }
}
```

- [ ] **Step 2: Create `Sources/StatusBarApp/LiveClaudeUsageSource.swift`**

```swift
import Foundation
import StatusBarKit

final class LiveClaudeUsageSource: ClaudeUsageSource, @unchecked Sendable {
    private let lock = NSLock()
    private var disabled = false   // po zamítnutí Keychain promptu přestaň otravovat (do restartu) — F-PROMPT

    func fetchFresh() async -> ClaudeLiveUsage? {
        if lock.withLock({ disabled }) { return nil }
        let token: String; let sub: String?
        switch ClaudeKeychain.read() {
        case .ok(let t, let s): token = t; sub = s
        case .userDenied: lock.withLock { disabled = true }; return nil   // už se neptat → fallback na cache
        case .unavailable: return nil                                     // fallback na cache
        }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.timeoutInterval = 10
        guard let pair = try? await URLSession.shared.data(for: req),
              (pair.1 as? HTTPURLResponse)?.statusCode == 200,
              let windows = try? ClaudeUsageCacheParser.parseAPIWindows(pair.0),
              !windows.isEmpty
        else { return nil }
        return ClaudeLiveUsage(windows: windows, planLabel: ClaudePlan.label(forSubscriptionType: sub))
    }
}
```

- [ ] **Step 3: Modify `AppDelegate.swift` — injektuj live source do Claude collectoru.**

Najdi přesně (`old_string`):
```swift
        coordinator = RefreshCoordinator(store: store, providers: [ClaudeCodeCollector(), CodexCollector()])
```
nahraď (`new_string`):
```swift
        coordinator = RefreshCoordinator(store: store, providers: [
            ClaudeCodeCollector(liveSource: LiveClaudeUsageSource()),
            CodexCollector(),
        ])
```

- [ ] **Step 4: Build + smoke.** `swift test` → 54/54 (žádný nový unit test — app-level Keychain/síť se ověří buildem+smoke). `swift build` čistý vč. app targetu (Security + URLSession). `./scripts/make-app.sh debug && open StatusBar.app` → app naběhne; při prvním refreshi macOS vyskočí s dotazem na Keychain „Claude Code-credentials" — **klikni „Always Allow"** (jinak by se ptal opakovaně) → karta Claude ukáže ČERSTVÁ % + plán „Max"; reset 5h okna budoucí čas. Když klikneš „Deny" → `LiveClaudeUsageSource` se vypne a app spadne zpět na cache („Data stará …"), bez dalšího ptaní. **Token se nikde nezaloguje.** Pozn.: ad-hoc podpis se mění při rebuildu, takže „Always Allow" se po `make-app.sh` může zeptat znovu (dev-build caveat; u podepsané app v `/Applications` přetrvá).
- [ ] **Step 5: Commit.**

```bash
git add Sources/StatusBarApp/ClaudeKeychain.swift Sources/StatusBarApp/LiveClaudeUsageSource.swift Sources/StatusBarApp/AppDelegate.swift
git commit -m "feat: LiveClaudeUsageSource (Keychain + usage API) + napojení do collectoru"
```

**Verify success (Task 3):** `swift build` čistý vč. app; `swift test` 54/54; app naběhne.
**On failure:** linker chyba `Security`/`URLSession` → na Apple platformách auto-link; jinak `old_string` nesedí → ZASTAV.

---

### Task 4: Cost fix — reálné vs. cache tokeny v „Dnes"

**Files:**
- Modify: `Sources/StatusBarKit/Models/TokenUsage.swift` (`realTokens`/`cacheTokens`)
- Modify: `Sources/StatusBarApp/PopoverView.swift` (zobrazení „Dnes")
- Modify: `Tests/StatusBarKitTests/TokenUsageTests.swift` (test)

**Interfaces:**
- Produces: `TokenUsage.realTokens: UInt` (input+output), `TokenUsage.cacheTokens: UInt` (cacheWrite+cacheRead).

- [ ] **Step 1: Modify `TokenUsage.swift` — přidej computed.**

Najdi přesně (`old_string`):
```swift
    public var totalTokens: UInt { input + output + cacheWrite + cacheRead }
```
nahraď (`new_string`):
```swift
    public var totalTokens: UInt { input + output + cacheWrite + cacheRead }
    public var realTokens: UInt { input + output }       // reálná práce (drahé)
    public var cacheTokens: UInt { cacheWrite + cacheRead }  // cache (levné, nafukuje total)
```

- [ ] **Step 2: Test do `TokenUsageTests.swift`** (na konec):

```swift
@Test func realACacheTokeny() {
    let t = TokenUsage(input: 10, output: 5, cacheWrite: 2, cacheRead: 100)
    #expect(t.realTokens == 15)
    #expect(t.cacheTokens == 102)
    #expect(t.totalTokens == 117)
}
```

- [ ] **Step 3: Modify `PopoverView.swift` — řádek „Dnes" ukáže reálné tok. + cache zvlášť.**

Najdi přesně (`old_string`):
```swift
                Text("\(TokenFormatter.compact(today.total.totalTokens)) tok. ≈ \(TokenFormatter.money(today.estimatedCost))")
                    .font(.caption).fontWeight(.medium)
```
nahraď (`new_string`):
```swift
                Text("\(TokenFormatter.compact(today.total.realTokens)) tok (+\(TokenFormatter.compact(today.total.cacheTokens)) cache) ≈ \(TokenFormatter.money(today.estimatedCost))")
                    .font(.caption).fontWeight(.medium)
```

A v rozpadu modelů najdi přesně (`old_string`):
```swift
                Text(today.perModel.map { "\(TokenFormatter.modelShortName($0.modelName)) \(TokenFormatter.compact($0.tokens.totalTokens))" }
                        .joined(separator: " · "))
```
nahraď (`new_string`):
```swift
                Text(today.perModel.map { "\(TokenFormatter.modelShortName($0.modelName)) \(TokenFormatter.compact($0.tokens.realTokens))" }
                        .joined(separator: " · "))
```

- [ ] **Step 4: Run + build + smoke.** `swift test` → vše PASS (54 + 1 = 55). `swift build` čistý. `./scripts/make-app.sh debug && open StatusBar.app` → „Dnes" ukáže např. „1.3M tok (+203M cache) ≈ $178" (reálná práce vs. cache jasně oddělené); rozpad „Opus … · Sonnet …" v reálných tokenech.
- [ ] **Step 5: Commit.**

```bash
git add Sources/StatusBarKit/Models/TokenUsage.swift Sources/StatusBarApp/PopoverView.swift Tests/StatusBarKitTests/TokenUsageTests.swift
git commit -m "fix: Dnes ukazuje reálné (input+output) tokeny + cache zvlášť"
```

**Verify success (Task 4):** `swift test` 55/55; app ukazuje rozdělené tokeny.

---

## Guardrails
- **Token NIKDY nelogovat/neukládat/neposílat jinam** — jen in-memory pro volání. Žádný `print` tokenu.
- Nezapínat login item; neměnit limit-parser cache cesty (jen refaktor sdílení); nepushovat (merge lokálně, push na souhlas).
- Stop: `old_string` nesedí → ZASTAV; existující testy padají → ZASTAV (regrese fallbacku).
- Kill criteria: pokud app target nekompiluje (Security/URLSession/concurrency) do 2 pokusů, NEBO app spadne při startu/refreshi → STOP, report. Pokud fallback na cache přestane fungovat (live=nil nevede na cache) → STOP (to je bezpečnostní síť).

## Rollback & Recovery
Aditivní na `feat/v0.6-live-usage-api`. Zahodit: `git checkout main && git branch -D feat/v0.6-live-usage-api`. Per-task `git revert`. Fallback na cache znamená, že i kdyby živé API zlobilo, app funguje jako v0.5.

## Audit Trail (plan-forge AUDIT, 2026-06-24)
- **Lenses 1–7.** Spike (HTTP 200 ověřeno) de-riskoval endpoint/hlavičky/tvar odpovědi/Keychain → assumptions většinou **verified**.
- **Security (lens 2, klíčové):** token jen in-memory, NIKDY nelogován (ověřeno: chybové cesty vrací nil bez tokenu; cache-catch užívá chybu cache souboru, ne API); HTTPS na pevný `api.anthropic.com`; čteme uživatelův vlastní token pro jeho vlastní data.
- **F-PROMPT (MED) → fixed:** Keychain read každých 60s by po „Deny"/jednorázovém „Allow" spamoval prompt. Fix: `ClaudeKeychain.Result.userDenied` + `LiveClaudeUsageSource` se po zamítnutí vypne (NSLock-guarded `disabled`); smoke radí „Always Allow".
- **Graceful degradace (lens 1):** jakékoli selhání (keychain unavailable/denied, token expiry/401, síť/timeout 10s, změna tvaru API → `!windows.isEmpty`) → `fetchFresh()` vrátí nil → collector použije cache. Nikdy pád.
- **Dependencies (lens 4):** Task 1 refaktor `ClaudeUsageCacheParser` zachová chování (sdílené `windows(from:)`); existující cache parser testy zelené. Task 2 `liveSource: nil` default → existující collector testy (vč. v0.5 gate) beze změny. `APIResponse{limits}` ignoruje extra top-level klíče (Decodable).
- **Decisions (autonomně, rozsah odsouhlasen):** live na každém refreshi (čerstvé limity v liště); token z Keychainu při každém volání (může se obnovit); plán z `subscriptionType`; cena beze změny (jen zobrazení); merge bez push.
- **Tabletop dry run:** T1 parser+plán (pure) → T2 protokol+collector(try live→cache) → T3 app keychain+net+wiring → T4 cost UI. Identifikátory konzistentní (`parseAPIWindows`, `ClaudeLiveUsage`, `liveSource`, `realTokens/cacheTokens`).
- **Verifikační gap:** reálný Keychain ACL prompt + fresh číslo = manuál uživatele (spike prokázal funkčnost path).

## Hotová definice v0.6
- Claude limity z živého API (čerstvá %, správný reset 5h okna), plán „Max" na kartě; při selhání fallback na cache (žádný pád, „Data stará …").
- „Dnes" ukazuje reálné (input+output) tokeny oddělené od cache; cena beze změny (správná).
- Jádro (API parser, plán, collector-fallback, realTokens) pokryté unit testy; Keychain/síť build+smoke; token nikde nelogován.

## Mimo v0.6 (další fáze)
- **v0.7:** OpenAI/Codex čerstvé limity (Admin klíč / jiný zdroj); přepínatelné styly lišty; refresh OAuth tokenu (kdyby Claude Code neběžel).
