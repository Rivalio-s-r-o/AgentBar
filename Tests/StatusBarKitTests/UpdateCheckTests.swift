import Testing
import Foundation
@testable import StatusBarKit

@Test func semverParse() {
    #expect(SemanticVersion.parse("0.10.0") == SemanticVersion(major: 0, minor: 10, patch: 0))
    #expect(SemanticVersion.parse("v0.10.0") == SemanticVersion.parse("0.10.0"))
    #expect(SemanticVersion.parse("0.10") == SemanticVersion.parse("0.10.0"))
    #expect(SemanticVersion.parse("0.10.1-beta") == SemanticVersion.parse("0.10.1"))
    #expect(SemanticVersion.parse("abc") == nil)
    #expect(SemanticVersion.parse("") == nil)
    #expect(SemanticVersion.parse("1.2.3.4") == nil)
}

@Test func semverCompareNumericky() {
    // KRITICKÉ: 0.10 > 0.9 numericky, NE string compare
    #expect(SemanticVersion.parse("0.10.0")! > SemanticVersion.parse("0.9.1")!)
    #expect(SemanticVersion.parse("0.9.9")! < SemanticVersion.parse("0.10.0")!)
    #expect(SemanticVersion.parse("1.0.0")! > SemanticVersion.parse("0.99.99")!)
    #expect(SemanticVersion.parse("0.10.0")! == SemanticVersion.parse("0.10.0")!)
}

@Test func updateCheckerVyhodnoceni() {
    let cur = SemanticVersion(major: 0, minor: 10, patch: 0)
    // novější dostupná
    if case .updateAvailable(let v, let url) = UpdateChecker.evaluate(current: cur, latestTag: "v0.11.0", latestURL: "https://x/y") {
        #expect(v == SemanticVersion(major: 0, minor: 11, patch: 0))
        #expect(url == "https://x/y")
    } else { Issue.record("čekáno updateAvailable") }
    // stejná → upToDate
    if case .upToDate = UpdateChecker.evaluate(current: cur, latestTag: "0.10.0", latestURL: "u") {} else { Issue.record("čekáno upToDate") }
    // starší → upToDate
    if case .upToDate = UpdateChecker.evaluate(current: cur, latestTag: "0.9.9", latestURL: "u") {} else { Issue.record("čekáno upToDate (starší remote)") }
    // nil tag → unknown
    if case .unknown = UpdateChecker.evaluate(current: cur, latestTag: nil, latestURL: nil) {} else { Issue.record("čekáno unknown") }
    // neparsovatelný tag → unknown
    if case .unknown = UpdateChecker.evaluate(current: cur, latestTag: "garbage", latestURL: "u") {} else { Issue.record("čekáno unknown (garbage)") }
}
