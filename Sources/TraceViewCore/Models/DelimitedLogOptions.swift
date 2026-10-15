import Foundation

struct DelimitedLogOptions: Codable, Equatable {
    enum HeaderMode: String, Codable, CaseIterable {
        case auto
        case headers
        case noHeaders

        var title: String {
            switch self {
            case .auto: return "Auto"
            case .headers: return "Headers"
            case .noHeaders: return "No headers"
            }
        }
    }

    var delimiter: String? = nil
    var headerMode: HeaderMode = .auto

    static let automaticDelimiters: [Character] = [",", ";", "\t", "|"]

    static func validationError(for delimiter: String) -> String? {
        guard delimiter.count == 1 else { return "Enter exactly one separator character." }
        guard !delimiter.contains(where: { $0.isNewline || $0 == "\"" }) else {
            return "Newlines and double quotes cannot be used as separators."
        }
        return nil
    }

    var isValid: Bool {
        delimiter.map { Self.validationError(for: $0) == nil } ?? true
    }

    static func delimiterName(_ delimiter: Character) -> String {
        switch delimiter {
        case ",": return "Comma (,)"
        case ";": return "Semicolon (;)"
        case "\t": return "Tab"
        case "|": return "Pipe (|)"
        case "-": return "Hyphen (-)"
        case " ": return "Space"
        default: return String(delimiter)
        }
    }
}
