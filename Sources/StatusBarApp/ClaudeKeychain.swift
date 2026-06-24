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
