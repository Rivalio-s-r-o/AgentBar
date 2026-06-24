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

@Test func odhadReálnýJenInputOutput() {
    // input 1M + output 1M + cacheRead 100M na Opus → reálná cena = 5 + 25 = 30 (cache ignorována)
    let t = TokenUsage(input: 1_000_000, output: 1_000_000, cacheWrite: 1_000_000, cacheRead: 100_000_000)
    #expect(PricingEstimator.estimateReal(t, model: "claude-opus-4-8") == Decimal(30))
}

@Test func odhadReálnýNeznámýModelJeNula() {
    #expect(PricingEstimator.estimateReal(TokenUsage(input: 1_000_000), model: "neznamy-xyz") == 0)
}

@Test func odhadReálnýPerModelSečte() {
    let perModel = [
        ModelTokens(modelName: "claude-sonnet-4-6", tokens: TokenUsage(input: 1_000_000, cacheRead: 9_000_000)),  // real 3.0, cache ignor.
        ModelTokens(modelName: "claude-haiku-4-5", tokens: TokenUsage(output: 1_000_000)),                          // real 5.0
    ]
    #expect(PricingEstimator.estimateReal(perModel) == Decimal(8))
}

@Test func odhadCacheWriteSonnetHaiku() {
    // Sonnet cacheWrite 3.75 / 1M; Haiku cacheWrite 1.25 / 1M (plná estimate)
    #expect(PricingEstimator.estimate(TokenUsage(cacheWrite: 1_000_000), model: "claude-sonnet-4-6") == Decimal(string: "3.75")!)
    #expect(PricingEstimator.estimate(TokenUsage(cacheWrite: 1_000_000), model: "claude-haiku-4-5") == Decimal(string: "1.25")!)
}

@Test func pricingTableGPT5Větve() {
    let g5 = PricingTable.pricing(forModel: "gpt-5")
    #expect(g5?.input == Decimal(string: "2.5")!)
    #expect(g5?.output == Decimal(15))
    let g55 = PricingTable.pricing(forModel: "gpt-5.5")
    #expect(g55?.input == Decimal(5))
    #expect(g55?.output == Decimal(30))
}
