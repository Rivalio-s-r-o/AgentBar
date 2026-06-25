import Testing
import Foundation
@testable import StatusBarKit

@Test func burnBarStyleVAllCases() {
    #expect(MenuBarStyle.allCases.contains(.burnBar))
    #expect(MenuBarStyle(rawValue: "burnBar") == .burnBar)
}
@Test func burnBarStyleDisplayName() {
    #expect(MenuBarStyle.burnBar.displayName(bundle: L10n.bundle("en")) == "Burn bar")
    #expect(MenuBarStyle.burnBar.displayName(bundle: L10n.bundle("cs")) == "Burn pruh")
}
