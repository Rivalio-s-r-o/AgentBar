// Sources/StatusBarKit/Localization/L10n.swift
import Foundation

/// Lokalizační pomocník. `bundle(_:)` vrací jazykově specifický .lproj bundle z Kit modulu
/// (pro deterministické testy); při neúspěchu vrací .module.
public enum L10n {
    public static func bundle(_ code: String) -> Bundle {
        guard let url = Bundle.module.url(forResource: code, withExtension: "lproj"),
              let b = Bundle(url: url) else { return .module }
        return b
    }
}
