import Foundation

/// Živý Codex výsledek: snapshot (z parseru) + čas pořízení.
public struct CodexLiveUsage: Sendable, Equatable {
    public let snapshot: CodexSnapshot
    public let fetchedAt: Date
    public init(snapshot: CodexSnapshot, fetchedAt: Date = Date()) {
        self.snapshot = snapshot; self.fetchedAt = fetchedAt
    }
}

/// Zdroj ČERSTVÝCH Codex limitů (živé wham/usage API). nil = nezdařilo se → fallback na JSONL.
public protocol CodexUsageSource: Sendable {
    func fetchFresh() async -> CodexLiveUsage?
}
