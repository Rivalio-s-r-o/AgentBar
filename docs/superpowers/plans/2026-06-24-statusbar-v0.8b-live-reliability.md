# StatusBar v0.8b — Spolehlivá živá data + refresh OAuth tokenu — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Živé usage zdroje přestanou přetěžovat API (throttle 5 min + backoff 15 min po 429) a drží poslední dobrý snapshot (žádné „Data stará X min"); při 401 obnoví OAuth token a bezpečně ho zapíšou zpět do credential store.

**Architecture:** Riziková logika (throttle rozhodování + mutace credential blobu) je v `StatusBarKit` jako pure, unit-testované funkce. Síť, Keychain a souborové I/O zůstávají v `StatusBarApp`. Throttle/refresh stav drží app live-source třídy (NSLock); protokoly a payload typy se nemění → existující testy netknuté.

**Tech Stack:** Swift 6 (strict concurrency), SwiftPM (`StatusBarKit` + `StatusBarApp`), Security/URLSession (App), Swift Testing.

## Global Constraints

- Swift 6 strict concurrency. `StatusBarKit` zůstává pure — žádný `import AppKit`/`SwiftUI`/`Security`/`URLSession`/zápis na disk. `JSONSerialization` (čistá transformace `Data`→`Data`) je v Kitu OK.
- **Throttle hodnoty:** `LiveUsagePolicy` default `minInterval = 300` (5 min), `cooldown = 900` (15 min po 429).
- **Refresh je REAKTIVNÍ** (jen na HTTP 401). Endpoint Claude `POST https://platform.claude.com/v1/oauth/token` (JSON, `anthropic-beta:oauth-2025-04-20`, `{grant_type:"refresh_token", refresh_token, client_id:"9d1c250a-e61b-44d9-88ed-5944d1962f5e"}`). Codex `POST https://auth.openai.com/oauth/token` (form, `grant_type=refresh_token&client_id=app_EMoamEEZ73f0CkXaXp7hrann&refresh_token=…`).
- **Bezpečnost zápisu:** mutace blobu mění JEN tokenová pole, ostatní zachová; před zápisem **round-trip validace** (parse zpět, ověř nový token); zápis JEN při úspěšném refreshi; auth.json atomicky (temp+replace), Keychain `SecItemUpdate`. Tokeny (access/refresh) se NIKDY nelogují/neposílají jinam.
- **Protokoly/payloady se NEMĚNÍ** (`ClaudeUsageSource`/`CodexUsageSource`/`ClaudeLiveUsage`/`CodexSnapshot`) → existující testy a fake sources netknuté.
- **Graceful degradace:** refresh nebo zápis selže → `.failed` → vrať lastGood/nil → fallback na file cache. Nikdy pád, nikdy poškození credentials.
- **Testy jsou volné `@Test func` bez `@Suite`/typu:** ověřuj VŽDY plným `swift test`, NIKDY `swift test --filter <NázevSouboru>`.
- **App smoke:** agentova brána = `swift build && swift test` + `swift build -c release && bash scripts/make-app.sh` (exit 0). Agent NESMÍ spouštět výslednou `.app`.
- České názvy testů s diakritikou. Bundle verze → `0.8.0`. TDD, časté commity, DRY, YAGNI.

## Guardrails
- **Zakázané:** logovat token (access/refresh); zapsat do credential store bez úspěšného refreshe NEBO bez round-trip validace; měnit jiná než tokenová pole blobu; měnit `last_refresh` (záměrně ponecháno); měnit protokoly/payload typy.
- ⚠ **Nevratná/riziková operace:** zápis do Keychainu (`SecItemUpdate`) a `~/.codex/auth.json` — gated: jen po úspěšném refreshi + round-trip validaci + (auth.json) atomickém zápisu.
- **Stop podmínky:** selže-li krok, postupuj dle „On failure"; nikdy neimprovizuj jiný endpoint/formát blobu.
- **Kill criterion:** když Kit testy (Task 1/2) nejdou zezelenat po 2 pokusech, NEBO round-trip validace mutace nejde zprovoznit → ZASTAV a nahlas (NEzapisuj do credentials bez funkční validace).

---

### Task 1: Kit — throttle/backoff policy (`LiveGateState`)

**Files:**
- Create: `Sources/StatusBarKit/Providers/LiveUsageGate.swift`
- Create (test): `Tests/StatusBarKitTests/LiveUsageGateTests.swift`

