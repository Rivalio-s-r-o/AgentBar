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

    let u = await CodexCollector(sessionsDir: root, staleAfter: .greatestFiniteMagnitude, maxFilesToScan: 10).fetch()
    #expect(u.windows.contains { $0.kind == .rolling5h })
    #expect(u.planLabel == "plus")
}

@Test func collectorBezSessionUnavailable() async {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cx-empty-\(UUID().uuidString)")
    let u = await CodexCollector(sessionsDir: root, staleAfter: 999, maxFilesToScan: 10).fetch()
    if case .unavailable = u.status {} else { Issue.record("čekán .unavailable") }
}
