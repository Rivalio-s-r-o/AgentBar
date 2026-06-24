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
