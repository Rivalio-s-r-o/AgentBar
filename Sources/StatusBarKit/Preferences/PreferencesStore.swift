import Foundation

public enum PreferenceKeys {
    public static let notificationsEnabled = "notificationsEnabled"
    public static let remainingThresholdPercent = "remainingThresholdPercent"
    public static let barStyle = "barStyle"
    public static let showUsedPercent = "showUsedPercent"
    public static let barWindowSource = "barWindowSource"
    public static let autoUpdateCheck = "autoUpdateCheck"
    public static let lastUpdateCheckAt = "lastUpdateCheckAt"
    public static let appearance = "appearance"
    public static let barProviders = "barProviders"
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
    public var barWindowSource: BarWindowSource {
        get { BarWindowSource(rawValue: defaults.string(forKey: PreferenceKeys.barWindowSource) ?? "") ?? .auto }
        nonmutating set { defaults.set(newValue.rawValue, forKey: PreferenceKeys.barWindowSource) }
    }
    public var autoUpdateCheck: Bool {
        get {
            if defaults.object(forKey: PreferenceKeys.autoUpdateCheck) == nil { return true }   // default ZAPNUTO
            return defaults.bool(forKey: PreferenceKeys.autoUpdateCheck)
        }
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.autoUpdateCheck) }
    }
    public var lastUpdateCheckAt: Double {
        get { defaults.double(forKey: PreferenceKeys.lastUpdateCheckAt) }   // default 0
        nonmutating set { defaults.set(newValue, forKey: PreferenceKeys.lastUpdateCheckAt) }
    }
    public var appearance: Appearance {
        get { Appearance(rawValue: defaults.string(forKey: PreferenceKeys.appearance) ?? "") ?? .system }
        nonmutating set { defaults.set(newValue.rawValue, forKey: PreferenceKeys.appearance) }
    }
    public var barProviders: BarProviders {
        get { BarProviders(rawValue: defaults.string(forKey: PreferenceKeys.barProviders) ?? "") ?? .both }
        nonmutating set { defaults.set(newValue.rawValue, forKey: PreferenceKeys.barProviders) }
    }
}
