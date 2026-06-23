import Foundation

public struct CodexCollector: UsageProvider {
    public let id: ProviderID = .codex
    private let sessionsDir: URL
    private let staleAfter: TimeInterval
    private let maxFilesToScan: Int

    public init(sessionsDir: URL? = nil, staleAfter: TimeInterval = 24 * 3600, maxFilesToScan: Int = 10) {
        self.sessionsDir = sessionsDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        self.staleAfter = staleAfter
        self.maxFilesToScan = maxFilesToScan
    }

    public func fetch() async -> ProviderUsage {
        let now = Date()
        let files = newestSessionFiles(limit: maxFilesToScan)   // od nejnovějšího
        guard !files.isEmpty else {
            return .unavailable(.codex, displayName: "Codex",
                reason: "Žádná session v ~/.codex/sessions. Spusť jednou `codex`.", now: now)
        }
        for f in files {
            guard let data = try? Data(contentsOf: f.url) else { continue }   // číst, NElogovat obsah
            guard let snap = CodexRateLimitParser.latestSnapshot(fromJSONL: data) else { continue }
            let age = now.timeIntervalSince(f.modified)
            let status: ProviderStatus = age > staleAfter
                ? .degraded("Data stará \(Int(age/3600)) h — spusť `codex` pro aktualizaci.")
                : .ok
            return ProviderUsage(providerId: .codex, displayName: "Codex",
                planLabel: snap.planType, windows: snap.windows, status: status, lastUpdated: f.modified)
        }
        return .unavailable(.codex, displayName: "Codex",
            reason: "V posledních \(maxFilesToScan) sessionech nejsou žádné limity.", now: now)
    }

    private func newestSessionFiles(limit: Int) -> [(url: URL, modified: Date)] {
        guard let en = FileManager.default.enumerator(at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var all: [(URL, Date)] = []
        for case let url as URL in en where url.pathExtension == "jsonl" {
            if let m = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                all.append((url, m))
            }
        }
        return all.sorted { $0.1 > $1.1 }.prefix(limit).map { (url: $0.0, modified: $0.1) }
    }
}
