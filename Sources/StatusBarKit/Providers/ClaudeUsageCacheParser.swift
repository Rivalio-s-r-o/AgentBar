import Foundation

public enum ClaudeUsageCacheParser {

    private struct Cache: Decodable { let timestamp: Double; let data: CacheData }
    private struct CacheData: Decodable { let limits: [LimitEntry] }
    private struct LimitEntry: Decodable {
        let kind: String
        let percent: Double
        let resets_at: String?
        let scope: Scope?
    }
    private struct Scope: Decodable { let model: Model? }
    private struct Model: Decodable { let display_name: String? }
    private struct APIResponse: Decodable { let limits: [LimitEntry] }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    private static func windows(from limits: [LimitEntry]) -> [UsageWindow] {
        limits.compactMap { e in
            let kind: WindowKind
            switch e.kind {
            case "session":       kind = .rolling5h
            case "weekly_all":    kind = .weekly(scope: nil)
            case "weekly_scoped": kind = .weekly(scope: e.scope?.model?.display_name)
            default: return nil
            }
            return UsageWindow(kind: kind, usedFraction: e.percent / 100.0, resetAt: parseDate(e.resets_at))
        }
    }

    public static func parse(_ data: Data) throws -> ProviderUsage {
        let cache = try JSONDecoder().decode(Cache.self, from: data)
        return ProviderUsage(providerId: .claudeCode, displayName: "Claude Code", planLabel: nil,
                             windows: windows(from: cache.data.limits), status: .ok,
                             lastUpdated: Date(timeIntervalSince1970: cache.timestamp))
    }

    /// Parse top-level odpovědi živého API (`{limits:[…]}`, bez timestamp/data wrapperu).
    public static func parseAPIWindows(_ data: Data) throws -> [UsageWindow] {
        windows(from: try JSONDecoder().decode(APIResponse.self, from: data).limits)
    }
}
