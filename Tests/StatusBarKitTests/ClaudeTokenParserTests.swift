import Testing
import Foundation
@testable import StatusBarKit

@Test func sumByModelJenDnešní() throws {
    let url = Bundle.module.url(forResource: "claude-project-session", withExtension: "jsonl", subdirectory: "Fixtures")!
    let data = try Data(contentsOf: url)
    // den 2026-06-23 v UTC (fixtura má UTC timestampy)
    let iso = ISO8601DateFormatter()
    let dayStart = iso.date(from: "2026-06-23T00:00:00Z")!
    let dayEnd = iso.date(from: "2026-06-24T00:00:00Z")!
    let sums = ClaudeTokenParser.sumByModel(fromJSONL: data, dayStart: dayStart, dayEnd: dayEnd)

    // Opus: jen dnešní řádek (ne ten z 06-22)
    #expect(sums["claude-opus-4-8"] == TokenUsage(input: 100, output: 50, cacheWrite: 10, cacheRead: 1000))
    #expect(sums["claude-sonnet-4-6"] == TokenUsage(input: 20, output: 8, cacheWrite: 0, cacheRead: 5))
}
