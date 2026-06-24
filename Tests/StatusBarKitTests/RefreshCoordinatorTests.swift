import Testing
import Foundation
@testable import StatusBarKit

private struct Stub: UsageProvider {
    let id: ProviderID; let frac: Double
    func fetch(includeToday: Bool) async -> ProviderUsage {
        ProviderUsage(providerId: id, displayName: id.rawValue, planLabel: nil,
            windows: [UsageWindow(kind: .rolling5h, usedFraction: frac, resetAt: nil)], status: .ok, lastUpdated: Date())
    }
}

@MainActor @Test func refreshNowNaplníStoreJednímZápisem() async {
    let store = UsageStore()
    await RefreshCoordinator(store: store, providers: [Stub(id: .claudeCode, frac: 0.3), Stub(id: .codex, frac: 0.9)]).refreshNow()
    #expect(store.providers.count == 2)
    #expect(store.worstPercent == 90)
}

private struct TodayStub: UsageProvider {
    let id: ProviderID
    func fetch(includeToday: Bool) async -> ProviderUsage {
        let today = includeToday
            ? TodayUsage(perModel: [ModelTokens(modelName: "x", tokens: TokenUsage(input: 100))], estimatedCost: 1)
            : nil
        return ProviderUsage(providerId: id, displayName: id.rawValue, planLabel: nil,
            windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.5, resetAt: nil)],
            status: .ok, lastUpdated: Date(), today: today)
    }
}

@MainActor @Test func líneRefreshZachováTodayMeziSkeny() async {
    let store = UsageStore()
    let coord = RefreshCoordinator(store: store, providers: [TodayStub(id: .claudeCode)])
    await coord.refreshNow(includeToday: true)
    #expect(store.providers[.claudeCode]?.today != nil)        // čerstvý sken
    await coord.refreshNow(includeToday: false)
    #expect(store.providers[.claudeCode]?.today != nil)        // NEzmizelo (cache)
}

@MainActor @Test func líneRefreshBezPředchozíhoSkenuNemáToday() async {
    let store = UsageStore()
    let coord = RefreshCoordinator(store: store, providers: [TodayStub(id: .claudeCode)])
    await coord.refreshNow(includeToday: false)
    #expect(store.providers[.claudeCode]?.today == nil)        // nic k zachování
}
