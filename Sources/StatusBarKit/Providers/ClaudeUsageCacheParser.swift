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

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    public static func parse(_ data: Data) throws -> ProviderUsage {
        let cache = try JSONDecoder().decode(Cache.self, from: data)
        let windows: [UsageWindow] = cache.data.limits.compactMap { e in
            let kind: WindowKind
            switch e.kind {
            case "session":       kind = .rolling5h
            case "weekly_all":    kind = .weekly(scope: nil)
            case "weekly_scoped": kind = .weekly(scope: e.scope?.model?.display_name)
            default: return nil
            }
            return UsageWindow(kind: kind, usedFraction: e.percent / 100.0, resetAt: parseDate(e.resets_at))
        }
        return ProviderUsage(providerId: .claudeCode, displayName: "Claude Code", planLabel: nil,
                             windows: windows, status: .ok,
                             lastUpdated: Date(timeIntervalSince1970: cache.timestamp))
    }
}