**Interfaces:**
- Produces: `LiveUsagePolicy {minInterval, cooldown}`, `LiveFetchSignal {success, rateLimited, failed}`, `LiveGateState {lastAttemptAt, cooldownUntil; shouldFetch(now:policy:); after(signal:now:policy:)}`.

- [ ] **Step 1: Napiš testy `LiveUsageGateTests.swift`**

Create `Tests/StatusBarKitTests/LiveUsageGateTests.swift`:

```swift
import Testing
import Foundation
@testable import StatusBarKit

private let p = LiveUsagePolicy()   // 300 / 900
private let t0 = Date(timeIntervalSince1970: 1_000_000)

@Test func gateIniciálněPovolí() {
    #expect(LiveGateState().shouldFetch(now: t0, policy: p) == true)
}

@Test func gatePoÚspěchuThrottluje() {
    let s = LiveGateState().after(signal: .success, now: t0, policy: p)
    #expect(s.shouldFetch(now: t0.addingTimeInterval(299), policy: p) == false)  // v rámci minInterval
    #expect(s.shouldFetch(now: t0.addingTimeInterval(300), policy: p) == true)   // přesně minInterval → povolí
    #expect(s.cooldownUntil == nil)
}

@Test func gatePo429Backoff() {
    let s = LiveGateState().after(signal: .rateLimited, now: t0, policy: p)
    #expect(s.cooldownUntil == t0.addingTimeInterval(900))
    #expect(s.shouldFetch(now: t0.addingTimeInterval(500), policy: p) == false)  // v cooldownu
    #expect(s.shouldFetch(now: t0.addingTimeInterval(900), policy: p) == true)   // cooldown vypršel + >minInterval
}

@Test func gatePoFailedJenThrottle() {
    let s = LiveGateState().after(signal: .failed, now: t0, policy: p)
    #expect(s.cooldownUntil == nil)
    #expect(s.shouldFetch(now: t0.addingTimeInterval(100), policy: p) == false)  // jen throttle
    #expect(s.shouldFetch(now: t0.addingTimeInterval(301), policy: p) == true)
}

@Test func gateÚspěchPo429ZrušíCooldown() {
    let s1 = LiveGateState().after(signal: .rateLimited, now: t0, policy: p)
    let s2 = s1.after(signal: .success, now: t0.addingTimeInterval(900), policy: p)
    #expect(s2.cooldownUntil == nil)
}

@Test func politikaVlastníHodnoty() {
    let custom = LiveUsagePolicy(minInterval: 60, cooldown: 120)
    let s = LiveGateState().after(signal: .rateLimited, now: t0, policy: custom)
    #expect(s.cooldownUntil == t0.addingTimeInterval(120))
}
```

- [ ] **Step 2: Spusť testy — selžou (typy neexistují)**

Run: `swift test`
Expected: FAIL — kompilace: `cannot find 'LiveGateState' in scope`. (Pozn. F1: NEpoužívej `--filter`.)

- [ ] **Step 3: Napiš `LiveUsageGate.swift`**

Create `Sources/StatusBarKit/Providers/LiveUsageGate.swift`:

```swift
import Foundation

/// Konfigurace throttlingu živého usage zdroje.
public struct LiveUsagePolicy: Sendable, Equatable {
    public let minInterval: TimeInterval   // min. čas mezi síťovými pokusy (default 5 min)
    public let cooldown: TimeInterval      // backoff po HTTP 429 (default 15 min)
    public init(minInterval: TimeInterval = 300, cooldown: TimeInterval = 900) {
        self.minInterval = minInterval; self.cooldown = cooldown
    }
}

/// Výsledek síťového pokusu o živá data.
public enum LiveFetchSignal: Sendable, Equatable { case success, rateLimited, failed }

/// Stavový automat throttle/backoff (pure, testovatelný s injektovaným `now`).
public struct LiveGateState: Sendable, Equatable {
    public var lastAttemptAt: Date?
    public var cooldownUntil: Date?
    public init(lastAttemptAt: Date? = nil, cooldownUntil: Date? = nil) {
        self.lastAttemptAt = lastAttemptAt; self.cooldownUntil = cooldownUntil
    }
    /// Smí se teď sáhnout na síť? false během cooldownu nebo do `minInterval` od posledního pokusu.
    public func shouldFetch(now: Date, policy: LiveUsagePolicy) -> Bool {
        if let cd = cooldownUntil, now < cd { return false }
        if let last = lastAttemptAt, now.timeIntervalSince(last) < policy.minInterval { return false }
        return true
    }
    /// Nový stav po síťovém pokusu. `.rateLimited` nastaví cooldown, jinak ho zruší.
    public func after(signal: LiveFetchSignal, now: Date, policy: LiveUsagePolicy) -> LiveGateState {
        var s = self
        s.lastAttemptAt = now
        switch signal {
        case .rateLimited: s.cooldownUntil = now.addingTimeInterval(policy.cooldown)
        case .success, .failed: s.cooldownUntil = nil
        }
        return s
    }
}
```

