import Foundation

public struct ClaudeLiveUsage: Sendable, Equatable {
    public let windows: [UsageWindow]
    public let planLabel: String?
    public let fetchedAt: Date
    public init(windows: [UsageWindow], planLabel: String?, fetchedAt: Date = Date()) {
        self.windows = windows; self.planLabel = planLabel; self.fetchedAt = fetchedAt
    }
}

/// Zdroj ČERSTVÝCH Claude limitů (živé API). Implementace v app vrstvě; nil = nezdařilo se → fallback na cache.
public protocol ClaudeUsageSource: Sendable {
    func fetchFresh() async -> ClaudeLiveUsage?
}
