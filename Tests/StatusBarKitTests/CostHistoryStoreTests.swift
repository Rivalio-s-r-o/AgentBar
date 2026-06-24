// Tests/StatusBarKitTests/CostHistoryStoreTests.swift
import Testing
import Foundation
@testable import StatusBarKit

private let t0 = Date(timeIntervalSince1970: 1_000_000)

@MainActor @Test func costHistoryNaplníHistoriiAUkončíPočítání() async {
    let store = CostHistoryStore(staleInterval: 3600, provider: { _ in
        [.claudeCode: PeriodCost(tokens: TokenUsage(input: 1000, output: 500), cost: Decimal(5))]
    })
    await store.refresh(now: t0)
    #expect(store.history[.claudeCode]?.cost == Decimal(5))
    #expect(store.history[.claudeCode]?.tokens.realTokens == 1500)
    #expect(store.isComputing == false)
    #expect(store.lastComputed == t0)
}

@MainActor @Test func costHistoryThrottle() async {
    let store = CostHistoryStore(staleInterval: 3600, provider: { _ in [:] })
    #expect(store.shouldRefresh(now: t0) == true)                              // nikdy nepočítáno
    await store.refresh(now: t0)
    #expect(store.shouldRefresh(now: t0.addingTimeInterval(1800)) == false)    // čerstvé (< 1h)
    #expect(store.shouldRefresh(now: t0.addingTimeInterval(3700)) == true)     // zatuchlé (> 1h)
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func bump() { lock.withLock { n += 1 } }
    var value: Int { lock.withLock { n } }
}

@MainActor @Test func costHistoryThrottleZabráníDruhémuComputeu() async {
    let counter = Counter()
    let store = CostHistoryStore(staleInterval: 3600, provider: { _ in counter.bump(); return [:] })
    await store.refresh(now: t0)
    await store.refresh(now: t0.addingTimeInterval(60))     // čerstvé → no-op (guard shouldRefresh)
    #expect(counter.value == 1)
}
