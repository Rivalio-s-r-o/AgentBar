import Foundation

/// Souhrn ceny + tokenů za období (display vrstva pro 30denní cenu).
public struct PeriodCost: Sendable, Equatable {
    public let tokens: TokenUsage
    public let cost: Decimal
    public init(tokens: TokenUsage, cost: Decimal) {
        self.tokens = tokens; self.cost = cost
    }
}
