import Testing
import Foundation
@testable import StatusBarKit

private func usage(_ kind: WindowKind, used: Double, resetIn: TimeInterval, now: Date) -> ProviderUsage {
    ProviderUsage(providerId: .claudeCode, displayName: "C", planLabel: nil,
                  windows: [UsageWindow(kind: kind, usedFraction: used, resetAt: now.addingTimeInterval(resetIn))],
                  status: .ok, lastUpdated: now)
}

@Test func burnBarProjekce() {
    let now = Date()
    // 5h, uplynula 1h (20 %), used 0.5 → projected 2.5 → clamp 1.0, overLimit, red
    let p = usage(.rolling5h, used: 0.5, resetIn: 4*3600, now: now)
    let b = BurnBarBuilder.bar(for: p, source: .auto, now: now)!
    #expect(b.used == 0.5)
    #expect(b.projected == 1.0)        // clamp na 1.0
    #expect(b.overLimit == true)
    #expect(b.projectedLevel == .critical)
    #expect(b.usedLevel == .normal)
}

@Test func burnBarMirnaProjekce() {
    let now = Date()
    // 5h, uplynulo 50 %, used 0.25 → projected 0.5, neexhausting, green
    let p = usage(.rolling5h, used: 0.25, resetIn: 2.5*3600, now: now)
    let b = BurnBarBuilder.bar(for: p, source: .auto, now: now)!
    #expect(b.used == 0.25)
    #expect(abs(b.projected - 0.5) < 0.001)
    #expect(b.overLimit == false)
    #expect(b.projectedLevel == .normal)
    #expect(b.usedLevel == .normal)
}

@Test func burnBarBezProjekce() {
    let now = Date()
    // příliš brzy (elapsedFraction < 0.02) → projekce nil → projected == used
    let p = usage(.rolling5h, used: 0.1, resetIn: 5*3600 - 60, now: now)
    let b = BurnBarBuilder.bar(for: p, source: .auto, now: now)!
    #expect(b.projected == b.used)
    #expect(b.overLimit == false)
}

@Test func burnBarNilBezOkna() {
    let now = Date()
    let p = ProviderUsage(providerId: .codex, displayName: "X", planLabel: nil,
                          windows: [], status: .ok, lastUpdated: now)
    #expect(BurnBarBuilder.bar(for: p, source: .auto, now: now) == nil)
}

@Test func burnBarUsedClamp() {
    let now = Date()
    let p = usage(.rolling5h, used: 1.2, resetIn: 3600, now: now)   // přes 100 %
    let b = BurnBarBuilder.bar(for: p, source: .auto, now: now)!
    #expect(b.used == 1.0)             // clamp
    #expect(b.projectedLevel == .critical)
    #expect(b.usedLevel == .critical)
}
