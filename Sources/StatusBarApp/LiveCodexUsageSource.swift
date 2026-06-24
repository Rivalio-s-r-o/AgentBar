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
