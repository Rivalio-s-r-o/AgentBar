import Testing
@testable import StatusBarKit

@Test func tokenUsageSoučetACelkem() {
    let a = TokenUsage(input: 10, output: 5, cacheWrite: 2, cacheRead: 100)
    let b = TokenUsage(input: 1, output: 1, cacheWrite: 0, cacheRead: 3)
    let s = a + b
    #expect(s == TokenUsage(input: 11, output: 6, cacheWrite: 2, cacheRead: 103))
    #expect(s.totalTokens == 11 + 6 + 2 + 103)
}

@Test func todayUsageTotalSečteModely() {
    let t = TodayUsage(perModel: [
        ModelTokens(modelName: "Opus", tokens: TokenUsage(input: 100, output: 50)),
        ModelTokens(modelName: "Sonnet", tokens: TokenUsage(input: 10, output: 5)),
    ], estimatedCost: 0)
    #expect(t.total == TokenUsage(input: 110, output: 55))
}
