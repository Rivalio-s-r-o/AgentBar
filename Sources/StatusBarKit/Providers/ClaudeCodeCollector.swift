import Foundation

public struct ClaudeCodeCollector: UsageProvider {
    public let id: ProviderID = .claudeCode
    private let cachePath: URL
    private let staleAfter: TimeInterval
    private let liveSource: (any ClaudeUsageSource)?

    public init(cachePath: URL? = nil, staleAfter: TimeInterval = 6 * 3600, liveSource: (any ClaudeUsageSource)? = nil) {
        self.cachePath = cachePath ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.usage_cache.json")
        self.staleAfter = staleAfter
        self.liveSource = liveSource
    }

    public func fetch(includeToday: Bool) async -> ProviderUsage {
        let now = Date()
        let today = includeToday ? ClaudeTokenScanner().todayUsage(now: now) : nil

        // 1) Živé API (čerstvé limity + plán). Selhání → nil → fallback na cache.
        if let fresh = await liveSource?.fetchFresh() {
            return ProviderUsage(providerId: .claudeCode, displayName: "Claude Code",
                planLabel: fresh.planLabel, windows: fresh.windows, status: .ok,
                lastUpdated: fresh.fetchedAt, today: today)
        }

        // 2) Fallback: lokální cache (stávající chování v0.1–v0.5).
        guard let data = try? Data(contentsOf: cachePath) else {
            return .unavailable(.claudeCode, displayName: "Claude Code",
                reason: String(format: NSLocalizedString("collector.claude.missing", bundle: .module, comment: ""), cachePath.lastPathComponent), now: now)
        }
        do {
            let usage = try ClaudeUsageCacheParser.parse(data)
            let age = now.timeIntervalSince(usage.lastUpdated)
            if age > staleAfter {
                return ProviderUsage(providerId: usage.providerId, displayName: usage.displayName,
                    planLabel: usage.planLabel, windows: usage.windows,
                    status: .degraded(String(format: NSLocalizedString("collector.claude.stale", bundle: .module, comment: ""), Int(age/60))),
                    lastUpdated: usage.lastUpdated, today: today)
            }
            return usage.with(today: today)
        } catch {
            return .unavailable(.claudeCode, displayName: "Claude Code",
                reason: String(format: NSLocalizedString("collector.claude.unreadable", bundle: .module, comment: ""), error.localizedDescription), now: now)
        }
    }
}
