import Testing
import Foundation
@testable import StatusBarKit

private struct Stub: UsageProvider {
    let id: ProviderID; let frac: Double
    func fetch() async -> ProviderUsage {
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
