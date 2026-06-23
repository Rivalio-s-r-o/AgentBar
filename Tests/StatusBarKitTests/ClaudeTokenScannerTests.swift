import Testing
import Foundation
@testable import StatusBarKit

@Test func claudeScannerJenDnešníZTempAdresáře() throws {
    let cal = Calendar.current
    var comps = DateComponents(); comps.year = 2026; comps.month = 6; comps.day = 23; comps.hour = 12
    let now = cal.date(from: comps)!
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let tsDnes = iso.string(from: now)
    let tsVčera = iso.string(from: cal.date(byAdding: .day, value: -1, to: now)!)

    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("claudeScan-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let file = tmp.appendingPathComponent("session.jsonl")
    let jsonl = """
    {"type":"assistant","timestamp":"\(tsDnes)","message":{"model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":10,"cache_read_input_tokens":1000}}}
    {"type":"assistant","timestamp":"\(tsVčera)","message":{"model":"claude-opus-4-8","usage":{"input_tokens":999,"output_tokens":999,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
    """
    try jsonl.data(using: .utf8)!.write(to: file)
    try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)

    let today = ClaudeTokenScanner(projectsDir: tmp).todayUsage(now: now)
    let t = try #require(today)                       // nesmí být nil (jinak F1-styl tichý výpadek)
    #expect(t.perModel.count == 1)
    #expect(t.perModel.first?.modelName == "claude-opus-4-8")
    #expect(t.perModel.first?.tokens == TokenUsage(input: 100, output: 50, cacheWrite: 10, cacheRead: 1000))
    #expect(t.estimatedCost > 0)
}
