import Testing
import Foundation
@testable import StatusBarKit

private func copyFixtureToTemp() throws -> URL {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cc-\(UUID().uuidString).json")
    let src = Bundle.module.url(forResource: "claude-usage-cache", withExtension: "json", subdirectory: "Fixtures")!
    try FileManager.default.copyItem(at: src, to: tmp)
    return tmp
}

@Test func collectorPřečteCache() async throws {
    let tmp = try copyFixtureToTemp()
    defer { try? FileManager.default.removeItem(at: tmp) }
    // staleAfter obrovský => i stará fixtura je ok
    let u = await ClaudeCodeCollector(cachePath: tmp, staleAfter: .greatestFiniteMagnitude).fetch(includeToday: false)
    #expect(u.status == .ok)
    #expect(u.windows.isEmpty == false)
}

@Test func collectorStaráCacheJeDegraded() async throws {  // H5
    let tmp = try copyFixtureToTemp()
    defer { try? FileManager.default.removeItem(at: tmp) }
    // fixtura má timestamp z minulosti => staleAfter 1 s => degraded
    let u = await ClaudeCodeCollector(cachePath: tmp, staleAfter: 1).fetch(includeToday: false)
    if case .degraded = u.status {} else { Issue.record("čekán .degraded, byl \(u.status)") }
    #expect(u.windows.isEmpty == false)
}

@Test func collectorChybějícíSouborUnavailable() async {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).json")
    let u = await ClaudeCodeCollector(cachePath: missing, staleAfter: 999).fetch(includeToday: false)
    if case .unavailable = u.status {} else { Issue.record("čekán .unavailable") }
}

@Test func collectorIncludeTodayFalseNemáToday() async throws {
    let tmp = try copyFixtureToTemp()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let u = await ClaudeCodeCollector(cachePath: tmp, staleAfter: .greatestFiniteMagnitude).fetch(includeToday: false)
    #expect(u.today == nil)   // includeToday=false → scanner se nespustí
}

private struct FakeClaudeSource: ClaudeUsageSource {
    let usage: ClaudeLiveUsage?
    func fetchFresh() async -> ClaudeLiveUsage? { usage }
}

@Test func collectorPoužijeŽivýZdroj() async {
    let fresh = ClaudeLiveUsage(
        windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.13, resetAt: nil)], planLabel: "Max")
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("none-\(UUID().uuidString).json")
    let u = await ClaudeCodeCollector(cachePath: missing, staleAfter: 999,
        liveSource: FakeClaudeSource(usage: fresh)).fetch(includeToday: false)
    #expect(u.status == .ok)                                  // živé, ne unavailable (i když cache chybí)
    #expect(u.planLabel == "Max")
    #expect(u.windows.first?.usedFraction == 0.13)
}

@Test func collectorFallbackNaCacheKdyžŽivýNil() async throws {
    let tmp = try copyFixtureToTemp()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let u = await ClaudeCodeCollector(cachePath: tmp, staleAfter: .greatestFiniteMagnitude,
        liveSource: FakeClaudeSource(usage: nil)).fetch(includeToday: false)
    #expect(u.status == .ok)                                  // fallback na cache
    #expect(u.windows.isEmpty == false)
}

@Test func collectorPrázdnýSouborUnavailable() async throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cc-empty-\(UUID().uuidString).json")
    try Data().write(to: tmp)                       // existující 0-bajtový soubor
    defer { try? FileManager.default.removeItem(at: tmp) }
    let u = await ClaudeCodeCollector(cachePath: tmp, staleAfter: .greatestFiniteMagnitude).fetch(includeToday: false)
    if case .unavailable = u.status {} else { Issue.record("čekán .unavailable, byl \(u.status)") }
}
