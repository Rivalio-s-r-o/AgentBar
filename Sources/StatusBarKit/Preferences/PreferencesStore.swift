import Foundation

public enum PreferenceKeys {
    public static let notificationsEnabled = "notificationsEnabled"
    public static let remainingThresholdPercent = "remainingThresholdPercent"
}

public struct PreferencesStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var notificationsEnabled: Bool {
        get { defaults.bool(forKey: PreferenceKeys.notificationsEnabled) }   // default false
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.notificationsEnabled) }
    }
    public var remainingThresholdPercent: Int {
        get {
            let v = defaults.integer(forKey: PreferenceKeys.remainingThresholdPercent)
            return v == 0 ? 10 : v   // 0 = neuloženo → default 10 (UI nabízí jen 5/10/15/20)
        }
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.remainingThresholdPercent) }
    }
}
