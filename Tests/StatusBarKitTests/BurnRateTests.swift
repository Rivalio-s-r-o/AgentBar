import Testing
import Foundation
@testable import StatusBarKit

private func win(_ kind: WindowKind, used: Double, resetIn: TimeInterval, now: Date) -> UsageWindow {
    UsageWindow(kind: kind, usedFraction: used, resetAt: now.addingTimeInterval(resetIn))
}

@Test func burnProjectedAExhausting() {
    let now = Date()
    // 5h okno, uplynula 1h (20 %), vyčerpáno 50 % → tempo 2.5× → projected 250 %, exhausting
    let w = win(.rolling5h, used: 0.5, resetIn: 4*3600, now: now)
    let p = BurnRateCalculator.project(window: w, now: now)!
    #expect(abs(p.projectedFractionAtReset - 2.5) < 0.001)
    #expect(p.timeToExhaustion != nil)
    #expect(p.timeToExhaustion! < w.resetAt!.timeIntervalSince(now))
    #expect(abs(p.timeToExhaustion! - 3600) < 1)   // zbývá 0.5 frakce při rate 0.5/3600 → 1h
}

@Test func burnNeexhausting() {
    let now = Date()
    let w = win(.rolling5h, used: 0.25, resetIn: 2.5*3600, now: now)   // 50 % uplynulo, 25 % použito
    let p = BurnRateCalculator.project(window: w, now: now)!
    #expect(abs(p.projectedFractionAtReset - 0.5) < 0.001)
    #expect(p.timeToExhaustion == nil)
}

@Test func burnLimitJizDosazen() {
    let now = Date()
    let w = win(.rolling5h, used: 1.05, resetIn: 3600, now: now)
    let p = BurnRateCalculator.project(window: w, now: now)!
    #expect(p.timeToExhaustion == 0)
}

@Test func burnPrilisBrzyNil() {
    let now = Date()
    // elapsed 60s z 18000 = 0.0033 < 0.02
    let w = win(.rolling5h, used: 0.01, resetIn: 5*3600 - 60, now: now)
    #expect(BurnRateCalculator.project(window: w, now: now) == nil)
}

@Test func burnResetVMinulostiNil() {
    let now = Date()
    let w = win(.rolling5h, used: 0.5, resetIn: -100, now: now)
    #expect(BurnRateCalculator.project(window: w, now: now) == nil)
}

@Test func burnResetNilNil() {
    let now = Date()
    let w = UsageWindow(kind: .rolling5h, usedFraction: 0.5, resetAt: nil)
    #expect(BurnRateCalculator.project(window: w, now: now) == nil)
}

@Test func burnWeeklyDny() {
    let now = Date()
    // weekly, zbývají 4 dny (uplynuly 3 → ~43 %), vyčerpáno 80 % → exhausting, tte v dnech/hodinách
    let w = win(.weekly(scope: nil), used: 0.8, resetIn: 4*86400, now: now)
    let p = BurnRateCalculator.project(window: w, now: now)!
    #expect(p.timeToExhaustion != nil)
    #expect(p.timeToExhaustion! < w.resetAt!.timeIntervalSince(now))
}
