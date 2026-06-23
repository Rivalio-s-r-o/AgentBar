import Testing
import Foundation
@testable import StatusBarKit

@Test func codexBerePosledníTotal() throws {
    let url = Bundle.module.url(forResource: "codex-session-tokens", withExtension: "jsonl", subdirectory: "Fixtures")!
    let t = CodexTokenParser.lastTotal(fromJSONL: try Data(contentsOf: url))
    // poslední řádek: input 3000 (z toho cached 1200) → 1800, output 600+100=700
    #expect(t == TokenUsage(input: 1800, output: 700, cacheWrite: 0, cacheRead: 1200))
}

@Test func codexBezTokenCountNil() {
    let t = CodexTokenParser.lastTotal(fromJSONL: Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"other\"}}".utf8))
    #expect(t == nil)
}
