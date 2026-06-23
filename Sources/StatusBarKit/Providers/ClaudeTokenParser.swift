import Foundation

public enum ClaudeTokenParser {
    private struct Line: Decodable {
        let type: String?; let timestamp: String?; let message: Msg?
    }
    private struct Msg: Decodable { let model: String?; let usage: Usage? }
    private struct Usage: Decodable {
        let input_tokens: UInt?; let output_tokens: UInt?
        let cache_creation_input_tokens: UInt?; let cache_read_input_tokens: UInt?
    }

    private static func makeIso() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }

    public static func sumByModel(fromJSONL data: Data, dayStart: Date, dayEnd: Date) -> [String: TokenUsage] {
        let needle = Data("\"assistant\"".utf8)
        let decoder = JSONDecoder()
        let iso = makeIso()
        let isoFallback = ISO8601DateFormatter()
        var result: [String: TokenUsage] = [:]
        for raw in data.split(separator: UInt8(ascii: "\n")) {
            let line = Data(raw)
            guard line.range(of: needle) != nil,
                  let l = try? decoder.decode(Line.self, from: line),
                  l.type == "assistant",
                  let ts = l.timestamp.flatMap({ iso.date(from: $0) }) ?? l.timestamp.flatMap({ isoFallback.date(from: $0) }),
                  ts >= dayStart, ts < dayEnd,
                  let model = l.message?.model, let u = l.message?.usage
            else { continue }
            let usage = TokenUsage(
                input: u.input_tokens ?? 0, output: u.output_tokens ?? 0,
                cacheWrite: u.cache_creation_input_tokens ?? 0, cacheRead: u.cache_read_input_tokens ?? 0)
            result[model, default: .zero] = (result[model] ?? .zero) + usage
        }
        return result
    }
}
