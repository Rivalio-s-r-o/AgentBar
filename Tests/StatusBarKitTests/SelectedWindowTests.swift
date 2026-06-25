import Testing
import Foundation
@testable import StatusBarKit

private func u(_ windows: [UsageWindow]) -> ProviderUsage {
    ProviderUsage(providerId: .claudeCode, displayName: "C", planLabel: nil,
                  windows: windows, status: .ok, lastUpdated: Date())
}
private func w(_ kind: WindowKind, _ used: Double) -> UsageWindow {
    UsageWindow(kind: kind, usedFraction: used, resetAt: Date().addingTimeInterval(3600))
}

@Test func selectedWindowAuto() {
    let p = u([w(.rolling5h, 0.3), w(.weekly(scope: nil), 0.7)])
    #expect(p.selectedWindow(for: .auto)?.usedFraction == 0.7)   // max
}
@Test func selectedWindowSession() {
    let p = u([w(.rolling5h, 0.3), w(.weekly(scope: nil), 0.7)])
    #expect(p.selectedWindow(for: .session)?.kind == .rolling5h)
    // fallback na max když chybí rolling5h
    let p2 = u([w(.weekly(scope: nil), 0.6), w(.weekly(scope: "Sonnet"), 0.9)])
    #expect(p2.selectedWindow(for: .session)?.usedFraction == 0.9)
}
@Test func selectedWindowWeekly() {
    let p = u([w(.rolling5h, 0.9), w(.weekly(scope: nil), 0.4), w(.weekly(scope: "Opus"), 0.8)])
    #expect(p.selectedWindow(for: .weekly)?.usedFraction == 0.4)   // preferuje weekly_all (scope nil)
    let p2 = u([w(.rolling5h, 0.9), w(.weekly(scope: "Opus"), 0.8), w(.weekly(scope: "Sonnet"), 0.5)])
    #expect(p2.selectedWindow(for: .weekly)?.usedFraction == 0.8)  // nejhorší scoped weekly
}
@Test func selectedWindowPrazdne() {
    let p = u([])
    #expect(p.selectedWindow(for: .auto) == nil)
}
@Test func usedPercentBezeZmeny() {
    // refaktor nesmí změnit číslo
    let p = u([w(.rolling5h, 0.3), w(.weekly(scope: nil), 0.72)])
    #expect(p.usedPercent(for: .auto) == 72)
    #expect(p.usedPercent(for: .session) == 30)
    #expect(p.usedPercent(for: .weekly) == 72)
    #expect(u([]).usedPercent(for: .auto) == 0)
}
