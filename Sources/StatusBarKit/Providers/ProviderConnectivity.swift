import Foundation

/// Zjišťuje, zda je provider na tomto stroji „připojený" (nakonfigurovaný). Čistě filesystem —
/// NEsahá na Keychain (žádný ACL prompt). Připojený = domovská složka providera existuje
/// (`~/.claude` resp. `~/.codex`; obě CLI ji vytvoří při nastavení/přihlášení).
public enum ProviderConnectivity {
    public static func isConfigured(_ id: ProviderID,
                                    home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let dir = (id == .claudeCode) ? ".claude" : ".codex"
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: home.appendingPathComponent(dir).path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    /// Ghost = nepřipojený (žádná data ANI footprint). „Připojený ale dočasně nedostupný" NENÍ ghost.
    public static func isGhost(status: ProviderStatus, isConfigured: Bool) -> Bool {
        if case .unavailable = status { return !isConfigured }
        return false
    }
}
