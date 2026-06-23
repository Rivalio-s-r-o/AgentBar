import Testing
import Foundation
@testable import StatusBarKit

private func fx(_ n: String) throws -> Data {
    try Data(contentsOf: Bundle.module.url(forResource: n, withExtension: "jsonl", subdirectory: "Fixtures")!)
}

@Test func parserVezmePosledníUdálostAMapujePodleWindowMinutes() throws {
    let snap = CodexRateLimitParser.latestSnapshot(fromJSONL: try fx("codex-session-with-limits"))
    #expect(snap != nil)
    #expect(snap?.planType == "plus")

    // poslední událost: primary 83 % (300 min => 5h), secondary 14 % (10080 => týden)
    let five = snap?.windows.first { $0.kind == .rolling5h }
    #expect(abs((five?.usedFraction ?? -1) - 0.83) < 0.0001)
    // resets_at je absolutní epoch 1776353068
    #expect(abs((five?.resetAt?.timeIntervalSince1970 ?? 0) - 1776353068) < 0.5)

    let week = snap?.windows.first { $0.kind == .weekly(scope: nil) }
    #expect(abs((week?.usedFraction ?? -1) - 0.14) < 0.0001)
}

@Test func parserBezLimitůVrátíNil() throws {
    #expect(CodexRateLimitParser.latestSnapshot(fromJSONL: try fx("codex-session-null-limits")) == nil)
}

@Test func prefiltrPřeskočíŘádkyBezRateLimits() {
    // Noisy line without "rate_limits" must be skipped; only the token_count line should be decoded.
    let noisy = #"{"type":"event_msg","payload":{"type":"message","content":"hello world, this is a long assistant message without the magic bytes"}}"#
    let valid = #"{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":42.0,"window_minutes":300,"resets_at":1776353068},"secondary":null,"plan_type":"pro"}}}"#
    let jsonl = Data((noisy + "\n" + valid).utf8)
    let snap = CodexRateLimitParser.latestSnapshot(fromJSONL: jsonl)
    #expect(snap != nil)
    let five = snap?.windows.first { $0.kind == .rolling5h }
    #expect(abs((five?.usedFraction ?? -1) - 0.42) < 0.0001)
}
