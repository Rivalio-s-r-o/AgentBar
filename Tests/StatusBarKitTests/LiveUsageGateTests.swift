import Testing
import Foundation
@testable import StatusBarKit

private let p = LiveUsagePolicy()   // 300 / 900
private let t0 = Date(timeIntervalSince1970: 1_000_000)

@Test func gateIniciálněPovolí() {
    #expect(LiveGateState().shouldFetch(now: t0, policy: p) == true)
}

@Test func gatePoÚspěchuThrottluje() {
    let s = LiveGateState().after(signal: .success, now: t0, policy: p)
    #expect(s.shouldFetch(now: t0.addingTimeInterval(299), policy: p) == false)  // v rámci minInterval
    #expect(s.shouldFetch(now: t0.addingTimeInterval(300), policy: p) == true)   // přesně minInterval → povolí
    #expect(s.cooldownUntil == nil)
}

@Test func gatePo429Backoff() {
    let s = LiveGateState().after(signal: .rateLimited, now: t0, policy: p)
    #expect(s.cooldownUntil == t0.addingTimeInterval(900))
    #expect(s.shouldFetch(now: t0.addingTimeInterval(500), policy: p) == false)  // v cooldownu
    #expect(s.shouldFetch(now: t0.addingTimeInterval(900), policy: p) == true)   // cooldown vypršel + >minInterval
}

@Test func gatePoFailedJenThrottle() {
    let s = LiveGateState().after(signal: .failed, now: t0, policy: p)
    #expect(s.cooldownUntil == nil)
    #expect(s.shouldFetch(now: t0.addingTimeInterval(100), policy: p) == false)  // jen throttle
    #expect(s.shouldFetch(now: t0.addingTimeInterval(301), policy: p) == true)
}

@Test func gateÚspěchPo429ZrušíCooldown() {
    let s1 = LiveGateState().after(signal: .rateLimited, now: t0, policy: p)
    let s2 = s1.after(signal: .success, now: t0.addingTimeInterval(900), policy: p)
    #expect(s2.cooldownUntil == nil)
}

@Test func politikaVlastníHodnoty() {
    let custom = LiveUsagePolicy(minInterval: 60, cooldown: 120)
    let s = LiveGateState().after(signal: .rateLimited, now: t0, policy: custom)
    #expect(s.cooldownUntil == t0.addingTimeInterval(120))
}
