import Foundation

public struct CodexSnapshot: Sendable, Equatable {
    public let windows: [UsageWindow]
    public let planType: String?
    public init(windows: [UsageWindow], planType: String?) { self.windows = windows; self.planType = planType }
}

public enum CodexRateLimitParser {

    private struct Line: Decodable { let type: String?; let payload: Payload? }
    private struct Payload: Decodable { let type: String?; let rate_limits: RateLimits? }
    private struct RateLimits: Decodable { let primary: Window?; let secondary: Window?; let plan_type: String? }
    private struct Window: Decodable { let used_percent: Double?; let window_minutes: Double?; let resets_at: Double? }

    private static func window(from w: Window) -> UsageWindow? {
        guard let pct = w.used_percent else { return nil }
        // Okno určuj podle window_minutes: ~300 (5h) vs ~10080 (týden). Práh 1 den.
        let kind: WindowKind = (w.window_minutes ?? 0) < 1440 ? .rolling5h : .weekly(scope: nil)
        let reset = w.resets_at.map { Date(timeIntervalSince1970: $0) }
        return UsageWindow(kind: kind, usedFraction: pct / 100.0, resetAt: reset)
    }

    public static func latestSnapshot(fromJSONL data: Data) -> CodexSnapshot? {
        let decoder = JSONDecoder()
        var last: RateLimits?
        for raw in data.split(separator: UInt8(ascii: "\n")) {
            guard !raw.isEmpty,
                  let line = try? decoder.decode(Line.self, from: Data(raw)),
                  line.type == "event_msg", line.payload?.type == "token_count",
                  let rl = line.payload?.rate_limits,
                  rl.primary != nil || rl.secondary != nil
            else { continue }
            last = rl
        }
        guard let rl = last else { return nil }
        var windows: [UsageWindow] = []
        if let p = rl.primary, let w = window(from: p) { windows.append(w) }
        if let s = rl.secondary, let w = window(from: s) { windows.append(w) }
        guard !windows.isEmpty else { return nil }
        return CodexSnapshot(windows: windows, planType: rl.plan_type)
    }
}
