import Testing
import Foundation
@testable import StatusBarKit

@Test func barProvidersIncludes() {
    #expect(BarProviders.both.includes(.claudeCode))
    #expect(BarProviders.both.includes(.codex))
    #expect(BarProviders.claude.includes(.claudeCode))
    #expect(!BarProviders.claude.includes(.codex))
    #expect(BarProviders.codex.includes(.codex))
    #expect(!BarProviders.codex.includes(.claudeCode))
}

@Test func barProvidersDisplayNameEnCs() {
    #expect(BarProviders.both.displayName(bundle: L10n.bundle("en")) == "Both")
    #expect(BarProviders.both.displayName(bundle: L10n.bundle("cs")) == "Oba")
    #expect(BarProviders.claude.displayName == "Claude")
    #expect(BarProviders.codex.displayName == "Codex")
    #expect(BarProviders.allCases == [.both, .claude, .codex])
}

@Test func barProvidersDefaultAPersistence() {
    let suite = "test.barprov.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: suite)!
    defer { d.removePersistentDomain(forName: suite) }
    let prefs = PreferencesStore(defaults: d)
    #expect(prefs.barProviders == .both)   // default
    prefs.barProviders = .claude
    #expect(prefs.barProviders == .claude)
}
