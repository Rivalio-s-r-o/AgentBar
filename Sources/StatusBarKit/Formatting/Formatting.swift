import Foundation

public enum UsageLevel: Sendable, Equatable {
    case normal, warning, critical
    public static func level(forPercent p: Int) -> UsageLevel {
        switch p { case ..<75: return .normal; case 75..<90: return .warning; default: return .critical }
    }
}

public struct MenuBarSegment: Sendable, Equatable {
    public enum Leading: Sendable, Equatable {
        case providerDot          // tečka v barvě providera
        case levelDot             // tečka v barvě stavu (level)
        case label(String)        // písmenný štítek v barvě stavu
        case none                 // bez prefixu
    }
    public let providerId: ProviderID; public let leading: Leading
    public let text: String; public let level: UsageLevel
    public init(providerId: ProviderID, leading: Leading = .providerDot, text: String, level: UsageLevel) {
        self.providerId = providerId; self.leading = leading; self.text = text; self.level = level
    }
}

public enum MenuBarTitleBuilder {
    private static func shortLabel(_ id: ProviderID) -> String {
        switch id { case .claudeCode: return "CC"; case .codex: return "CX" }
    }

    private static func displayable(_ u: ProviderUsage) -> Bool {
        if case .unavailable = u.status { return false }; return true
    }

    /// Segment pro styly A/B (per provider, tečka providera nebo štítek).
    private static func perProvider(_ u: ProviderUsage, label: Bool, showUsedPercent: Bool, source: BarWindowSource) -> MenuBarSegment {
        let leading: MenuBarSegment.Leading = label ? .label(shortLabel(u.providerId)) : .providerDot
        if case .unavailable = u.status {
            return MenuBarSegment(providerId: u.providerId, leading: leading, text: "—", level: .normal)
        }
        let used = u.usedPercent(for: source)
        let shown = showUsedPercent ? used : max(0, 100 - used)
        return MenuBarSegment(providerId: u.providerId, leading: leading,
                              text: "\(shown)%", level: UsageLevel.level(forPercent: used))
    }

    public static func segments(for usages: [ProviderUsage],
                                style: MenuBarStyle = .dotPercent,
                                showUsedPercent: Bool = false,
                                source: BarWindowSource = .auto) -> [MenuBarSegment] {
        switch style {
        case .dotPercent:
            return usages.map { perProvider($0, label: false, showUsedPercent: showUsedPercent, source: source) }
        case .labelPercent:
            return usages.map { perProvider($0, label: true, showUsedPercent: showUsedPercent, source: source) }
        case .dotOnly:
            return usages.map { u in
                let level = displayable(u) ? UsageLevel.level(forPercent: u.usedPercent(for: source)) : .normal
                return MenuBarSegment(providerId: u.providerId, leading: .levelDot, text: "", level: level)
            }
        case .worst:
            let pool = usages.filter(displayable)
            if let worst = pool.max(by: { $0.usedPercent(for: source) < $1.usedPercent(for: source) }) {
                let used = worst.usedPercent(for: source)
                let shown = showUsedPercent ? used : max(0, 100 - used)
                return [MenuBarSegment(providerId: worst.providerId, leading: .providerDot,
                                       text: "\(shown)%", level: UsageLevel.level(forPercent: used))]
            }
            if usages.isEmpty { return [] }
            return [MenuBarSegment(providerId: usages[0].providerId, leading: .none, text: "—", level: .normal)]
        }
    }
}

public enum ResetFormatter {
    public static func short(until date: Date, now: Date, bundle: Bundle? = nil) -> String {
        let b = bundle ?? .module
        let s = Int(date.timeIntervalSince(now))
        guard s > 0 else { return NSLocalizedString("reset.now", bundle: b, comment: "resets now") }
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"   // numerický formát beze slov — nelokalizuje se
    }
}

public enum WindowLabel {
    public static func text(for kind: WindowKind, bundle: Bundle? = nil) -> String {
        let b = bundle ?? .module
        switch kind {
        case .rolling5h: return NSLocalizedString("window.session", bundle: b, comment: "5h rolling window")
        case .weekly(let scope):
            if let scope { return scope }   // scoped weekly = jen název modelu (nepřekládá se)
            return NSLocalizedString("window.weekly", bundle: b, comment: "weekly window")
        }
    }
}
