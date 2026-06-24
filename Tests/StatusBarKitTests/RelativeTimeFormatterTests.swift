import Testing
import Foundation
@testable import StatusBarKit

private let now = Date(timeIntervalSince1970: 1_000_000)
private let cs = L10n.bundle("cs")
private let en = L10n.bundle("en")

@Test func relČasPrávěTeď() {
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-30), now: now, bundle: cs) == "právě teď")
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-30), now: now, bundle: en) == "just now")
}
@Test func relČasMinuty() {
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-5*60), now: now, bundle: cs) == "před 5 min")
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-5*60), now: now, bundle: en) == "5 min ago")
}
@Test func relČasHodiny() {
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-2*3600), now: now, bundle: cs) == "před 2 h")
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-2*3600), now: now, bundle: en) == "2 h ago")
}
@Test func relČasDny() {
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-3*86400), now: now, bundle: cs) == "před 3 d")
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-3*86400), now: now, bundle: en) == "3 d ago")
}
