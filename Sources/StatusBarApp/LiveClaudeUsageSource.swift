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
