import Testing
import Foundation
@testable import StatusBarKit

@MainActor @Test func storeReplaceAllAWorstPercent() {
    let store = UsageStore()
    store.replaceAll([
        ProviderUsage(providerId: .codex, displayName: "Codex", planLabel: nil,
            windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.78, resetAt: nil)], status: .ok, lastUpdated: Date()),
        ProviderUsage(providerId: .claudeCode, displayName: "Claude Code", planLabel: nil,
            windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.42, resetAt: nil)], status: .ok, lastUpdated: Date()),
    ])
    #expect(store.providers.count == 2)
    #expect(store.worstPercent == 78)
    #expect(store.orderedUsages.map(\.providerId) == [.claudeCode, .codex])  // pořadí dle ProviderID.allCases
}
