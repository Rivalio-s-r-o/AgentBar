import Testing
import Foundation
@testable import StatusBarKit

private func copyFixtureToTemp(now: Date) throws -> URL {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cc-\(UUID().uuidString).json")
    let src = Bundle.module.url(forResource: "claude-usage-cache", withExtension: "json", subdirectory: "Fixtures")!
    try FileManager.default.copyItem(at: src, to: tmp)
    return tmp
}

@Test func collectorPřečteCache() async throws {
    let tmp = try copyFixtureToTemp(now: Date())
    defer { try? FileManager.default.removeItem(at: tmp) }
    // staleAfter obrovský => i stará fixtura je ok
    let u = await ClaudeCodeCollector(cachePath: tmp, staleAfter: .greatestFiniteMagnitude).fetch()
    #expect(u.status == .ok)
    #expect(u.windows.isEmpty == false)
}

@Test func collectorStaráCacheJeDegraded() async throws {  // H5
    let tmp = try copyFixtureToTemp(now: Date())
    defer { try? FileManager.default.removeItem(at: tmp) }
    // fixtura má timestamp z minulosti => staleAfter 1 s => degraded
    let u = await ClaudeCodeCollector(cachePath: tmp, staleAfter: 1).fetch()
    if case .degraded = u.status {} else { Issue.record("čekán .degraded, byl \(u.status)") }
}

@Test func collectorChybějícíSouborUnavailable() async {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).json")
    let u = await ClaudeCodeCollector(cachePath: missing, staleAfter: 999).fetch()
    if case .unavailable = u.status {} else { Issue.record("čekán .unavailable") }
}