- [ ] **Step 4: Spusť testy — projdou**

Run: `swift test`
Expected: PASS (6 nových testů zelených).

- [ ] **Step 5: Build + commit**

Run: `swift build`
Expected: Build complete, 0 warnings.

```bash
git add Sources/StatusBarKit/Providers/LiveUsageGate.swift Tests/StatusBarKitTests/LiveUsageGateTests.swift
git commit -m "feat: LiveGateState throttle/backoff policy (pure, testovatelná)"
```

---

### Task 2: Kit — refresh parse + credential mutace (pure)

**Files:**
- Create: `Sources/StatusBarKit/Providers/CredentialUpdate.swift`
- Create (test): `Tests/StatusBarKitTests/CredentialUpdateTests.swift`

**Interfaces:**
- Produces:
  - `ClaudeRefreshParse.parse(_ data: Data) -> (accessToken: String, expiresInSeconds: Double, refreshToken: String?)?`
  - `ClaudeCredentialUpdate.updatedBlob(original: Data, accessToken: String, expiresAtMillis: Double, refreshToken: String?) -> Data?`
  - `CodexRefreshParse.parse(_ data: Data) -> (accessToken: String, refreshToken: String?)?`
  - `CodexAuthUpdate.updatedAuthJSON(original: Data, accessToken: String, refreshToken: String?) -> Data?`

- [ ] **Step 1: Napiš testy `CredentialUpdateTests.swift`**

Create `Tests/StatusBarKitTests/CredentialUpdateTests.swift`:

