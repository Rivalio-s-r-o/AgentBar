import Foundation

/// Parsuje odpověď živého Codex usage endpointu (chatgpt.com/backend-api/wham/usage)
/// do existujícího CodexSnapshot. nil = bez čerstvých dat → fallback na JSONL.
public enum CodexUsageAPIParser {
    private struct Response: Decodable {
        let plan_type: String?
        let rate_limit: RateLimit?
    }
    private struct RateLimit: Decodable {
        let primary_window: Window?
        let secondary_window: Window?
    }
    private struct Window: Decodable {
        let used_percent: Double?
        let limit_window_seconds: Double?
        let reset_at: Double?
    }

    private static func window(from w: Window) -> UsageWindow? {
        guard let pct = w.used_percent else { return nil }
        // Okno dle limit_window_seconds: 18000 (5h) vs 604800 (týden). Práh 1 den.
        let kind: WindowKind = (w.limit_window_seconds ?? 0) < 86400 ? .rolling5h : .weekly(scope: nil)
        let reset = w.reset_at.map { Date(timeIntervalSince1970: $0) }
        return UsageWindow(kind: kind, usedFraction: pct / 100.0, resetAt: reset)
    }

    public static func parse(_ data: Data) -> CodexSnapshot? {
        guard let r = try? JSONDecoder().decode(Response.self, from: data),
              let rl = r.rate_limit else { return nil }
        var windows: [UsageWindow] = []
        if let p = rl.primary_window, let w = window(from: p) { windows.append(w) }
        if let s = rl.secondary_window, let w = window(from: s) { windows.append(w) }
        guard !windows.isEmpty else { return nil }
        return CodexSnapshot(windows: windows, planType: r.plan_type)
    }
}
