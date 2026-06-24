import Testing
import Foundation
@testable import StatusBarKit

@Test func periodCostRovnost() {
    let a = PeriodCost(tokens: TokenUsage(input: 10, output: 20), cost: Decimal(5))
    let b = PeriodCost(tokens: TokenUsage(input: 10, output: 20), cost: Decimal(5))
    #expect(a == b)
    #expect(a.tokens.realTokens == 30)
    #expect(a.cost == Decimal(5))
}
