import Foundation

/// Kteří provideři se zobrazují v menu baru. `.both` = oba (default, beze změny).
public enum BarProviders: String, Sendable, Hashable, CaseIterable {
    case both, claude, codex

    /// Má se daný provider zobrazit v liště?
    public func includes(_ id: ProviderID) -> Bool {
        switch self {
        case .both:   return true
        case .claude: return id == .claudeCode
        case .codex:  return id == .codex
        }
    }

    public func displayName(bundle: Bundle? = nil) -> String {
        let b = bundle ?? .module
        switch self {
        case .both:   return NSLocalizedString("barprov.both", bundle: b, comment: "both providers")
        case .claude: return "Claude"   // vlastní jméno — nepřekládá se
        case .codex:  return "Codex"
        }
    }
    public var displayName: String { displayName() }
}
