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

@Test func claudeScannerVyhodíNulovéModely() throws {
    // Reálná data obsahují placeholder model "<synthetic>" s 0 tokeny — nesmí se objevit v rozpadu.
    let cal = Calendar.current
    var comps = DateComponents(); comps.year = 2026; comps.month = 6; comps.day = 23; comps.hour = 12
    let now = cal.date(from: comps)!
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let ts = iso.string(from: now)

    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("claudeScanSynthetic-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let file = tmp.appendingPathComponent("session.jsonl")
    let jsonl = """
    {"type":"assistant","timestamp":"\(ts)","message":{"model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
    {"type":"assistant","timestamp":"\(ts)","message":{"model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
    """
    try jsonl.data(using: .utf8)!.write(to: file)
    try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)

    let t = try #require(ClaudeTokenScanner(projectsDir: tmp).todayUsage(now: now))
    #expect(t.perModel.map(\.modelName) == ["claude-opus-4-8"])   // "<synthetic>" vyfiltrován
}

@Test func claudeRangeUsageSečteVíceDnů() throws {
    let cal = Calendar.current
    var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 20; c.hour = 12
    let day20 = cal.date(from: c)!
    let day10 = cal.date(byAdding: .day, value: -10, to: day20)!   // v rozsahu
    let day40 = cal.date(byAdding: .day, value: -40, to: day20)!   // mimo rozsah (>30 dní)
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("claudeRange-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    // soubor v rozsahu (mtime = day10, řádky day10)
    let f1 = tmp.appendingPathComponent("a.jsonl")
    try """
    {"type":"assistant","timestamp":"\(iso.string(from: day10))","message":{"model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":9999}}}
    """.data(using: .utf8)!.write(to: f1)
    try FileManager.default.setAttributes([.modificationDate: day10], ofItemAtPath: f1.path)

    // soubor mimo rozsah (mtime = day40) — nesmí se započítat (mtime < start)
    let f2 = tmp.appendingPathComponent("b.jsonl")
    try """
    {"type":"assistant","timestamp":"\(iso.string(from: day40))","message":{"model":"claude-opus-4-8","usage":{"input_tokens":777,"output_tokens":777,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
    """.data(using: .utf8)!.write(to: f2)
    try FileManager.default.setAttributes([.modificationDate: day40], ofItemAtPath: f2.path)

    let start = cal.date(byAdding: .day, value: -30, to: day20)!
    let r = try #require(ClaudeTokenScanner(projectsDir: tmp).rangeUsage(start: start, end: day20))
    #expect(r.total.realTokens == 150)            // jen f1 (100+50); f2 mimo rozsah; cache se do realTokens nepočítá
    #expect(r.estimatedCost > 0)
}

@Test func claudeRangeUsageFiltrujeŘádkyMimoOkno() throws {
    // soubor má mtime v rozsahu, ale obsahuje řádek STARŠÍ než start → parser ho odfiltruje
    let cal = Calendar.current
    var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 20; c.hour = 12
    let day20 = cal.date(from: c)!
    let start = cal.date(byAdding: .day, value: -30, to: day20)!
    let inWindow = cal.date(byAdding: .day, value: -5, to: day20)!
    let beforeWindow = cal.date(byAdding: .day, value: -35, to: day20)!
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("claudeRange2-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let f = tmp.appendingPathComponent("a.jsonl")
    try """
    {"type":"assistant","timestamp":"\(iso.string(from: inWindow))","message":{"model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
    {"type":"assistant","timestamp":"\(iso.string(from: beforeWindow))","message":{"model":"claude-opus-4-8","usage":{"input_tokens":555,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
    """.data(using: .utf8)!.write(to: f)
    try FileManager.default.setAttributes([.modificationDate: inWindow], ofItemAtPath: f.path)

    let r = try #require(ClaudeTokenScanner(projectsDir: tmp).rangeUsage(start: start, end: day20))
    #expect(r.total.realTokens == 100)            // řádek beforeWindow (555) odfiltrován parserem
}

@Test func claudeRangeUsageMergePřesVíceSouborů() throws {
    let cal = Calendar.current
    var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 20; c.hour = 12
    let day = cal.date(from: c)!
    let start = cal.date(byAdding: .day, value: -30, to: day)!
    let inWindow = cal.date(byAdding: .day, value: -5, to: day)!
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("claudeMerge-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    // 5 souborů, každý 100 input + 50 output stejného modelu → součet 500/250
    for n in 0..<5 {
        let f = tmp.appendingPathComponent("s\(n).jsonl")
        try """
        {"type":"assistant","timestamp":"\(iso.string(from: inWindow))","message":{"model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """.data(using: .utf8)!.write(to: f)
        try FileManager.default.setAttributes([.modificationDate: inWindow], ofItemAtPath: f.path)
    }
    let r = try #require(ClaudeTokenScanner(projectsDir: tmp).rangeUsage(start: start, end: day))
    #expect(r.perModel.count == 1)
    #expect(r.total.realTokens == 750)   // 5 × (100+50) — paralelní merge musí sečíst vše
}
