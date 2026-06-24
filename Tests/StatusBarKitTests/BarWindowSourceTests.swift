import Testing
import Foundation
@testable import StatusBarKit

private func usage(session: Double?, weekly: Double?) -> ProviderUsage {
    var w: [UsageWindow] = []
    if let s = session { w.append(UsageWindow(kind: .rolling5h, usedFraction: s, resetAt: nil)) }
    if let wk = weekly { w.append(UsageWindow(kind: .weekly(scope: nil), usedFraction: wk, resetAt: nil)) }
    return ProviderUsage(providerId: .claudeCode, displayName: "Claude Code", planLabel: nil,
        windows: w, status: .ok, lastUpdated: Date())
}

@Test func usedPercentVybíráOkno() {
    let u = usage(session: 0.20, weekly: 0.80)
    #expect(u.usedPercent(for: .session) == 20)
    #expect(u.usedPercent(for: .weekly) == 80)
    #expect(u.usedPercent(for: .auto) == 80)              // nearest = max
}

@Test func usedPercentFallbackKdyžOknoChybí() {
    let jenSession = usage(session: 0.30, weekly: nil)
    #expect(jenSession.usedPercent(for: .weekly) == 30)   // chybí weekly → nearest (30)
    let jenWeekly = usage(session: nil, weekly: 0.55)
    #expect(jenWeekly.usedPercent(for: .session) == 55)   // chybí session → nearest (55)
}

@Test func usedPercentWeeklyPreferujeCelkové() {
    // F2: weekly_all (scope nil) = 40 %, scoped „Sonnet" = 90 % → .weekly bere CELKOVÉ (40), ne scoped
    let u = ProviderUsage(providerId: .claudeCode, displayName: "Claude Code", planLabel: nil,
        windows: [
            UsageWindow(kind: .rolling5h, usedFraction: 0.10, resetAt: nil),
            UsageWindow(kind: .weekly(scope: nil), usedFraction: 0.40, resetAt: nil),
            UsageWindow(kind: .weekly(scope: "Sonnet"), usedFraction: 0.90, resetAt: nil),
        ], status: .ok, lastUpdated: Date())
    #expect(u.usedPercent(for: .weekly) == 40)            // celkové týdenní, ne scoped 90
    #expect(u.usedPercent(for: .auto) == 90)              // auto = nearest = nejhorší (90)
}

@Test func segmentsSourceVybíráČísloIBarvu() {
    let u = usage(session: 0.05, weekly: 0.95)             // session bezpečné, weekly kritické
    let sSession = MenuBarTitleBuilder.segments(for: [u], style: .dotPercent, showUsedPercent: true, source: .session)
    #expect(sSession[0].text == "5%")
    #expect(sSession[0].level == .normal)
    let sWeekly = MenuBarTitleBuilder.segments(for: [u], style: .dotPercent, showUsedPercent: true, source: .weekly)
    #expect(sWeekly[0].text == "95%")
    #expect(sWeekly[0].level == .critical)
    let sAuto = MenuBarTitleBuilder.segments(for: [u], style: .dotPercent, showUsedPercent: true)  // default .auto
    #expect(sAuto[0].text == "95%")                       // auto = nearest = beze změny
}

@Test func barWindowSourceDisplayName() {
    let cs = L10n.bundle("cs"); let en = L10n.bundle("en")
    #expect(BarWindowSource.session.displayName(bundle: cs) == "Relace")
    #expect(BarWindowSource.weekly.displayName(bundle: cs) == "Týden")
    #expect(BarWindowSource.auto.displayName(bundle: cs) == "Auto")
    #expect(BarWindowSource.session.displayName(bundle: en) == "Session")
    #expect(BarWindowSource.allCases.count == 3)
}

@Test func preferenceBarWindowSourceDefaultAuto() {
    let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    let prefs = PreferencesStore(defaults: suite)
    #expect(prefs.barWindowSource == .auto)               // default
    prefs.barWindowSource = .weekly
    #expect(prefs.barWindowSource == .weekly)
}