```swift
import Testing
import Foundation
@testable import StatusBarKit

// --- Claude refresh response parse ---
@Test func claudeRefreshParseÚplný() {
    let d = Data(#"{"access_token":"newA","expires_in":3600,"refresh_token":"newR"}"#.utf8)
    let r = ClaudeRefreshParse.parse(d)
    #expect(r?.accessToken == "newA")
    #expect(r?.expiresInSeconds == 3600)
    #expect(r?.refreshToken == "newR")
}
@Test func claudeRefreshParseBezRefresh() {
    let r = ClaudeRefreshParse.parse(Data(#"{"access_token":"a","expires_in":60}"#.utf8))
    #expect(r?.refreshToken == nil)
    #expect(r?.accessToken == "a")
}
@Test func claudeRefreshParseNevalidníNil() {
    #expect(ClaudeRefreshParse.parse(Data("nonsense".utf8)) == nil)
    #expect(ClaudeRefreshParse.parse(Data(#"{"expires_in":60}"#.utf8)) == nil)  // chybí access_token
}

// --- Claude Keychain blob mutace ---
private let claudeBlob = Data(#"""
{"mcpOAuth":{"srv":"x"},"claudeAiOauth":{"accessToken":"oldA","refreshToken":"oldR","expiresAt":111,"subscriptionType":"max","scopes":["openid"],"clientId":"cid"}}
"""#.utf8)

@Test func claudeBlobMutaceZachováOstatní() throws {
    let out = ClaudeCredentialUpdate.updatedBlob(original: claudeBlob, accessToken: "newA", expiresAtMillis: 999, refreshToken: "newR")
    let json = try JSONSerialization.jsonObject(with: #require(out)) as! [String: Any]
    let oauth = json["claudeAiOauth"] as! [String: Any]
    #expect(oauth["accessToken"] as? String == "newA")
    #expect((oauth["expiresAt"] as? Double) == 999)
    #expect(oauth["refreshToken"] as? String == "newR")
    #expect(oauth["subscriptionType"] as? String == "max")          // zachováno
    #expect(oauth["clientId"] as? String == "cid")                  // zachováno
    #expect((json["mcpOAuth"] as? [String: Any])?["srv"] as? String == "x")  // zachováno
}
@Test func claudeBlobMutaceRefreshNilPonecháStarý() throws {
    let out = ClaudeCredentialUpdate.updatedBlob(original: claudeBlob, accessToken: "newA", expiresAtMillis: 5, refreshToken: nil)
    let oauth = (try JSONSerialization.jsonObject(with: #require(out)) as! [String: Any])["claudeAiOauth"] as! [String: Any]
    #expect(oauth["refreshToken"] as? String == "oldR")             // ponecháno
    #expect(oauth["accessToken"] as? String == "newA")
}
@Test func claudeBlobMutaceCizíStrukturaNil() {
    #expect(ClaudeCredentialUpdate.updatedBlob(original: Data(#"{"foo":1}"#.utf8), accessToken: "x", expiresAtMillis: 1, refreshToken: nil) == nil)
}

// --- Codex refresh response parse ---
@Test func codexRefreshParseÚplný() {
    let r = CodexRefreshParse.parse(Data(#"{"access_token":"a","token_type":"Bearer","expires_in":3600,"refresh_token":"r"}"#.utf8))
    #expect(r?.accessToken == "a")
    #expect(r?.refreshToken == "r")
}
@Test func codexRefreshParseNevalidníNil() {
    #expect(CodexRefreshParse.parse(Data(#"{"token_type":"Bearer"}"#.utf8)) == nil)
}

// --- Codex auth.json mutace ---
private let codexAuth = Data(#"""
{"auth_mode":"chatgpt","tokens":{"access_token":"oldA","refresh_token":"oldR","account_id":"acc","id_token":"idt"},"last_refresh":"2026-01-01T00:00:00Z"}
"""#.utf8)

@Test func codexAuthMutaceZachováOstatní() throws {
    let out = CodexAuthUpdate.updatedAuthJSON(original: codexAuth, accessToken: "newA", refreshToken: nil)
    let json = try JSONSerialization.jsonObject(with: #require(out)) as! [String: Any]
    let tokens = json["tokens"] as! [String: Any]
    #expect(tokens["access_token"] as? String == "newA")
    #expect(tokens["refresh_token"] as? String == "oldR")           // nil → ponecháno
    #expect(tokens["account_id"] as? String == "acc")               // zachováno
    #expect(tokens["id_token"] as? String == "idt")                 // zachováno
    #expect(json["auth_mode"] as? String == "chatgpt")              // zachováno
    #expect(json["last_refresh"] as? String == "2026-01-01T00:00:00Z")  // ZÁMĚRNĚ nezměněno
}
@Test func codexAuthMutaceRefreshRotace() throws {
    let out = CodexAuthUpdate.updatedAuthJSON(original: codexAuth, accessToken: "newA", refreshToken: "newR")
    let tokens = (try JSONSerialization.jsonObject(with: #require(out)) as! [String: Any])["tokens"] as! [String: Any]
    #expect(tokens["refresh_token"] as? String == "newR")
}
@Test func codexAuthMutaceCizíStrukturaNil() {
    #expect(CodexAuthUpdate.updatedAuthJSON(original: Data(#"{"foo":1}"#.utf8), accessToken: "x", refreshToken: nil) == nil)
}
```

- [ ] **Step 2: Spusť testy — selžou (typy neexistují)**

Run: `swift test`
Expected: FAIL — kompilace `cannot find 'ClaudeRefreshParse' in scope`.

- [ ] **Step 3: Napiš `CredentialUpdate.swift`**

Create `Sources/StatusBarKit/Providers/CredentialUpdate.swift`:

