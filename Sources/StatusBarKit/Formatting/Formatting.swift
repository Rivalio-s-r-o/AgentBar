import Foundation

public enum UsageLevel: Sendable, Equatable {
    case normal, warning, critical
    public static func level(forPercent p: Int) -> UsageLevel {
        switch p { case ..<75: return .normal; case 75..<90: return .warning; default: return .critical }
    }
}

public struct MenuBarSegment: Sendable, Equatable {
    public let providerId: ProviderID; public let text: String; public let level: UsageLevel
    public init(providerId: ProviderID, text: String, level: UsageLevel) {
        self.providerId = providerId; self.text = text; self.level = level
    }
}

public enum MenuBarTitleBuilder {
    public static func segments(for usages: [ProviderUsage]) -> [MenuBarSegment] {
        usages.map { u in
            if case .unavailable = u.status { return MenuBarSegment(providerId: u.providerId, text: "—", level: .normal) }
            let p = u.nearestLimitPercent
            return MenuBarSegment(providerId: u.providerId, text: "\(p)%", level: UsageLevel.level(forPercent: p))
        }
    }
}

public enum ResetFormatter {
    public static func short(until date: Date, now: Date) -> String {
        let s = Int(date.timeIntervalSince(now)); guard s > 0 else { return "teď" }
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

public enum WindowLabel {
    public static func text(for kind: WindowKind) -> String {
        switch kind {
        case .rolling5h: return "5h okno"
        case .weekly(let s): return s.map { "Týden · \($0)" } ?? "Týden"
        }
    }
}
