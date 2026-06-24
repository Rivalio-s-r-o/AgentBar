import Foundation

public struct ClaudeLiveUsage: Sendable, Equatable {
    public let windows: [UsageWindow]
    public let planLabel: String?
    public init(windows: [UsageWindow], planLabel: String?) {
        self.windows = windows; self.planLabel = planLabel
    }
}

/// Zdroj ČERSTVÝCH Claude limitů (živé API). Implementace v app vrstvě; nil = nezdařilo se → fallback na cache.
public protocol ClaudeUsageSource: Sendable {
    func fetchFresh() async -> ClaudeLiveUsage?
}
