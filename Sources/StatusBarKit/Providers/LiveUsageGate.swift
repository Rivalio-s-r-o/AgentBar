import Foundation

/// Konfigurace throttlingu živého usage zdroje.
public struct LiveUsagePolicy: Sendable, Equatable {
    public let minInterval: TimeInterval   // min. čas mezi síťovými pokusy (default 5 min)
    public let cooldown: TimeInterval      // backoff po HTTP 429 (default 15 min)
    public init(minInterval: TimeInterval = 300, cooldown: TimeInterval = 900) {
        self.minInterval = minInterval; self.cooldown = cooldown
    }
}

/// Výsledek síťového pokusu o živá data.
public enum LiveFetchSignal: Sendable, Equatable { case success, rateLimited, failed }

/// Stavový automat throttle/backoff (pure, testovatelný s injektovaným `now`).
public struct LiveGateState: Sendable, Equatable {
    public var lastAttemptAt: Date?
    public var cooldownUntil: Date?
    public init(lastAttemptAt: Date? = nil, cooldownUntil: Date? = nil) {
        self.lastAttemptAt = lastAttemptAt; self.cooldownUntil = cooldownUntil
    }
    /// Smí se teď sáhnout na síť? false během cooldownu nebo do `minInterval` od posledního pokusu.
    public func shouldFetch(now: Date, policy: LiveUsagePolicy) -> Bool {
        if let cd = cooldownUntil, now < cd { return false }
        if let last = lastAttemptAt, now.timeIntervalSince(last) < policy.minInterval { return false }
        return true
    }
    /// Nový stav po síťovém pokusu. `.rateLimited` nastaví cooldown, jinak ho zruší.
    public func after(signal: LiveFetchSignal, now: Date, policy: LiveUsagePolicy) -> LiveGateState {
        var s = self
        s.lastAttemptAt = now
        switch signal {
        case .rateLimited: s.cooldownUntil = now.addingTimeInterval(policy.cooldown)
        case .success, .failed: s.cooldownUntil = nil
        }
        return s
    }
}
