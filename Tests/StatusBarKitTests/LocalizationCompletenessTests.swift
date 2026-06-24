// Tests/StatusBarKitTests/LocalizationCompletenessTests.swift
import Testing
import Foundation
@testable import StatusBarKit

private func keys(_ langBundle: Bundle) -> Set<String> {
    guard let url = langBundle.url(forResource: "Localizable", withExtension: "strings"),
          let dict = NSDictionary(contentsOf: url) as? [String: String] else { return [] }
    return Set(dict.keys)
}

@Test func kitKlíčeEnACsShodné() {
    let en = keys(L10n.bundle("en"))
    let cs = keys(L10n.bundle("cs"))
    #expect(!en.isEmpty)
    #expect(en == cs, "Kit: rozdíl klíčů en↔cs: \(en.symmetricDifference(cs).sorted())")
}
