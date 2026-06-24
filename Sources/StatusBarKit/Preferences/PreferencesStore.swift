import Foundation

public enum PreferenceKeys {
    public static let notificationsEnabled = "notificationsEnabled"
    public static let remainingThresholdPercent = "remainingThresholdPercent"
    public static let barStyle = "barStyle"
    public static let showUsedPercent = "showUsedPercent"
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
    public var barStyle: MenuBarStyle {
        get { MenuBarStyle(rawValue: defaults.string(forKey: PreferenceKeys.barStyle) ?? "") ?? .dotPercent }
        nonmutating set { defaults.set(newValue.rawValue, forKey: PreferenceKeys.barStyle) }
    }
    public var showUsedPercent: Bool {
        get { defaults.bool(forKey: PreferenceKeys.showUsedPercent) }   // default false
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.showUsedPercent) }
    }
}
