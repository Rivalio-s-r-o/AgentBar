import Testing
import Foundation
@testable import StatusBarKit

@Test func barForWindowProjekce() {
    let now = Date()
    let w = UsageWindow(kind: .rolling5h, usedFraction: 0.5, resetAt: now.addingTimeInterval(4*3600))
    let b = BurnBarBuilder.bar(forWindow: w, now: now)
    #expect(b.used == 0.5)
    #expect(b.projected == 1.0)   // proj 2.5 → clamp 1.0
    #expect(b.overLimit == true)
    #expect(b.projectedLevel == .critical)
    #expect(b.usedLevel == .normal)
}

@Test func barForWindowOddeleneBarvy() {
    let now = Date()
    // Weekly: used 29 % (zelená), ale rychlé tempo → projekce přes limit (červená)
    // 7d okno, uplynulo ~27 % (122h55m zbývá z 168h), used 0.29 → proj ~108 % overLimit
    let w = UsageWindow(kind: .weekly(scope: nil), usedFraction: 0.29, resetAt: now.addingTimeInterval(122.92*3600))
    let b = BurnBarBuilder.bar(forWindow: w, now: now)
    #expect(b.usedLevel == .normal)        // teď 29 % = zelená
    #expect(b.projectedLevel == .critical) // projekce přes limit = červená
    #expect(b.overLimit == true)
}

@Test func barForWindowBezProjekce() {
    let now = Date()
    let w = UsageWindow(kind: .weekly(scope: nil), usedFraction: 0.3, resetAt: nil)  // reset nil → bez projekce
    let b = BurnBarBuilder.bar(forWindow: w, now: now)
    #expect(b.used == 0.3)
    #expect(b.projected == 0.3)
    #expect(b.overLimit == false)
}

@Test func barForSourceDeleguje() {
    let now = Date()
    let u = ProviderUsage(providerId: .claudeCode, displayName: "C", planLabel: nil,
        windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.25, resetAt: now.addingTimeInterval(2.5*3600))],
        status: .ok, lastUpdated: now)
    let viaSource = BurnBarBuilder.bar(for: u, source: .auto, now: now)
    let viaWindow = BurnBarBuilder.bar(forWindow: u.windows[0], now: now)
    #expect(viaSource == viaWindow)   // delegace → stejný výsledek
}