```swift
import Foundation

/// Parse Claude refresh-token odpovědi (`{access_token, expires_in, refresh_token?}`).
public enum ClaudeRefreshParse {
    public static func parse(_ data: Data) -> (accessToken: String, expiresInSeconds: Double, refreshToken: String?)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String, !token.isEmpty,
              let expires = json["expires_in"] as? Double else { return nil }
        return (token, expires, json["refresh_token"] as? String)
    }
}

/// Mutace Claude Keychain blobu: změní jen `claudeAiOauth.accessToken/expiresAt/refreshToken`, ostatní zachová.
public enum ClaudeCredentialUpdate {
    public static func updatedBlob(original: Data, accessToken: String, expiresAtMillis: Double, refreshToken: String?) -> Data? {
        guard var json = try? JSONSerialization.jsonObject(with: original) as? [String: Any],
              var oauth = json["claudeAiOauth"] as? [String: Any] else { return nil }
        oauth["accessToken"] = accessToken
        oauth["expiresAt"] = expiresAtMillis
        if let rt = refreshToken { oauth["refreshToken"] = rt }
        json["claudeAiOauth"] = oauth
        return try? JSONSerialization.data(withJSONObject: json)
    }
}

/// Parse Codex refresh-token odpovědi (`{access_token, token_type, expires_in, refresh_token?}`).
public enum CodexRefreshParse {
    public static func parse(_ data: Data) -> (accessToken: String, refreshToken: String?)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String, !token.isEmpty else { return nil }
        return (token, json["refresh_token"] as? String)
    }
}

/// Mutace `~/.codex/auth.json`: změní jen `tokens.access_token` (+ `refresh_token` když dán), ostatní vč. `last_refresh` zachová.
public enum CodexAuthUpdate {
    public static func updatedAuthJSON(original: Data, accessToken: String, refreshToken: String?) -> Data? {
        guard var json = try? JSONSerialization.jsonObject(with: original) as? [String: Any],
              var tokens = json["tokens"] as? [String: Any] else { return nil }
        tokens["access_token"] = accessToken
        if let rt = refreshToken { tokens["refresh_token"] = rt }
        json["tokens"] = tokens
        return try? JSONSerialization.data(withJSONObject: json)
    }
}
```

- [ ] **Step 4: Spusť testy — projdou**

Run: `swift test`
Expected: PASS (11 nových testů zelených).

- [ ] **Step 5: Build + commit**

Run: `swift build`
Expected: Build complete, 0 warnings.

```bash
git add Sources/StatusBarKit/Providers/CredentialUpdate.swift Tests/StatusBarKitTests/CredentialUpdateTests.swift
git commit -m "feat: Kit refresh parse + credential blob mutace (pure, zachovávají strukturu)"
```

---

### Task 3: App — `LiveClaudeUsageSource` throttle + refresh-on-401 + Keychain write-back

**Files:**
- Modify: `Sources/StatusBarApp/ClaudeKeychain.swift`
- Modify: `Sources/StatusBarApp/LiveClaudeUsageSource.swift`

**Interfaces:**
- Consumes: `LiveGateState`/`LiveUsagePolicy`/`LiveFetchSignal`, `ClaudeRefreshParse`, `ClaudeCredentialUpdate`, `ClaudeLiveUsage`, `ClaudeUsageCacheParser.parseAPIWindows`, `ClaudePlan`.
- Produces: `ClaudeKeychain.Result.ok(accessToken, refreshToken, subscriptionType)`, `ClaudeKeychain.currentBlob() -> Data?`, `ClaudeKeychain.update(blob: Data) -> Bool`.

> **Pozn.:** App vrstva nemá unit testy. Ověření = `swift build && swift test` (Kit zelený) + smoke. Token (access/refresh) NIKDE nelogovat.

- [ ] **Step 1: Rozšiř `ClaudeKeychain.swift`**

Nahraď obsah `Sources/StatusBarApp/ClaudeKeychain.swift`:

```swift
import Foundation
import Security

enum ClaudeKeychain {
    enum Result {
        case ok(accessToken: String, refreshToken: String?, subscriptionType: String?)
        case userDenied
        case unavailable
    }
    private static let service = "Claude Code-credentials"
    private static func query(returnData: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if returnData { q[kSecReturnData as String] = true }
        return q
    }

    static func read() -> Result {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query(returnData: true) as CFDictionary, &item)
        if status == errSecUserCanceled || status == errSecAuthFailed { return .userDenied }
        guard status == errSecSuccess,
              let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return .unavailable }
        return .ok(accessToken: token,
                   refreshToken: oauth["refreshToken"] as? String,
                   subscriptionType: oauth["subscriptionType"] as? String)
    }

    /// Surový blob (pro mutaci při refreshi). nil = nedostupné.
    static func currentBlob() -> Data? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query(returnData: true) as CFDictionary, &item)
        return status == errSecSuccess ? (item as? Data) : nil
    }

    /// Přepíše hodnotu existující položky novým blobem. true = úspěch.
    static func update(blob: Data) -> Bool {
        let attrs: [String: Any] = [kSecValueData as String: blob]
        return SecItemUpdate(query(returnData: false) as CFDictionary, attrs as CFDictionary) == errSecSuccess
    }
}
```

- [ ] **Step 2: Přepiš `LiveClaudeUsageSource.swift` (throttle + refresh-on-401 + write-back)**

Nahraď obsah `Sources/StatusBarApp/LiveClaudeUsageSource.swift`:

