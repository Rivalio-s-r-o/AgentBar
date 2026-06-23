import Testing
import Foundation
@testable import StatusBarKit

private func fixture(_ n: String) throws -> Data {
    try Data(contentsOf: Bundle.module.url(forResource: n, withExtension: "json", subdirectory: "Fixtures")!)
}

@Test func parseClaudeLimitsVytvoříOkna() throws {
    let u = try ClaudeUsageCacheParser.parse(fixture("claude-usage-cache"))
    #expect(u.providerId == .claudeCode)
    #expect(u.status == .ok)

    let five = u.windows.first { $0.kind == .rolling5h }
    #expect(abs((five?.usedFraction ?? -1) - 0.08) < 0.0001)
    #expect(five?.resetAt != nil)

    let weekAll = u.windows.first { $0.kind == .weekly(scope: nil) }
    #expect(abs((weekAll?.usedFraction ?? -1) - 0.02) < 0.0001)

    let weekSonnet = u.windows.first { $0.kind == .weekly(scope: "Sonnet") }
    #expect(abs((weekSonnet?.usedFraction ?? -1) - 0.12) < 0.0001)

    #expect(abs(u.lastUpdated.timeIntervalSince1970 - 1782223012.474268) < 0.001)
}

@Test func parseClaudeChybnýJSONHodí() {
    #expect(throws: (any Error).self) { _ = try ClaudeUsageCacheParser.parse(Data("nonsense".utf8)) }
}
