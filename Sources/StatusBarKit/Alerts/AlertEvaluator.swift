import Foundation

public struct AlertKey: Hashable, Sendable {
    public let providerId: ProviderID
    public let window: WindowKind
    public init(providerId: ProviderID, window: WindowKind) {
        self.providerId = providerId; self.window = window
    }
}

public struct AlertEvent: Equatable, Sendable {
    public let providerDisplayName: String
    public let windowLabel: String
    public let remainingPercent: Int
    public let resetAt: Date?
    public init(providerDisplayName: String, windowLabel: String, remainingPercent: Int, resetAt: Date?) {
        self.providerDisplayName = providerDisplayName; self.windowLabel = windowLabel
        self.remainingPercent = remainingPercent; self.resetAt = resetAt
    }
}

public enum AlertEvaluator {
    public static func evaluate(
        usages: [ProviderUsage],
        thresholdPercent: Int,
        alreadyAlerted: Set<AlertKey>
    ) -> (toFire: [AlertEvent], newState: Set<AlertKey>) {
        var toFire: [AlertEvent] = []
        var newState: Set<AlertKey> = []
        for u in usages {
            guard case .ok = u.status else { continue }      // jen čerstvá data
            for w in u.windows {
                let remaining = max(0, 100 - Int((w.usedFraction * 100).rounded()))
                guard remaining <= thresholdPercent else { continue }   // nad prahem → klíč se nepřidá (rearm)
                let key = AlertKey(providerId: u.providerId, window: w.kind)
                newState.insert(key)
                if !alreadyAlerted.contains(key) {
                    toFire.append(AlertEvent(
                        providerDisplayName: u.displayName,
                        windowLabel: WindowLabel.text(for: w.kind),
                        remainingPercent: remaining,
                        resetAt: w.resetAt))
                }
            }
        }
        return (toFire, newState)
    }
}
