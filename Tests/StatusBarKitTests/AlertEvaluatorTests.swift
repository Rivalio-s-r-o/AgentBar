import Testing
import Foundation
@testable import StatusBarKit

private func usage(_ id: ProviderID, _ name: String, _ status: ProviderStatus, _ used: [Double]) -> ProviderUsage {
    ProviderUsage(providerId: id, displayName: name, planLabel: nil,
        windows: used.map { UsageWindow(kind: .rolling5h, usedFraction: $0, resetAt: nil) },
        status: status, lastUpdated: Date())
}

@Test func přechodPodPrahPálíJednou() {
    let u = [usage(.claudeCode, "Claude Code", .ok, [0.92])]   // remaining 8 ≤ 10
    let (fire, state) = AlertEvaluator.evaluate(usages: u, thresholdPercent: 10, alreadyAlerted: [])
    #expect(fire.count == 1)
    #expect(fire[0].remainingPercent == 8)
    #expect(state.contains(AlertKey(providerId: .claudeCode, window: .rolling5h)))
    // setrvání pod prahem se stejným stavem → žádný re-fire
    let (fire2, state2) = AlertEvaluator.evaluate(usages: u, thresholdPercent: 10, alreadyAlerted: state)
    #expect(fire2.isEmpty)
    #expect(state2 == state)
}

@Test func zotaveníNadPrahRearm() {
    let key = AlertKey(providerId: .claudeCode, window: .rolling5h)
    let recovered = [usage(.claudeCode, "Claude Code", .ok, [0.50])]   // remaining 50 > 10
    let (fire, state) = AlertEvaluator.evaluate(usages: recovered, thresholdPercent: 10, alreadyAlerted: [key])
    #expect(fire.isEmpty)
    #expect(!state.contains(key))   // odbito → příště zase upozorní
    // opětovný přechod po rearmu → fire znovu
    let low = [usage(.claudeCode, "Claude Code", .ok, [0.95])]
    let (fire2, _) = AlertEvaluator.evaluate(usages: low, thresholdPercent: 10, alreadyAlerted: state)
    #expect(fire2.count == 1)
}

@Test func hraniceRovnostPálí() {
    let u = [usage(.codex, "Codex", .ok, [0.90])]   // remaining 10 == threshold → ≤ → fire
    let (fire, _) = AlertEvaluator.evaluate(usages: u, thresholdPercent: 10, alreadyAlerted: [])
    #expect(fire.count == 1)
    #expect(fire[0].remainingPercent == 10)
}

@Test func degradedAUnavailableSeIgnorují() {
    let u = [
        usage(.claudeCode, "Claude Code", .degraded("stará"), [0.99]),
        usage(.codex, "Codex", .unavailable("nic"), [0.99]),
    ]
    let (fire, state) = AlertEvaluator.evaluate(usages: u, thresholdPercent: 10, alreadyAlerted: [])
    #expect(fire.isEmpty)
    #expect(state.isEmpty)
}

@Test func víceOkenNezávisle() {
    let u = ProviderUsage(providerId: .claudeCode, displayName: "Claude Code", planLabel: nil,
        windows: [
            UsageWindow(kind: .rolling5h, usedFraction: 0.95, resetAt: nil),         // remaining 5 ≤ 10 → fire
            UsageWindow(kind: .weekly(scope: nil), usedFraction: 0.40, resetAt: nil) // remaining 60 → ne
        ], status: .ok, lastUpdated: Date())
    let (fire, state) = AlertEvaluator.evaluate(usages: [u], thresholdPercent: 10, alreadyAlerted: [])
    #expect(fire.count == 1)
    #expect(state == [AlertKey(providerId: .claudeCode, window: .rolling5h)])
}
