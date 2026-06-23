import Foundation

public enum CodexTokenParser {
    private struct Line: Decodable { let type: String?; let payload: Payload? }
    private struct Payload: Decodable { let type: String?; let info: Info? }
    private struct Info: Decodable { let total_token_usage: Total? }
    private struct Total: Decodable {
        let input_tokens: UInt?; let cached_input_tokens: UInt?
        let output_tokens: UInt?; let reasoning_output_tokens: UInt?
    }

    public static func lastTotal(fromJSONL data: Data) -> TokenUsage? {
        let needle = Data("total_token_usage".utf8)
        let decoder = JSONDecoder()
        var last: Total?
        for raw in data.split(separator: UInt8(ascii: "\n")) {
            let line = Data(raw)
            guard line.range(of: needle) != nil,
                  let l = try? decoder.decode(Line.self, from: line),
                  l.type == "event_msg", l.payload?.type == "token_count",
                  let total = l.payload?.info?.total_token_usage
            else { continue }
            last = total
        }
        guard let t = last else { return nil }
        let cached = t.cached_input_tokens ?? 0
        let input = (t.input_tokens ?? 0) >= cached ? (t.input_tokens ?? 0) - cached : 0
        let output = (t.output_tokens ?? 0) + (t.reasoning_output_tokens ?? 0)
        return TokenUsage(input: input, output: output, cacheWrite: 0, cacheRead: cached)
    }
}
