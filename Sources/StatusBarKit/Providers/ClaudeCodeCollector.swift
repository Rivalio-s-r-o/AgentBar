import Foundation

public struct ClaudeCodeCollector: UsageProvider {
    public let id: ProviderID = .claudeCode
    private let cachePath: URL
    private let staleAfter: TimeInterval

    public init(cachePath: URL? = nil, staleAfter: TimeInterval = 6 * 3600) {
        self.cachePath = cachePath ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.usage_cache.json")
        self.staleAfter = staleAfter
    }

    public func fetch(includeToday: Bool) async -> ProviderUsage {
        let now = Date()
        guard let data = try? Data(contentsOf: cachePath) else {
            return .unavailable(.claudeCode, displayName: "Claude Code",
                reason: "Soubor \(cachePath.lastPathComponent) nenalezen. Otevři Claude Code a spusť /usage.", now: now)
        }
        do {
            let usage = try ClaudeUsageCacheParser.parse(data)
            let today = includeToday ? ClaudeTokenScanner().todayUsage(now: now) : nil
            let age = now.timeIntervalSince(usage.lastUpdated)
            if age > staleAfter {
                return ProviderUsage(providerId: usage.providerId, displayName: usage.displayName,
                    planLabel: usage.planLabel, windows: usage.windows,
                    status: .degraded("Data stará \(Int(age/60)) min — otevři Claude Code."),
                    lastUpdated: usage.lastUpdated, today: today)
            }
            return usage.with(today: today)
        } catch {
            return .unavailable(.claudeCode, displayName: "Claude Code",
                reason: "Cache nelze přečíst: \(error.localizedDescription)", now: now)
        }
    }
}
