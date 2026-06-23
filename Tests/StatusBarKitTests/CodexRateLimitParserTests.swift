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
