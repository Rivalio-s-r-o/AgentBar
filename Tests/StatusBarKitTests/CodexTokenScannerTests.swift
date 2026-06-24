import Testing
import Foundation
@testable import StatusBarKit

@Test func codexScannerDnešníZTempAdresáře() throws {
    let cal = Calendar.current
    var comps = DateComponents(); comps.year = 2026; comps.month = 6; comps.day = 23; comps.hour = 12
    let now = cal.date(from: comps)!

    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("codexScan-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let file = tmp.appendingPathComponent("rollout.jsonl")
    let jsonl = """
    {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":400,"output_tokens":200,"reasoning_output_tokens":50,"total_tokens":1250}}}}
    {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":3000,"cached_input_tokens":1200,"output_tokens":600,"reasoning_output_tokens":100,"total_tokens":3700}}}}
    """
    try jsonl.data(using: .utf8)!.write(to: file)
    try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)

    let today = CodexTokenScanner(sessionsDir: tmp).todayUsage(now: now)
    let t = try #require(today)
    #expect(t.perModel == [ModelTokens(modelName: "codex", tokens: TokenUsage(input: 1800, output: 700, cacheWrite: 0, cacheRead: 1200))])
    #expect(t.estimatedCost > 0)
}

@Test func codexScannerVčerejšíMtimeIgnoruje() throws {
    let cal = Calendar.current
    var comps = DateComponents(); comps.year = 2026; comps.month = 6; comps.day = 23; comps.hour = 12
    let now = cal.date(from: comps)!
    let včera = cal.date(byAdding: .day, value: -1, to: now)!
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("codexNeg-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let file = tmp.appendingPathComponent("rollout.jsonl")
    let jsonl = #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":200,"reasoning_output_tokens":0,"total_tokens":1200}}}}"#
    try jsonl.data(using: .utf8)!.write(to: file)
    try FileManager.default.setAttributes([.modificationDate: včera], ofItemAtPath: file.path)
    #expect(CodexTokenScanner(sessionsDir: tmp).todayUsage(now: now) == nil)   // mtime < dayStart → soubor přeskočen
}

@Test func codexScannerPrázdnýAdresářNil() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("codexEmpty-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let cal = Calendar.current
    var comps = DateComponents(); comps.year = 2026; comps.month = 6; comps.day = 23; comps.hour = 12
    #expect(CodexTokenScanner(sessionsDir: tmp).todayUsage(now: cal.date(from: comps)!) == nil)
}
