import Testing
import Foundation
@testable import StatusBarKit

@Test func apiParserVytvoříOkna() throws {
    let url = Bundle.module.url(forResource: "claude-api-usage", withExtension: "json", subdirectory: "Fixtures")!
    let w = try ClaudeUsageCacheParser.parseAPIWindows(Data(contentsOf: url))
    #expect(w.count == 3)
    #expect(w.contains { $0.kind == .rolling5h && abs($0.usedFraction - 0.13) < 0.0001 })
    #expect(w.contains { $0.kind == .weekly(scope: nil) && abs($0.usedFraction - 0.08) < 0.0001 })
    #expect(w.contains { $0.kind == .weekly(scope: "Sonnet") })
}

@Test func plánLabelMapování() {
    #expect(ClaudePlan.label(forSubscriptionType: "max") == "Max")
    #expect(ClaudePlan.label(forSubscriptionType: "pro") == "Pro")
    #expect(ClaudePlan.label(forSubscriptionType: "free") == "Free")
    #expect(ClaudePlan.label(forSubscriptionType: nil) == nil)
    #expect(ClaudePlan.label(forSubscriptionType: "") == nil)
    #expect(ClaudePlan.label(forSubscriptionType: "custom") == "Custom")
}
