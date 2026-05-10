import Foundation

enum AgentRunToolFormatter {
    struct Formatted {
        let title: String
        let detail: String?
    }

    static func format(toolName: String, arguments: [String: AnyCodable]) -> Formatted {
        Formatted(
            title: humanizeName(toolName),
            detail: genericDetail(arguments)
        )
    }

    private static func genericDetail(_ args: [String: AnyCodable]) -> String? {
        guard !args.isEmpty else { return nil }
        let pieces = args
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \(scalarDescription($0.value))" }
        return pieces.joined(separator: ", ")
    }

    private static func scalarDescription(_ value: AnyCodable) -> String {
        switch value {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .string(let s): return "“\(truncate(s, to: 60))”"
        case .array(let arr): return "[\(arr.count) items]"
        case .object(let obj): return "{\(obj.count) keys}"
        }
    }

    private static func humanizeName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private static func truncate(_ text: String, to length: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= length { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: length)
        return String(trimmed[..<end]) + "…"
    }
}