```swift
import Foundation
import StatusBarKit

final class LiveClaudeUsageSource: ClaudeUsageSource, @unchecked Sendable {
    private let lock = NSLock()
    private var disabled = false          // F-PROMPT: po Keychain "Deny"
    private var gate = LiveGateState()
    private var lastGood: ClaudeLiveUsage?
    private let policy = LiveUsagePolicy()

    private enum Decision { case disabled, cached, fetch }

    func fetchFresh() async -> ClaudeLiveUsage? {
        let now = Date()
        let (decision, cached): (Decision, ClaudeLiveUsage?) = lock.withLock {
            if disabled { return (.disabled, nil) }
            return (gate.shouldFetch(now: now, policy: policy) ? .fetch : .cached, lastGood)
        }
        switch decision {
        case .disabled: return nil
        case .cached:   return cached                       // throttle/backoff → last-good
        case .fetch:    break
        }
        let (signal, snapshot) = await doNetwork()
        lock.withLock {
            gate = gate.after(signal: signal, now: now, policy: policy)
            if let s = snapshot { lastGood = s }
        }
        return snapshot ?? cached
    }

    // MARK: - síť (token jen in-memory, NIKDY nelogován)

    private func doNetwork() async -> (LiveFetchSignal, ClaudeLiveUsage?) {
        let token: String; let refresh: String?; let sub: String?
        switch ClaudeKeychain.read() {
        case .ok(let t, let r, let s): token = t; refresh = r; sub = s
        case .userDenied: lock.withLock { disabled = true }; return (.failed, nil)
        case .unavailable: return (.failed, nil)
        }

        var (status, body) = await usageCall(token: token)
        if status == 401, let refresh, let newToken = await refreshAndStore(refreshToken: refresh) {
            (status, body) = await usageCall(token: newToken)
        }
        switch status {
        case 200:
            guard let body, let windows = try? ClaudeUsageCacheParser.parseAPIWindows(body), !windows.isEmpty
            else { return (.failed, nil) }
            return (.success, ClaudeLiveUsage(windows: windows, planLabel: ClaudePlan.label(forSubscriptionType: sub)))
        case 429: return (.rateLimited, nil)
        default:  return (.failed, nil)
        }
    }

    private func usageCall(token: String) async -> (Int, Data?) {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.timeoutInterval = 10
        guard let pair = try? await URLSession.shared.data(for: req),
              let http = pair.1 as? HTTPURLResponse else { return (0, nil) }
        return (http.statusCode, pair.0)
    }

    /// Obnoví token, bezpečně zapíše zpět do Keychainu. Vrátí nový access token, nebo nil (→ žádný zápis).
    private func refreshAndStore(refreshToken: String) async -> String? {
        var req = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        ])
        req.timeoutInterval = 10
        guard let pair = try? await URLSession.shared.data(for: req),
              (pair.1 as? HTTPURLResponse)?.statusCode == 200,
              let parsed = ClaudeRefreshParse.parse(pair.0),
              let original = ClaudeKeychain.currentBlob() else { return nil }
        let expiresAtMillis = Date().timeIntervalSince1970 * 1000 + parsed.expiresInSeconds * 1000
        guard let newBlob = ClaudeCredentialUpdate.updatedBlob(
                original: original, accessToken: parsed.accessToken,
                expiresAtMillis: expiresAtMillis, refreshToken: parsed.refreshToken),
              roundTripValid(newBlob, expectedAccessToken: parsed.accessToken),
              ClaudeKeychain.update(blob: newBlob) else { return nil }
        return parsed.accessToken
    }

    /// Round-trip: nový blob musí jít znovu naparsovat a obsahovat očekávaný token.
    private func roundTripValid(_ blob: Data, expectedAccessToken: String) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: blob) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              oauth["accessToken"] as? String == expectedAccessToken else { return false }
        return true
    }
}
```

- [ ] **Step 3: Build + test (Kit beze změny, App kompiluje)**

Run: `swift build && swift test`
Expected: Build complete (0 warnings); všechny testy PASS (Kit netknuté, žádný nový App unit test).

- [ ] **Step 4: Commit**

```bash
git add Sources/StatusBarApp/ClaudeKeychain.swift Sources/StatusBarApp/LiveClaudeUsageSource.swift
git commit -m "feat: LiveClaudeUsageSource throttle/backoff/last-good + refresh-on-401 + Keychain write-back"
```

