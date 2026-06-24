import Foundation
import StatusBarKit

enum AppVersion {
    static func current() -> SemanticVersion? {
        guard let s = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return nil }
        return SemanticVersion.parse(s)
    }
}

/// Anonymní read-only GET na veřejné GitHub Releases API. Žádný token, žádná auth.
/// Privátní repo / chyba sítě → nil (graceful). `releases/latest` vynechává drafty i prereleases.
struct GitHubReleaseChecker {
    let owner = "Rivalio-s-r-o"
    let repo = "StatusBar"
    func fetchLatest() async -> (tag: String, url: String)? {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("StatusBar-app", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        guard let pair = try? await URLSession.shared.data(for: req),
              (pair.1 as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: pair.0) as? [String: Any],
              let tag = obj["tag_name"] as? String else { return nil }
        let html = (obj["html_url"] as? String) ?? "https://github.com/\(owner)/\(repo)/releases"
        return (tag, html)
    }
}

@MainActor
final class UpdateCoordinator: ObservableObject {
    @Published private(set) var status: UpdateStatus = .unknown
    @Published private(set) var isChecking: Bool = false
    private let prefs: PreferencesStore
    private let checker = GitHubReleaseChecker()
    private static let interval: TimeInterval = 24 * 3600

    init(prefs: PreferencesStore) { self.prefs = prefs }

    func checkNow() async {
        guard let cur = AppVersion.current() else { return }
        guard !isChecking else { return }
        isChecking = true
        let latest = await checker.fetchLatest()
        status = UpdateChecker.evaluate(current: cur, latestTag: latest?.tag, latestURL: latest?.url)
        prefs.lastUpdateCheckAt = Date().timeIntervalSince1970
        isChecking = false
    }

    func checkIfDue() async {
        guard prefs.autoUpdateCheck else { return }
        let since = Date().timeIntervalSince1970 - prefs.lastUpdateCheckAt
        if since >= Self.interval { await checkNow() }
    }
}
