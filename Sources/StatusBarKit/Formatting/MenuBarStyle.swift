import Foundation

public enum MenuBarStyle: String, Sendable, Equatable, Hashable, CaseIterable {
    case dotPercent      // A — barevná tečka providera + %
    case labelPercent    // B — písmenný štítek (CC/CX) + %
    case dotOnly         // C — jen tečka obarvená podle stavu
    case worst           // D — jediné číslo = nejnižší zbývající napříč providery
    case burnBar         // E — dvoubarevný proužek teď+projekce

    public func displayName(bundle: Bundle? = nil) -> String {
        let b = bundle ?? .module
        switch self {
        case .dotPercent:   return NSLocalizedString("style.dotPercent", bundle: b, comment: "")
        case .labelPercent: return NSLocalizedString("style.labelPercent", bundle: b, comment: "")
        case .dotOnly:      return NSLocalizedString("style.dotOnly", bundle: b, comment: "")
        case .worst:        return NSLocalizedString("style.worst", bundle: b, comment: "")
        case .burnBar:      return NSLocalizedString("style.burnBar", bundle: b, comment: "")
        }
    }
    public var displayName: String { displayName() }
}
