import Foundation

/// Projekce vyčerpání okna při zachování dosavadního tempa.
public struct BurnProjection: Sendable, Equatable {
    /// Odhad vyčerpané frakce v čase resetu (1.0 = 100 %), může být > 1.
    public let projectedFractionAtReset: Double
    /// Sekundy do dosažení limitu, je-li projektováno PŘED resetem; jinak nil. 0 = limit už dosažen.
    public let timeToExhaustion: TimeInterval?
    public init(projectedFractionAtReset: Double, timeToExhaustion: TimeInterval?) {
        self.projectedFractionAtReset = projectedFractionAtReset
        self.timeToExhaustion = timeToExhaustion
    }
}

/// Burn-rate odhad: extrapoluje dosavadní tempo čerpání okna do času resetu.
public enum BurnRateCalculator {
    public static func project(window: UsageWindow, now: Date) -> BurnProjection? {
        guard let reset = window.resetAt, reset > now else { return nil }
        let duration: TimeInterval = window.kind == .rolling5h ? 5 * 3600 : 7 * 24 * 3600
        let start = reset.addingTimeInterval(-duration)
        let elapsed = now.timeIntervalSince(start)
        let elapsedFraction = elapsed / duration
        // Příliš brzy po startu okna → tempo statisticky bezcenné (dělení skoro nulou).
        guard elapsedFraction >= 0.02 else { return nil }
        let u = max(0, window.usedFraction)
        let proj = u / elapsedFraction
        var tte: TimeInterval? = nil
        if u >= 1.0 {
            tte = 0
        } else if proj > 1.0 {
            let rate = u / elapsed
            tte = (1.0 - u) / rate
        }
        return BurnProjection(projectedFractionAtReset: proj, timeToExhaustion: tte)
    }
}