---

### Task 4: App — `LiveCodexUsageSource` (struct→class) throttle + refresh + auth.json write-back

**Files:**
- Modify: `Sources/StatusBarApp/CodexAuth.swift`
- Modify: `Sources/StatusBarApp/LiveCodexUsageSource.swift`

**Interfaces:**
- Consumes: `LiveGateState`/`LiveUsagePolicy`/`LiveFetchSignal`, `CodexRefreshParse`, `CodexAuthUpdate`, `CodexUsageAPIParser`, `CodexSnapshot`.
- Produces: `CodexAuth.read() -> (accessToken, accountId, refreshToken)?`, `CodexAuth.currentJSON() -> Data?`, `CodexAuth.write(authJSON: Data) -> Bool`.

> **Pozn.:** App vrstva, ověření = build+smoke. Token NIKDE nelogovat.

- [ ] **Step 1: Rozšiř `CodexAuth.swift`**

Nahraď obsah `Sources/StatusBarApp/CodexAuth.swift`:

```swift
import Foundation

/// Čte/zapisuje ~/.codex/auth.json (ChatGPT OAuth). Tokeny se NIKDE nelogují.
enum CodexAuth {
    private static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
    }

    static func read() -> (accessToken: String, accountId: String, refreshToken: String?)? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String, !token.isEmpty,
              let account = tokens["account_id"] as? String, !account.isEmpty
        else { return nil }
        return (token, account, tokens["refresh_token"] as? String)
    }

    /// Surový obsah auth.json (pro mutaci). nil = nedostupné.
    static func currentJSON() -> Data? { try? Data(contentsOf: url) }

    /// Atomicky přepíše auth.json (temp soubor + replace). true = úspěch.
    static func write(authJSON: Data) -> Bool {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".auth.json.tmp-\(UUID().uuidString)")
        do {
            try authJSON.write(to: tmp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
    }
}
```

- [ ] **Step 2: Přepiš `LiveCodexUsageSource.swift` (struct→class, throttle + refresh + write-back)**

Nahraď obsah `Sources/StatusBarApp/LiveCodexUsageSource.swift`:

```swift
import Foundation
import StatusBarKit

/// Živý zdroj Codex limitů s throttle/backoff/last-good + refresh-on-401 + zápis do ~/.codex/auth.json.
final class LiveCodexUsageSource: CodexUsageSource, @unchecked Sendable {
    private let lock = NSLock()
    private var gate = LiveGateState()
    private var lastGood: CodexSnapshot?
    private let policy = LiveUsagePolicy()

    func fetchFresh() async -> CodexSnapshot? {
        let now = Date()
        let (doFetch, cached): (Bool, CodexSnapshot?) = lock.withLock {
            (gate.shouldFetch(now: now, policy: policy), lastGood)
        }
        if !doFetch { return cached }

        let (signal, snapshot) = await doNetwork()
        lock.withLock {
            gate = gate.after(signal: signal, now: now, policy: policy)
            if let s = snapshot { lastGood = s }
        }
        return snapshot ?? cached
    }

    private func doNetwork() async -> (LiveFetchSignal, CodexSnapshot?) {
        guard let auth = CodexAuth.read() else { return (.failed, nil) }
        var (status, body) = await usageCall(token: auth.accessToken, accountId: auth.accountId)
        if status == 401, let refresh = auth.refreshToken, let newToken = await refreshAndStore(refreshToken: refresh) {
            (status, body) = await usageCall(token: newToken, accountId: auth.accountId)
        }
        switch status {
        case 200:
            guard let body, let snap = CodexUsageAPIParser.parse(body), !snap.windows.isEmpty
            else { return (.failed, nil) }
            return (.success, snap)
        case 429: return (.rateLimited, nil)
        default:  return (.failed, nil)
        }
    }

    private func usageCall(token: String, accountId: String) async -> (Int, Data?) {
        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(accountId, forHTTPHeaderField: "chatgpt-account-id")
        req.setValue("codex_cli_rs/0.135.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        guard let pair = try? await URLSession.shared.data(for: req),
              let http = pair.1 as? HTTPURLResponse else { return (0, nil) }
        return (http.statusCode, pair.0)
    }

    private func refreshAndStore(refreshToken: String) async -> String? {
        var req = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = "grant_type=refresh_token&client_id=app_EMoamEEZ73f0CkXaXp7hrann&refresh_token=\(refreshToken)"
        req.httpBody = form.data(using: .utf8)
        req.timeoutInterval = 10
        guard let pair = try? await URLSession.shared.data(for: req),
              (pair.1 as? HTTPURLResponse)?.statusCode == 200,
              let parsed = CodexRefreshParse.parse(pair.0),
              let original = CodexAuth.currentJSON(),
              let newJSON = CodexAuthUpdate.updatedAuthJSON(original: original, accessToken: parsed.accessToken, refreshToken: parsed.refreshToken),
              roundTripValid(newJSON, expectedAccessToken: parsed.accessToken),
              CodexAuth.write(authJSON: newJSON) else { return nil }
        return parsed.accessToken
    }

    private func roundTripValid(_ json: Data, expectedAccessToken: String) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let tokens = obj["tokens"] as? [String: Any],
              tokens["access_token"] as? String == expectedAccessToken else { return false }
        return true
    }
}
```

