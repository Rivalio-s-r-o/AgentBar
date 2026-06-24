import Testing
import Foundation
@testable import StatusBarKit

private func usage(_ id: ProviderID, used: Double, status: ProviderStatus = .ok) -> ProviderUsage {
    ProviderUsage(providerId: id, displayName: id == .claudeCode ? "Claude Code" : "Codex", planLabel: nil,
        windows: [UsageWindow(kind: .rolling5h, usedFraction: used, resetAt: nil)],
        status: status, lastUpdated: Date())
}

// data: Claude 42 % vyčerpáno (58 zbývá), Codex 92 % vyčerpáno (8 zbývá)
private let cc = { usage(.claudeCode, used: 0.42) }()
private let cx = { usage(.codex, used: 0.92) }()

@Test func stylAZbývající() {
    let s = MenuBarTitleBuilder.segments(for: [cc, cx], style: .dotPercent, showUsedPercent: false)
    #expect(s == [
        MenuBarSegment(providerId: .claudeCode, leading: .providerDot, text: "58%", level: .normal),
        MenuBarSegment(providerId: .codex, leading: .providerDot, text: "8%", level: .critical),
    ])
}

@Test func stylAVyčerpané() {
    let s = MenuBarTitleBuilder.segments(for: [cc, cx], style: .dotPercent, showUsedPercent: true)
    #expect(s[0] == MenuBarSegment(providerId: .claudeCode, leading: .providerDot, text: "42%", level: .normal))
    #expect(s[1] == MenuBarSegment(providerId: .codex, leading: .providerDot, text: "92%", level: .critical))
}

@Test func stylBŠtítek() {
    let s = MenuBarTitleBuilder.segments(for: [cc, cx], style: .labelPercent, showUsedPercent: false)
    #expect(s[0] == MenuBarSegment(providerId: .claudeCode, leading: .label("CC"), text: "58%", level: .normal))
    #expect(s[1] == MenuBarSegment(providerId: .codex, leading: .label("CX"), text: "8%", level: .critical))
}

@Test func stylCJenTečka() {
    let s = MenuBarTitleBuilder.segments(for: [cc, cx], style: .dotOnly, showUsedPercent: false)
    #expect(s == [
        MenuBarSegment(providerId: .claudeCode, leading: .levelDot, text: "", level: .normal),
        MenuBarSegment(providerId: .codex, leading: .levelDot, text: "", level: .critical),
    ])
}

@Test func stylDNejkritičtější() {
    // Codex je horší (8 zbývá) → jediný segment Codexu
    let s = MenuBarTitleBuilder.segments(for: [cc, cx], style: .worst, showUsedPercent: false)
    #expect(s == [MenuBarSegment(providerId: .codex, leading: .providerDot, text: "8%", level: .critical)])
}

@Test func stylDVyčerpané() {
    let s = MenuBarTitleBuilder.segments(for: [cc, cx], style: .worst, showUsedPercent: true)
    #expect(s == [MenuBarSegment(providerId: .codex, leading: .providerDot, text: "92%", level: .critical)])
}

@Test func stylDPřeskočíNedostupné() {
    let down = usage(.codex, used: 0, status: .unavailable("x"))
    // Codex nedostupný → worst je Claude (jediný zobrazitelný)
    let s = MenuBarTitleBuilder.segments(for: [cc, down], style: .worst, showUsedPercent: false)
    #expect(s == [MenuBarSegment(providerId: .claudeCode, leading: .providerDot, text: "58%", level: .normal)])
}

@Test func stylDVšeNedostupné() {
    let a = usage(.claudeCode, used: 0, status: .unavailable("x"))
    let b = usage(.codex, used: 0, status: .unavailable("y"))
    let s = MenuBarTitleBuilder.segments(for: [a, b], style: .worst, showUsedPercent: false)
    #expect(s == [MenuBarSegment(providerId: .claudeCode, leading: .none, text: "—", level: .normal)])
}

@Test func prázdnýVstup() {
    #expect(MenuBarTitleBuilder.segments(for: [], style: .worst).isEmpty)
    #expect(MenuBarTitleBuilder.segments(for: [], style: .dotPercent).isEmpty)
}

@Test func nedostupnýStylB() {
    let down = usage(.claudeCode, used: 0, status: .unavailable("x"))
    let s = MenuBarTitleBuilder.segments(for: [down], style: .labelPercent)
    #expect(s[0] == MenuBarSegment(providerId: .claudeCode, leading: .label("CC"), text: "—", level: .normal))
}

@Test func menuBarStyleRawValueAFallback() {
    #expect(MenuBarStyle(rawValue: "dotPercent") == .dotPercent)
    #expect(MenuBarStyle(rawValue: "worst") == .worst)
    #expect(MenuBarStyle(rawValue: "nesmysl") == nil)               // fallback řeší PreferencesStore
    #expect(MenuBarStyle.allCases.count == 4)
    #expect(MenuBarStyle.dotPercent.displayName == "Tečka + %")
    #expect(MenuBarStyle.worst.displayName == "Nejkritičtější")
}

@Test func stylCNedostupný() {
    // dotOnly + .unavailable → tečka v barvě stavu .normal (nerozlišitelná od OK-normal, dle specu)
    let down = usage(.claudeCode, used: 0, status: .unavailable("x"))
    let s = MenuBarTitleBuilder.segments(for: [down], style: .dotOnly)
    #expect(s[0] == MenuBarSegment(providerId: .claudeCode, leading: .levelDot, text: "", level: .normal))
}

@Test func stylDShodaVyhráváPrvní() {
    // worst tie-break: při shodném vyčerpání vyhrává první v pořadí (Claude před Codexem)
    let a = usage(.claudeCode, used: 0.50)
    let b = usage(.codex, used: 0.50)
    let s = MenuBarTitleBuilder.segments(for: [a, b], style: .worst, showUsedPercent: false)
    #expect(s == [MenuBarSegment(providerId: .claudeCode, leading: .providerDot, text: "50%", level: .normal)])
}
