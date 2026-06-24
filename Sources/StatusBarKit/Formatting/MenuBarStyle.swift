import Foundation

public enum MenuBarStyle: String, Sendable, Equatable, Hashable, CaseIterable {
    case dotPercent      // A — barevná tečka providera + %
    case labelPercent    // B — písmenný štítek (CC/CX) + %
    case dotOnly         // C — jen tečka obarvená podle stavu
    case worst           // D — jediné číslo = nejnižší zbývající napříč providery

    public var displayName: String {
        switch self {
        case .dotPercent:   return "Tečka + %"
        case .labelPercent: return "Štítek + %"
        case .dotOnly:      return "Jen tečka"
        case .worst:        return "Nejkritičtější"
        }
    }
}
