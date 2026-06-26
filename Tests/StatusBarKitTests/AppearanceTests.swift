import Testing
import Foundation
@testable import StatusBarKit

@Test func appearanceAllCasesARawValue() {
    #expect(Appearance.allCases == [.system, .light, .dark])
    #expect(Appearance(rawValue: "dark") == .dark)
    #expect(Appearance(rawValue: "nesmysl") == nil)
}

@Test func appearanceDisplayNameEnCs() {
    #expect(Appearance.system.displayName(bundle: L10n.bundle("en")) == "System")
    #expect(Appearance.light.displayName(bundle: L10n.bundle("en")) == "Light")
    #expect(Appearance.dark.displayName(bundle: L10n.bundle("cs")) == "Tmavý")
    #expect(Appearance.system.displayName(bundle: L10n.bundle("cs")) == "Systém")
}

@Test func appearanceDefaultAPersistence() {
    let suite = "test.appearance.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: suite)!
    defer { d.removePersistentDomain(forName: suite) }
    let prefs = PreferencesStore(defaults: d)
    #expect(prefs.appearance == .system)   // default
    prefs.appearance = .dark
    #expect(prefs.appearance == .dark)
}
