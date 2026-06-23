import Testing
import Foundation
@testable import StatusBarKit

@Test func nearestLimitPercentVracíMaximumZOken() {
    let u = ProviderUsage(providerId: .claudeCode, displayName: "Claude Code", planLabel: nil,
        windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.08, resetAt: nil),
                  UsageWindow(kind: .weekly(scope: nil), usedFraction: 0.61, resetAt: nil)],
        status: .ok, lastUpdated: Date(timeIntervalSince1970: 0))
    #expect(u.nearestLimitPercent == 61)
}

@Test func overagePřes100Procent() {  // M2
    let u = ProviderUsage(providerId: .codex, displayName: "Codex", planLabel: nil,
        windows: [UsageWindow(kind: .rolling5h, usedFraction: 1.05, resetAt: nil)],
        status: .ok, lastUpdated: Date(timeIntervalSince1970: 0))
    #expect(u.nearestLimitPercent == 105)
}

@Test func bezOkenJeNula() {
    let u = ProviderUsage.unavailable(.codex, displayName: "Codex", reason: "x", now: Date(timeIntervalSince1970: 0))
    #expect(u.nearestLimitPercent == 0)
}
