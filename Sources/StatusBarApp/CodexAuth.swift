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
