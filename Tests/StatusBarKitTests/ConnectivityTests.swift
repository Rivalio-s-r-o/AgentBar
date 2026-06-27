import Foundation
import Testing
@testable import StatusBarKit

@Test func isConfiguredTrueKdyžSložkaExistuje() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmp.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    #expect(ProviderConnectivity.isConfigured(.claudeCode, home: tmp) == true)
    #expect(ProviderConnectivity.isConfigured(.codex, home: tmp) == false)
    try? FileManager.default.removeItem(at: tmp)
}

@Test func isConfiguredFalseKdyžChybí() {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    #expect(ProviderConnectivity.isConfigured(.claudeCode, home: tmp) == false)
    #expect(ProviderConnectivity.isConfigured(.codex, home: tmp) == false)
}

@Test func isGhostMatice() {
    #expect(ProviderConnectivity.isGhost(status: .ok, isConfigured: false) == false)
    #expect(ProviderConnectivity.isGhost(status: .degraded("x"), isConfigured: false) == false)
    #expect(ProviderConnectivity.isGhost(status: .unavailable("x"), isConfigured: true) == false)
    #expect(ProviderConnectivity.isGhost(status: .unavailable("x"), isConfigured: false) == true)
}
