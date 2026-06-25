import Testing
import Foundation
@testable import StatusBarKit

@Test func burnLabelProjectedEnCs() {
    // projekce vyčerpání 85 % → ZBÝVÁ 15 % (konzistentní s „% left")
    let p = BurnProjection(projectedFractionAtReset: 0.85, timeToExhaustion: nil)
    #expect(BurnRateLabel.text(p, bundle: L10n.bundle("en")).contains("15"))
    #expect(BurnRateLabel.text(p, bundle: L10n.bundle("en")).contains("left"))
    #expect(BurnRateLabel.text(p, bundle: L10n.bundle("cs")).contains("zbyde"))
    // literální % se vykreslí jednou
    #expect(BurnRateLabel.text(p, bundle: L10n.bundle("en")).contains("%"))
    #expect(!BurnRateLabel.text(p, bundle: L10n.bundle("en")).contains("%%"))
}

@Test func burnLabelExhaustEnCs() {
    let p = BurnProjection(projectedFractionAtReset: 2.5, timeToExhaustion: 3600 + 20*60) // 1h 20m
    let en = BurnRateLabel.text(p, bundle: L10n.bundle("en"))
    let cs = BurnRateLabel.text(p, bundle: L10n.bundle("cs"))
    #expect(en.contains("1h 20m"))
    #expect(en.contains("limit in"))
    #expect(cs.contains("limit ~za"))
    #expect(cs.contains("1h 20m"))
}

@Test func burnLabelReached() {
    let p = BurnProjection(projectedFractionAtReset: 1.2, timeToExhaustion: 0)
    #expect(BurnRateLabel.text(p, bundle: L10n.bundle("en")) == "limit reached")
    #expect(BurnRateLabel.text(p, bundle: L10n.bundle("cs")) == "limit vyčerpán")
}

@Test func burnLabelDuration() {
    // dny
    let pd = BurnProjection(projectedFractionAtReset: 1.5, timeToExhaustion: 2*86400 + 5*3600)
    #expect(BurnRateLabel.text(pd, bundle: L10n.bundle("en")).contains("2d 5h"))
    // jen minuty
    let pm = BurnProjection(projectedFractionAtReset: 3.0, timeToExhaustion: 90)
    #expect(BurnRateLabel.text(pm, bundle: L10n.bundle("en")).contains("1m"))
}
