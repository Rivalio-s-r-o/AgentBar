import Foundation

/// Zdroj ČERSTVÝCH Codex limitů (živé wham/usage API). Implementace v app vrstvě;
/// nil = nezdařilo se → fallback na session JSONL.
public protocol CodexUsageSource: Sendable {
    func fetchFresh() async -> CodexSnapshot?
}
