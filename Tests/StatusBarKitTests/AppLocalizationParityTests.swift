// Tests/StatusBarKitTests/AppLocalizationParityTests.swift
// App target (StatusBarApp) nelze testovat přes L10n.bundle (to je Kit .module).
// Proto čteme App .strings přímo ze zdrojů přes #filePath (robustní vůči CWD).
import Testing
import Foundation

private func appStringsKeys(lang: String) -> Set<String> {
    // <root>/Tests/StatusBarKitTests/<thisFile> → nahoru 3× = <root>
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // StatusBarKitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // <root>
    let url = root.appendingPathComponent("Sources/StatusBarApp/Resources/\(lang).lproj/Localizable.strings")
    guard let dict = NSDictionary(contentsOf: url) as? [String: String] else { return [] }
    return Set(dict.keys)
}

@Test func appKlíčeEnACsShodné() {
    let en = appStringsKeys(lang: "en")
    let cs = appStringsKeys(lang: "cs")
    #expect(!en.isEmpty, "App en.lproj nenačteno (ověř cestu Sources/StatusBarApp/Resources/en.lproj)")
    #expect(en == cs, "App: rozdíl klíčů en↔cs: \(en.symmetricDifference(cs).sorted())")
}
