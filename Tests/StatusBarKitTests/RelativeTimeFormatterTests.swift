import Testing
import Foundation
@testable import StatusBarKit

private let now = Date(timeIntervalSince1970: 1_000_000)

@Test func relČasPrávěTeď() {
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-30), now: now) == "právě teď")
    #expect(RelativeTimeFormatter.string(from: now, now: now) == "právě teď")
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(60), now: now) == "právě teď")  // budoucnost
}
@Test func relČasMinuty() {
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-5*60), now: now) == "před 5 min")
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-59*60), now: now) == "před 59 min")
}
@Test func relČasHodiny() {
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-2*3600), now: now) == "před 2 h")
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-23*3600), now: now) == "před 23 h")
}
@Test func relČasDny() {
    #expect(RelativeTimeFormatter.string(from: now.addingTimeInterval(-3*86400), now: now) == "před 3 d")
}
