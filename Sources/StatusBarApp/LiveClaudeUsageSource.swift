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
            if gate.shouldFetch(now: now, policy: policy) {
                gate.lastAttemptAt = now   // F3: optimistický claim — serializuje souběžné fetchFresh
                return (.fetch, lastGood)
            }
            return (.cached, lastGood)
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
            return (.success, ClaudeLiveUsage(windows: windows, planLabel: ClaudePlan.label(forSubscriptionType: sub), fetchedAt: Date()))
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
