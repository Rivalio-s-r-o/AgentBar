import Foundation

public struct CodexCollector: UsageProvider {
    public let id: ProviderID = .codex
    private let sessionsDir: URL
    private let staleAfter: TimeInterval
    private let maxFilesToScan: Int
    private let liveSource: (any CodexUsageSource)?

    public init(sessionsDir: URL? = nil, staleAfter: TimeInterval = 24 * 3600,
                maxFilesToScan: Int = 10, liveSource: (any CodexUsageSource)? = nil) {
        self.sessionsDir = sessionsDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        self.staleAfter = staleAfter
        self.maxFilesToScan = maxFilesToScan
        self.liveSource = liveSource
    }

    public func fetch(includeToday: Bool) async -> ProviderUsage {
        let now = Date()
        let today = includeToday ? CodexTokenScanner().todayUsage(now: now) : nil

        // 1) Živé wham/usage (čerstvé limity + plán). Selhání → nil → fallback na JSONL.
        if let fresh = await liveSource?.fetchFresh() {
            return ProviderUsage(providerId: .codex, displayName: "Codex",
                planLabel: CodexPlan.label(forPlanType: fresh.snapshot.planType), windows: fresh.snapshot.windows,
                status: .ok, lastUpdated: fresh.fetchedAt, today: today)
        }

        // 2) Fallback: session JSONL (stávající chování).
        let files = newestSessionFiles(limit: maxFilesToScan)   // od nejnovějšího
        guard !files.isEmpty else {
            return .unavailable(.codex, displayName: "Codex",
                reason: NSLocalizedString("collector.codex.nosession", bundle: .module, comment: ""), now: now)
        }
        for f in files {
            guard let data = try? Data(contentsOf: f.url) else { continue }   // číst, NElogovat obsah
            guard let snap = CodexRateLimitParser.latestSnapshot(fromJSONL: data) else { continue }
            let age = now.timeIntervalSince(f.modified)
            let status: ProviderStatus = age > staleAfter
                ? .degraded(String(format: NSLocalizedString("collector.codex.stale", bundle: .module, comment: ""), Int(age/3600)))
                : .ok
            return ProviderUsage(providerId: .codex, displayName: "Codex",
                planLabel: CodexPlan.label(forPlanType: snap.planType), windows: snap.windows,
                status: status, lastUpdated: f.modified, today: today)
        }
        return .unavailable(.codex, displayName: "Codex",
            reason: String(format: NSLocalizedString("collector.codex.nolimits", bundle: .module, comment: ""), maxFilesToScan), now: now)
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
