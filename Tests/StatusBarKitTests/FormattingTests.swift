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
    // Text = ZBÝVAJÍCÍ % (100 - vyčerpáno); úroveň/barva pořád dle nebezpečí (vyčerpáno).
    #expect(s[0] == MenuBarSegment(providerId: .claudeCode, text: "58%", level: .normal))   // 42 vyčerpáno → 58 zbývá
    #expect(s[1] == MenuBarSegment(providerId: .codex, text: "8%", level: .critical))        // 92 vyčerpáno → 8 zbývá
}

@Test func segmentNedostupný() {
    let u = [ProviderUsage.unavailable(.claudeCode, displayName: "Claude Code", reason: "x", now: Date())]
    #expect(MenuBarTitleBuilder.segments(for: u)[0] == MenuBarSegment(providerId: .claudeCode, text: "—", level: .normal))
}

@Test func resetFormat() {
    let now = Date(timeIntervalSince1970: 0)
    let cs = L10n.bundle("cs"); let en = L10n.bundle("en")
    #expect(ResetFormatter.short(until: Date(timeIntervalSince1970: 2*3600+14*60), now: now) == "2h 14m")  // numerický, beze slov
    #expect(ResetFormatter.short(until: Date(timeIntervalSince1970: 41*60), now: now) == "41m")
    #expect(ResetFormatter.short(until: Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 100), bundle: cs) == "teď")
    #expect(ResetFormatter.short(until: Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 100), bundle: en) == "now")
}

@Test func popiskyOken() {
    let cs = L10n.bundle("cs"); let en = L10n.bundle("en")
    #expect(WindowLabel.text(for: .rolling5h, bundle: cs) == "Relace")
    #expect(WindowLabel.text(for: .weekly(scope: nil), bundle: cs) == "Týden")
    #expect(WindowLabel.text(for: .weekly(scope: "Sonnet"), bundle: cs) == "Sonnet")
    #expect(WindowLabel.text(for: .rolling5h, bundle: en) == "Session")
    #expect(WindowLabel.text(for: .weekly(scope: nil), bundle: en) == "Weekly")
    #expect(WindowLabel.text(for: .weekly(scope: "Sonnet"), bundle: en) == "Sonnet")
}
