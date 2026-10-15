import Foundation

enum ParsedLogDetail: Equatable {
    struct Field: Equatable {
        let label: String
        let value: String
    }

    case text(String)
    case fields([Field])

    init(entry: LogEntry, csvHeaders: [String]? = nil, csvParser: CSVLogParser? = nil) {
        if csvHeaders != nil || csvParser != nil {
            let labels = csvHeaders ?? csvParser?.headers ?? []
            let values = (csvParser ?? CSVLogParser()).parseCSVRow(entry.rawLine)
            self = .fields(values.enumerated().map { index, value in
                let header = index < labels.count ? labels[index] : ""
                return Field(
                    label: header.trimmingCharacters(in: .whitespaces).isEmpty
                        ? "Column \(index + 1)" : header,
                    value: Self.prettyJSON(value) ?? value
                )
            })
        } else {
            self = .text(Self.prettyJSON(entry.rawLine)
                ?? Self.prettyJSON(entry.message)
                ?? entry.message)
        }
    }

    var copyText: String {
        switch self {
        case .text(let text):
            return text
        case .fields(let fields):
            return fields.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
        }
    }

    private static func prettyJSON(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{" || trimmed.first == "[",
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ) else { return nil }
        return String(data: formatted, encoding: .utf8)
    }
}
