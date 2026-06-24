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

@Test func apiParserHodíChybnýJSON() {
    #expect(throws: (any Error).self) { _ = try ClaudeUsageCacheParser.parseAPIWindows(Data("nonsense".utf8)) }
}

@Test func apiParserPrázdnéLimitsPrázdnéPole() throws {
    let w = try ClaudeUsageCacheParser.parseAPIWindows(Data(#"{"limits":[]}"#.utf8))
    #expect(w.isEmpty)
}

@Test func apiParserNeznámýKindIgnorován() throws {
    // kind "daily" není mapován → přeskočí; "session" zůstane
    let json = #"{"limits":[{"kind":"daily","percent":50},{"kind":"session","percent":20}]}"#
    let w = try ClaudeUsageCacheParser.parseAPIWindows(Data(json.utf8))
    #expect(w.count == 1)
    #expect(w.first?.kind == .rolling5h)
}
