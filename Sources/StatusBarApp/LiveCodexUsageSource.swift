import Foundation
import StatusBarKit

/// Živý zdroj Codex limitů s throttle/backoff/last-good + refresh-on-401 + zápis do ~/.codex/auth.json.
final class LiveCodexUsageSource: CodexUsageSource, @unchecked Sendable {
    private let lock = NSLock()
    private var gate = LiveGateState()
    private var lastGood: CodexLiveUsage?
    private let policy = LiveUsagePolicy()

    func fetchFresh() async -> CodexLiveUsage? {
        let now = Date()
        let (doFetch, cached): (Bool, CodexLiveUsage?) = lock.withLock {
            if gate.shouldFetch(now: now, policy: policy) {
                gate.lastAttemptAt = now   // F3: optimistický claim — serializuje souběžné fetchFresh
                return (true, lastGood)
            }
            return (false, lastGood)
        }
        if !doFetch { return cached }

        let (signal, snapshot) = await doNetwork()
        lock.withLock {
            gate = gate.after(signal: signal, now: now, policy: policy)
            if let s = snapshot { lastGood = s }
        }
        return snapshot ?? cached
    }

    private func doNetwork() async -> (LiveFetchSignal, CodexLiveUsage?) {
        guard let auth = CodexAuth.read() else { return (.failed, nil) }
        var (status, body) = await usageCall(token: auth.accessToken, accountId: auth.accountId)
        if status == 401, let refresh = auth.refreshToken, let newToken = await refreshAndStore(refreshToken: refresh) {
            (status, body) = await usageCall(token: newToken, accountId: auth.accountId)
        }
        switch status {
        case 200:
            guard let body, let snap = CodexUsageAPIParser.parse(body), !snap.windows.isEmpty
            else { return (.failed, nil) }
            return (.success, CodexLiveUsage(snapshot: snap, fetchedAt: Date()))
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
        // F1: refresh_token musí být percent-enkódovaný (může obsahovat +, /, =) — jinak rozbitý form body
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        let rt = refreshToken.addingPercentEncoding(withAllowedCharacters: allowed) ?? refreshToken
        let form = "grant_type=refresh_token&client_id=app_EMoamEEZ73f0CkXaXp7hrann&refresh_token=\(rt)"
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
