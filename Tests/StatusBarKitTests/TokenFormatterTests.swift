import Testing
import Foundation
@testable import StatusBarKit

@Test func compactTokeny() {
    #expect(TokenFormatter.compact(950) == "950")
    #expect(TokenFormatter.compact(1_240_000) == "1.24M")
    #expect(TokenFormatter.compact(820_000) == "820K")
}

@Test func moneyDvěMísta() {
    #expect(TokenFormatter.money(Decimal(string: "9.804")!) == "$9.80")
    #expect(TokenFormatter.money(Decimal(0)) == "$0.00")
}

@Test func krátkýNázevModelu() {
    #expect(TokenFormatter.modelShortName("claude-opus-4-8") == "Opus")
    #expect(TokenFormatter.modelShortName("claude-sonnet-4-6") == "Sonnet")
    #expect(TokenFormatter.modelShortName("claude-haiku-4-5") == "Haiku")
    #expect(TokenFormatter.modelShortName("codex") == "Codex")
}
