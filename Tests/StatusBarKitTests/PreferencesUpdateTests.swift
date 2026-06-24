import Testing
import Foundation
@testable import StatusBarKit

@Test func autoUpdateDefaultTrueAPersistence() {
    let suite = "test.update.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: suite)!
    defer { d.removePersistentDomain(forName: suite) }
    let prefs = PreferencesStore(defaults: d)
    #expect(prefs.autoUpdateCheck == true)        // default ZAPNUTO
    prefs.autoUpdateCheck = false
    #expect(prefs.autoUpdateCheck == false)
    #expect(prefs.lastUpdateCheckAt == 0)          // default 0
    prefs.lastUpdateCheckAt = 12345
    #expect(prefs.lastUpdateCheckAt == 12345)
}
