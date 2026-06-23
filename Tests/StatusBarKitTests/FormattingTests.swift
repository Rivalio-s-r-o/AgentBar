import Testing
import Foundation
@testable import StatusBarKit

@Test func úrovněPodleProcent() {
    #expect(UsageLevel.level(forPercent: 10) == .normal)
    #expect(UsageLevel.level(forPercent: 80) == .warning)
    #expect(UsageLevel.level(forPercent: 95) == .critical)
    #expect(UsageLevel.level(forPercent: 130) == .critical)   // overage M2
}

@Test func segmentyStyluA() {
    let usages = [
        ProviderUsage(providerId: .claudeCode, displayName: "Claude Code", planLabel: nil,
            windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.42, resetAt: nil)], status: .ok, lastUpdated: Date()),
        ProviderUsage(providerId: .codex, displayName: "Codex", planLabel: nil,
            windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.92, resetAt: nil)], status: .ok, lastUpdated: Date()),
    ]
    let s = MenuBarTitleBuilder.segments(for: usages)
    #expect(s[0] == MenuBarSegment(providerId: .claudeCode, text: "42%", level: .normal))
    #expect(s[1] == MenuBarSegment(providerId: .codex, text: "92%", level: .critical))
}

@Test func segmentNedostupný() {
    let u = [ProviderUsage.unavailable(.claudeCode, displayName: "Claude Code", reason: "x", now: Date())]
    #expect(MenuBarTitleBuilder.segments(for: u)[0] == MenuBarSegment(providerId: .claudeCode, text: "—", level: .normal))
}

@Test func resetFormat() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(ResetFormatter.short(until: Date(timeIntervalSince1970: 2*3600+14*60), now: now) == "2h 14m")
    #expect(ResetFormatter.short(until: Date(timeIntervalSince1970: 41*60), now: now) == "41m")
    #expect(ResetFormatter.short(until: Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 100)) == "teď")
}

@Test func popiskyOken() {
    #expect(WindowLabel.text(for: .rolling5h) == "5h okno")
    #expect(WindowLabel.text(for: .weekly(scope: nil)) == "Týden")
    #expect(WindowLabel.text(for: .weekly(scope: "Sonnet")) == "Týden · Sonnet")
}
