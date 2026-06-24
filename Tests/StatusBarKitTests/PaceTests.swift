import Testing
import Foundation
@testable import StatusBarKit

private let now = Date(timeIntervalSince1970: 1_000_000)

@Test func paceTýdenPozadu() {
    // reset za 3.5 dne → start před 3.5 dne → uplynulo 50 %; vyčerpáno 30 % → -20
    let w = UsageWindow(kind: .weekly(scope: nil), usedFraction: 0.30, resetAt: now.addingTimeInterval(3.5*86400))
    #expect(PaceCalculator.pace(window: w, now: now) == -20)
}
@Test func paceTýdenNapřed() {
    let w = UsageWindow(kind: .weekly(scope: nil), usedFraction: 0.70, resetAt: now.addingTimeInterval(3.5*86400))
    #expect(PaceCalculator.pace(window: w, now: now) == 20)
}
@Test func pace5hOkno() {
    // reset za 2.5h → uplynulo 50 %; vyčerpáno 50 % → 0
    let w = UsageWindow(kind: .rolling5h, usedFraction: 0.50, resetAt: now.addingTimeInterval(2.5*3600))
    #expect(PaceCalculator.pace(window: w, now: now) == 0)
}
@Test func paceNilBezResetu() {
    #expect(PaceCalculator.pace(window: UsageWindow(kind: .rolling5h, usedFraction: 0.5, resetAt: nil), now: now) == nil)
}
@Test func paceNilResetVMinulosti() {
    let w = UsageWindow(kind: .weekly(scope: nil), usedFraction: 0.5, resetAt: now.addingTimeInterval(-3600))
    #expect(PaceCalculator.pace(window: w, now: now) == nil)
}
@Test func paceLabelTexty() {
    #expect(PaceLabel.text(deltaPercent: 20) == "napřed o 20 %")
    #expect(PaceLabel.text(deltaPercent: -42) == "pozadu o 42 %")
    #expect(PaceLabel.text(deltaPercent: 0) == "v tempu")
}
