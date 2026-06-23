import Testing
import Foundation
@testable import StatusBarKit

@Test func odhadOpusCacheAware() {
    // 1M input + 1M output + 1M cacheRead na Opus (5 / 25 / cacheRead 0.5)
    let t = TokenUsage(input: 1_000_000, output: 1_000_000, cacheWrite: 0, cacheRead: 1_000_000)
    let cost = PricingEstimator.estimate(t, model: "claude-opus-4-8")
    #expect(cost == Decimal(5) + Decimal(25) + Decimal(string: "0.5")!)  // 30.5
}

@Test func odhadNeznámýModelJeNula() {
    #expect(PricingEstimator.estimate(TokenUsage(input: 1_000_000), model: "neznamy-xyz") == 0)
}

@Test func odhadPerModelSečte() {
    let perModel = [
        ModelTokens(modelName: "claude-sonnet-4-6", tokens: TokenUsage(input: 1_000_000)),  // 3.0
        ModelTokens(modelName: "claude-haiku-4-5", tokens: TokenUsage(output: 1_000_000)),   // 5.0
    ]
    #expect(PricingEstimator.estimate(perModel) == Decimal(8))
}
