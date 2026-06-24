import Testing
import Foundation
@testable import StatusBarKit

private func place(_ fixture: String, into dir: URL, sub: String, mtime: Date) throws {
    let dest = dir.appendingPathComponent(sub)
    try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
    let src = Bundle.module.url(forResource: fixture, withExtension: "jsonl", subdirectory: "Fixtures")!
    try FileManager.default.copyItem(at: src, to: dest)
    try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: dest.path)
}

@Test func collectorPřeskočíNejnovějšíNullSessionAVezmeStarší() async throws {  // C3
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cx-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    // novější soubor = null limity; starší = platná data
    try place("codex-session-with-limits", into: root, sub: "a/older.jsonl", mtime: Date(timeIntervalSince1970: 1000))
    try place("codex-session-null-limits", into: root, sub: "a/newer.jsonl", mtime: Date(timeIntervalSince1970: 2000))

    let u = await CodexCollector(sessionsDir: root, staleAfter: .greatestFiniteMagnitude, maxFilesToScan: 10).fetch(includeToday: false)
    #expect(u.windows.contains { $0.kind == .rolling5h })
    #expect(u.planLabel == "Plus")
}

@Test func collectorBezSessionUnavailable() async {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cx-empty-\(UUID().uuidString)")
    let u = await CodexCollector(sessionsDir: root, staleAfter: 999, maxFilesToScan: 10).fetch(includeToday: false)
    if case .unavailable = u.status {} else { Issue.record("čekán .unavailable") }
}

private struct FakeCodexSource: CodexUsageSource {
    let live: CodexLiveUsage?
    func fetchFresh() async -> CodexLiveUsage? { live }
}

@Test func codexCollectorPoužijeŽivýZdroj() async {
    let when = Date(timeIntervalSince1970: 1_700_000_000)
    let live = CodexLiveUsage(snapshot: CodexSnapshot(windows: [UsageWindow(kind: .rolling5h, usedFraction: 0.05, resetAt: nil)], planType: "plus"), fetchedAt: when)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cx-live-\(UUID().uuidString)")
    let u = await CodexCollector(sessionsDir: root, liveSource: FakeCodexSource(live: live)).fetch(includeToday: false)
    if case .ok = u.status {} else { Issue.record("čekán .ok z živého zdroje") }
    #expect(u.planLabel == "Plus")          // CodexPlan.label aplikován v collectoru
    #expect(u.windows.count == 1)
    #expect(u.windows.first?.kind == .rolling5h)
    #expect(u.lastUpdated == when)
}

@Test func codexCollectorFallbackNaJSONLKdyžŽivýNil() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cx-fb-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try place("codex-session-with-limits", into: root, sub: "a/s.jsonl", mtime: Date(timeIntervalSince1970: 1000))
    let u = await CodexCollector(sessionsDir: root, staleAfter: .greatestFiniteMagnitude,
                                 liveSource: FakeCodexSource(live: nil)).fetch(includeToday: false)
    #expect(u.windows.contains { $0.kind == .rolling5h })
    #expect(u.planLabel == "Plus")          // retrofit: "plus" → "Plus"
}
