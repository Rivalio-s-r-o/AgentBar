// Tests/StatusBarKitTests/LocalizationPipelineTests.swift
import Testing
import Foundation
@testable import StatusBarKit

@Test func lokalizacePipelineKitFunguje() {
    let cs = L10n.bundle("cs")
    let en = L10n.bundle("en")
    #expect(NSLocalizedString("test.ping", bundle: cs, comment: "") == "pong-cs")
    #expect(NSLocalizedString("test.ping", bundle: en, comment: "") == "pong-en")
}
