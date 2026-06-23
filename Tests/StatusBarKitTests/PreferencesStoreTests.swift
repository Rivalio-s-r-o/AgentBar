import Testing
import Foundation
@testable import StatusBarKit

private func freshDefaults() -> (UserDefaults, String) {
    let suite = "test-prefs-\(UUID().uuidString)"
    return (UserDefaults(suiteName: suite)!, suite)
}

@Test func defaultyJsouVypnutoA10() {
    let (ud, suite) = freshDefaults()
    defer { ud.removePersistentDomain(forName: suite) }
    let store = PreferencesStore(defaults: ud)
    #expect(store.notificationsEnabled == false)
    #expect(store.remainingThresholdPercent == 10)
}

@Test func uloženíANačtení() {
    let (ud, suite) = freshDefaults()
    defer { ud.removePersistentDomain(forName: suite) }
    let store = PreferencesStore(defaults: ud)
    store.notificationsEnabled = true
    store.remainingThresholdPercent = 15
    // nová instance nad stejným UserDefaults vidí uložené hodnoty
    let reread = PreferencesStore(defaults: ud)
    #expect(reread.notificationsEnabled == true)
    #expect(reread.remainingThresholdPercent == 15)
}
