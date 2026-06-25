import Foundation

/// Model dvoubarevného burn proužku v liště. Frakce 0..1 (clamp pro kreslení).
public struct BurnBar: Sendable, Equatable {
    public let used: Double          // vyčerpáno teď (0..1)
    public let projected: Double     // projekce do resetu (0..1, vždy >= used)
    public let overLimit: Bool       // surová projekce > 1.0 → limit padne před resetem
    public let usedLevel: UsageLevel       // barva plné části (aktuální stav)
    public let projectedLevel: UsageLevel  // barva projekce (kam směřuje)
    public init(used: Double, projected: Double, overLimit: Bool, usedLevel: UsageLevel, projectedLevel: UsageLevel) {
        self.used = used; self.projected = projected; self.overLimit = overLimit
        self.usedLevel = usedLevel; self.projectedLevel = projectedLevel
    }
}

public enum BurnBarBuilder {
    public static func bar(forWindow w: UsageWindow, now: Date) -> BurnBar {
        let used = min(1.0, max(0, w.usedFraction))
        let projRaw = BurnRateCalculator.project(window: w, now: now)?.projectedFractionAtReset
        let projected = projRaw.map { min(1.0, max($0, used)) } ?? used
        let overLimit = (projRaw ?? 0) > 1.0
        let usedLevel = UsageLevel.level(forPercent: Int((used * 100).rounded()))
        let projectedLevel = UsageLevel.level(forPercent: Int((projected * 100).rounded()))
        return BurnBar(used: used, projected: projected, overLimit: overLimit,
                       usedLevel: usedLevel, projectedLevel: projectedLevel)
    }

    public static func bar(for usage: ProviderUsage, source: BarWindowSource, now: Date) -> BurnBar? {
        guard let w = usage.selectedWindow(for: source) else { return nil }
        return bar(forWindow: w, now: now)
    }
}
