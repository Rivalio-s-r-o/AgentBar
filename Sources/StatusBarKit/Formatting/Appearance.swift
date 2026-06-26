import Foundation

/// Vzhled aplikace. `.system` = sleduj systém (default, beze změny chování).
public enum Appearance: String, Sendable, Hashable, CaseIterable {
    case system, light, dark

    public func displayName(bundle: Bundle? = nil) -> String {
        let b = bundle ?? .module
        switch self {
        case .system: return NSLocalizedString("appearance.system", bundle: b, comment: "follow system")
        case .light:  return NSLocalizedString("appearance.light", bundle: b, comment: "")
        case .dark:   return NSLocalizedString("appearance.dark", bundle: b, comment: "")
        }
    }
    public var displayName: String { displayName() }
}
