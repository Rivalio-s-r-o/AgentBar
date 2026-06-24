import Foundation

/// Které okno ukazuje lišta. `.auto` = nejhorší okno (dnešní chování).
public enum BarWindowSource: String, Sendable, Hashable, CaseIterable {
    case auto, session, weekly

    public func displayName(bundle: Bundle? = nil) -> String {
        let b = bundle ?? .module
        switch self {
        case .auto:    return NSLocalizedString("barsource.auto", bundle: b, comment: "auto = worst window")
        case .session: return NSLocalizedString("window.session", bundle: b, comment: "")
        case .weekly:  return NSLocalizedString("window.weekly", bundle: b, comment: "")
        }
    }
    public var displayName: String { displayName() }
}