- [ ] **Step 3: Build + test**

Run: `swift build && swift test`
Expected: Build complete (0 warnings); všechny testy PASS. (`LiveCodexUsageSource()` v `AppDelegate` stále kompiluje — bezparametrový init zachován.)

- [ ] **Step 4: Commit**

```bash
git add Sources/StatusBarApp/CodexAuth.swift Sources/StatusBarApp/LiveCodexUsageSource.swift
git commit -m "feat: LiveCodexUsageSource (class) throttle/backoff/last-good + refresh-on-401 + auth.json write-back"
```

---

### Task 5: Verze 0.8.0 + finální build/smoke

**Files:**
- Modify: `Resources/Info.plist`

- [ ] **Step 1: Bump verze**

V `Resources/Info.plist` změň obě pole na `0.8.0`:

```xml
  <key>CFBundleVersion</key><string>0.8.0</string>
  <key>CFBundleShortVersionString</key><string>0.8.0</string>
```

- [ ] **Step 2: Ověř build + test**

Run: `swift build && swift test`
Expected: Build complete (0 warnings); všechny testy PASS (existující + 17 nových Kit testů).

- [ ] **Step 3: Postav `.app` (NEspouštět GUI)**

Run: `swift build -c release && bash scripts/make-app.sh`
Expected: exit 0, vyrobí `StatusBar.app`. **Agent NESMÍ spouštět `.app`.** Nahlas cestu.
On failure: nahlas výstup a ZASTAV.

- [ ] **Step 4: Commit**

```bash
git add Resources/Info.plist
git commit -m "chore: verze bundlu 0.8.0"
```

---

## Verifikace (po všech taskách)
- `swift build` (debug+release) čistý (Kit+App), `swift test` zelený (existující + 17 nových Kit testů: 6 gate + 11 credential).
- Throttle (5 min) + 429 backoff (15 min) + last-good cache: žádné „Data stará X min" při běžném provozu (živý zdroj drží snapshot).
- Refresh-on-401 + bezpečný write-back (Kit mutace + round-trip + atomicky/SecItemUpdate).
- GAP (ověří uživatel/runtime): zmizení „Data stará X min" v liště; reálný refresh nastane až token vyprší a Claude Code/Codex neběží.

## Rollback & Recovery
Kód aditivní/nahrazující (žádná migrace dat). Rollback = `git revert`/`git checkout main -- <soubory>`. Write-back do credentials je jištěn round-trip validací; při pochybnosti uživatel re-login do Claude Code/Codex obnoví credentials (idempotentní).

## Risk Register
| ID | Severity | Likelihood | Risk | Mitigace (krok) | Resolution |
|----|----------|------------|------|-----------------|------------|
| R1 | MED | L | zápis poškodí credential store → odhlášení | Kit mutace zachovává strukturu (T2, testy) + round-trip validace (T3/T4) + zápis jen po úspěšném refreshi + atomicky/SecItemUpdate | mitigated |
| R2 | MED | M | refresh endpoint nefunguje jak odhadnuto (hlavičky/formát) | graceful degradace → fallback (neškodné); caveat (ne live-testováno) | accepted |
| R3 | LOW | L | throttle 5 min stále nad limitem → reziduální 429 | backoff 15 min to pohltí, last-good | mitigated |
| R4 | LOW | L | concurrency souběžné fetchFresh | NSLock; 60s timer = sekvenční | mitigated |
| R5 | LOW | L | token rotace | nový refresh_token zapsán zpět (jeden zdroj pravdy) | mitigated |

## Audit Trail (doplní plan-forge)
