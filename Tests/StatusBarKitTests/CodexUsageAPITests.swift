import Testing
import Foundation
@testable import StatusBarKit

@Test func codexAPIParserVytvoříOkna() throws {
    let url = Bundle.module.url(forResource: "codex-wham-usage", withExtension: "json", subdirectory: "Fixtures")!
    let snap = CodexUsageAPIParser.parse(try Data(contentsOf: url))
    #expect(snap != nil)
    #expect(snap?.planType == "plus")
    #expect(snap?.windows.count == 2)
    #expect(snap?.windows.contains { $0.kind == .rolling5h && abs($0.usedFraction - 0.01) < 0.0001 } == true)
    #expect(snap?.windows.contains { $0.kind == .weekly(scope: nil) && abs($0.usedFraction - 0.12) < 0.0001 } == true)
    let p = snap?.windows.first { $0.kind == .rolling5h }
    #expect(p?.resetAt == Date(timeIntervalSince1970: 1782312918))
}

@Test func codexAPIParserChybíRateLimit() {
    let data = Data(#"{"plan_type":"plus"}"#.utf8)
    #expect(CodexUsageAPIParser.parse(data) == nil)
}

@Test func codexAPIParserJenPrimary() {
    let data = Data(#"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":50,"limit_window_seconds":18000,"reset_at":111}}}"#.utf8)
    let snap = CodexUsageAPIParser.parse(data)
    #expect(snap?.windows.count == 1)
    #expect(snap?.windows.first?.kind == .rolling5h)
    #expect(snap?.planType == "pro")
}

@Test func codexAPIParserPrázdnáDataNil() {
    #expect(CodexUsageAPIParser.parse(Data("nesmysl".utf8)) == nil)
}

@Test func codexPlanLabelMapování() {
    #expect(CodexPlan.label(forPlanType: "plus") == "Plus")
    #expect(CodexPlan.label(forPlanType: "pro") == "Pro")
    #expect(CodexPlan.label(forPlanType: "free") == "Free")
    #expect(CodexPlan.label(forPlanType: nil) == nil)
    #expect(CodexPlan.label(forPlanType: "") == nil)
    #expect(CodexPlan.label(forPlanType: "business") == "Business")
}

@Test func codexAPIParserUsedPercentNilOknoNil() {
    // primary bez used_percent → okno se nevytvoří; žádné secondary → nil
    let data = Data(#"{"plan_type":"plus","rate_limit":{"primary_window":{"limit_window_seconds":18000,"reset_at":1}}}"#.utf8)
    #expect(CodexUsageAPIParser.parse(data) == nil)
}

@Test func codexAPIParserLimitWindowSecondsNilJe5h() {
    // primary bez limit_window_seconds → (nil ?? 0) < 86400 → .rolling5h
    let data = Data(#"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":50,"reset_at":1}}}"#.utf8)
    let snap = CodexUsageAPIParser.parse(data)
    #expect(snap?.windows.count == 1)
    #expect(snap?.windows.first?.kind == .rolling5h)
}
