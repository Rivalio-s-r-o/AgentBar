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
