import Foundation

public enum ProviderID: String, Sendable, CaseIterable {
    case claudeCode
    case codex
}

public enum WindowKind: Sendable, Hashable {
    case rolling5h
    case weekly(scope: String?)
}

public enum ProviderStatus: Sendable, Equatable {
    case ok
    case degraded(String)
    case unavailable(String)
}

public struct UsageWindow: Sendable, Equatable {
    public let kind: WindowKind
    public let usedFraction: Double
    public let resetAt: Date?
    public init(kind: WindowKind, usedFraction: Double, resetAt: Date?) {
        self.kind = kind; self.usedFraction = usedFraction; self.resetAt = resetAt
    }
}

public struct ProviderUsage: Sendable, Equatable {
    public let providerId: ProviderID
    public let displayName: String
    public let planLabel: String?
    public let windows: [UsageWindow]
    public let status: ProviderStatus
    public let lastUpdated: Date
    public let today: TodayUsage?
    public init(providerId: ProviderID, displayName: String, planLabel: String?,
                windows: [UsageWindow], status: ProviderStatus, lastUpdated: Date,
                today: TodayUsage? = nil) {
        self.providerId = providerId; self.displayName = displayName; self.planLabel = planLabel
        self.windows = windows; self.status = status; self.lastUpdated = lastUpdated
        self.today = today
    }

    public func with(today: TodayUsage?) -> ProviderUsage {
        ProviderUsage(providerId: providerId, displayName: displayName, planLabel: planLabel,
                      windows: windows, status: status, lastUpdated: lastUpdated, today: today)
    }

    public var nearestLimitFraction: Double { windows.map(\.usedFraction).max() ?? 0 }
    public var nearestLimitPercent: Int { Int((nearestLimitFraction * 100).rounded()) }

    /// Used % okna zvoleného lištou. Chybí-li dané okno, fallback na nejhorší (nearestLimitPercent).
    public func usedPercent(for source: BarWindowSource) -> Int {
        switch source {
        case .auto:
            return nearestLimitPercent
        case .session:
            if let w = windows.first(where: { $0.kind == .rolling5h }) {
                return Int((w.usedFraction * 100).rounded())
            }
            return nearestLimitPercent
        case .weekly:
            // F2: preferuj CELKOVÉ týdenní okno (weekly_all, scope == nil) — to je „Weekly" na fotce.
            if let allWeekly = windows.first(where: { if case .weekly(let s) = $0.kind { return s == nil }; return false }) {
                return Int((allWeekly.usedFraction * 100).rounded())
            }
            // jinak nejhorší týdenní (scoped), jinak nearest
            let weeklies = windows.filter { if case .weekly = $0.kind { return true }; return false }
            if let w = weeklies.max(by: { $0.usedFraction < $1.usedFraction }) {
                return Int((w.usedFraction * 100).rounded())
            }
            return nearestLimitPercent
        }
    }

    public static func unavailable(_ id: ProviderID, displayName: String, reason: String, now: Date) -> ProviderUsage {
        ProviderUsage(providerId: id, displayName: displayName, planLabel: nil,
                      windows: [], status: .unavailable(reason), lastUpdated: now)
    }
}
