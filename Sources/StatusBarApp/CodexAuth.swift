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
