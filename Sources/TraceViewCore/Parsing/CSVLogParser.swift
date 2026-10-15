import Foundation

/// Immutable sample-derived configuration keeps per-line parsing safe for
/// indexed sources and concurrent file loads.
struct CSVLogParser: LogParser {
    let name = "CSV"
    let supportedExtensions: Set<String> = ["csv"]
    let isLineStateless = true
    let kind: ParserKind = .csv
    let delimiter: Character
    let headers: [String]?
    let headerLineNumber: Int?
    private let timestampColumn: Int?
    private let levelColumn: Int?
    private let messageColumn: Int?
    private let componentColumn: Int?
    private let threadColumn: Int?

    init(
        delimiter: Character = ",",
        sampleLines: [String]? = nil,
        headerMode: DelimitedLogOptions.HeaderMode = .auto
    ) {
        self.delimiter = delimiter
        // Keep the historical no-sample initializer for existing per-line callers.
        guard let sampleLines else {
            headers = nil
            headerLineNumber = headerMode == .noHeaders ? nil : 1
            timestampColumn = nil
            levelColumn = nil
            messageColumn = nil
            componentColumn = nil
            threadColumn = nil
            return
        }
        let nonEmpty = sampleLines.enumerated().filter { !$0.element.isEmpty }
        let rows = nonEmpty.map { Self.splitRow($0.element, delimiter: delimiter) }
        let first = rows.first ?? []
        let known = Self.timestampHeaders.union(Self.levelHeaders)
            .union(Self.messageHeaders).union(Self.componentHeaders).union(Self.threadHeaders)
        let normalized = first.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        let recognized = normalized.filter { known.contains($0) }.count
        let hasHeaders = headerMode == .headers
            || (headerMode == .auto && recognized >= 1
                && !first.contains(where: { Self.levelValue($0) != nil || Self.dateValue($0) != nil }))
        headers = hasHeaders ? first : nil
        headerLineNumber = hasHeaders ? nonEmpty.first.map { $0.offset + 1 } : nil
        let values = hasHeaders ? Array(rows.dropFirst()) : rows
        func named(_ names: Set<String>) -> Int? {
            hasHeaders ? normalized.firstIndex(where: { names.contains($0) }) : nil
        }
        func inferred(_ matches: (String) -> Bool) -> Int? {
            (0..<(first.count)).first { column in
                let samples = values.compactMap { column < $0.count ? $0[column] : nil }
                return !samples.isEmpty
                    && samples.filter(matches).count * 5 >= samples.count * 4
            }
        }
        let timestamp = named(Self.timestampHeaders) ?? inferred { Self.dateValue($0) != nil }
        let level = named(Self.levelHeaders) ?? inferred { Self.levelValue($0) != nil }
        timestampColumn = timestamp
        levelColumn = level
        let candidates = (0..<first.count).filter { $0 != timestamp && $0 != level }
        messageColumn = named(Self.messageHeaders) ?? candidates.max { lhs, rhs in
            let left = values.reduce(0) { $0 + (lhs < $1.count ? $1[lhs].count : 0) }
            let right = values.reduce(0) { $0 + (rhs < $1.count ? $1[rhs].count : 0) }
            return left < right
        }
        componentColumn = named(Self.componentHeaders)
        threadColumn = named(Self.threadHeaders)
    }

    private static let timestampHeaders = Set(["timestamp", "time", "datetime", "date", "ts", "@timestamp"])
    private static let levelHeaders = Set(["level", "severity", "loglevel", "log_level", "priority"])
    private static let messageHeaders = Set(["message", "msg", "text", "body", "description", "log"])
    private static let componentHeaders = Set(["component", "source", "logger", "module", "service", "process", "category"])
    private static let threadHeaders = Set(["thread", "threadid", "thread_id", "tid"])

    func canParseLegacy(sampleLines: [String]) -> Double {
        guard sampleLines.count >= 2 else { return 0 }
        let columns = parseCSVRow(sampleLines[0])
        guard columns.count >= 2, parseCSVRow(sampleLines[1]).count == columns.count else { return 0 }
        let names = Set(columns.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })
        guard !names.isDisjoint(with: Self.messageHeaders) else { return 0 }
        return !names.isDisjoint(with: Self.levelHeaders) || !names.isDisjoint(with: Self.timestampHeaders) ? 0.8 : 0.5
    }

    func canParse(sampleLines: [String]) -> Double {
        guard sampleLines.count >= 2 else { return 0.0 }

        let lines = Array(sampleLines.filter { !$0.isEmpty }.prefix(50))
        guard lines.count >= 2,
              !lines.contains(where: {
                  let lead = $0.trimmingCharacters(in: .whitespaces).first
                  return lead == "{" || lead == "["
              }) else { return 0 }
        let rows = lines.map(parseCSVRow)
        guard let count = rows.first?.count, count >= 2,
              rows.allSatisfy({ $0.count == count }) else { return 0 }
        let configured = CSVLogParser(delimiter: delimiter, sampleLines: lines)
        if configured.headers != nil {
            let names = Set(rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespaces) })
            if !names.isDisjoint(with: Self.messageHeaders)
                && (!names.isDisjoint(with: Self.levelHeaders) || !names.isDisjoint(with: Self.timestampHeaders)) {
                return 0.8
            }
            if !names.isDisjoint(with: Self.messageHeaders) { return 0.5 }
        }
        if configured.timestampColumn != nil && configured.levelColumn != nil { return 0.75 }
        if configured.levelColumn != nil { return 0.7 }
        if configured.timestampColumn != nil { return 0.65 }
        return 0
    }

    func parse(line: String, lineNumber: Int, entryID: Int) -> LogEntry {
        let columns = parseCSVRow(line)
        // Keep the header visible as a debug entry.
        if lineNumber == headerLineNumber && (headers == nil || columns == headers) {
            return LogEntry(
                id: entryID, lineNumber: lineNumber,
                timestamp: nil, level: .debug,
                message: "CSV Header: \(line)", component: nil,
                threadID: nil, source: nil, rawLine: line
            )
        }

        guard !columns.isEmpty else {
            return LogEntry(
                id: entryID, lineNumber: lineNumber,
                timestamp: nil, level: .info,
                message: line, component: nil,
                threadID: nil, source: nil, rawLine: line
            )
        }

        func value(_ index: Int?) -> String? {
            guard let index, index < columns.count else { return nil }
            return columns[index]
        }
        let timestamp = value(timestampColumn).flatMap(Self.dateValue) ?? findTimestamp(in: columns)
        let level = value(levelColumn).flatMap(Self.levelValue) ?? findLevel(in: columns)
        let component = value(componentColumn) ?? findComponent(in: columns)
        let message = value(messageColumn) ?? findMessage(in: columns)

        return LogEntry(
            id: entryID, lineNumber: lineNumber,
            timestamp: timestamp, level: level,
            message: message, component: component,
            threadID: value(threadColumn), source: nil, rawLine: line
        )
    }

    private func findMessage(in columns: [String]) -> String {
        // The message is usually the last column or the longest one
        guard columns.count > 1 else { return columns.first ?? "" }
        // Pick the longest column (most likely the message)
        return columns.max(by: { $0.count < $1.count }) ?? columns.last ?? ""
    }

    private func findComponent(in columns: [String]) -> String? {
        // Component is usually a short identifier, not the first (timestamp) or last (message)
        guard columns.count > 3 else { return nil }
        // Skip first (likely timestamp) and last (likely message), pick a short middle column
        let middle = columns.dropFirst().dropLast()
        return middle.first { $0.count > 0 && $0.count < 50 && !isTimestamp($0) && !isLevel($0) }
    }

    private func findLevel(in columns: [String]) -> LogLevel {
        for col in columns {
            if let level = Self.levelValue(col) { return level }
        }
        return LevelDetector.detect(in: columns.joined(separator: " "))
    }

    private static func levelValue(_ value: String) -> LogLevel? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "debug", "trace": return .debug
        case "info", "information": return .info
        case "notice": return .notice
        case "warn", "warning": return .warning
        case "error", "err": return .error
        case "fatal", "critical": return .critical
        default: return nil
        }
    }

    private func findTimestamp(in columns: [String]) -> Date? {
        for col in columns.prefix(3) {
            let trimmed = col.trimmingCharacters(in: .whitespaces)
            if let date = Self.dateValue(trimmed) { return date }
        }
        return nil
    }

    private func isTimestamp(_ str: String) -> Bool {
        Self.dateValue(str) != nil
    }

    private func isLevel(_ str: String) -> Bool {
        let lower = str.trimmingCharacters(in: .whitespaces).lowercased()
        return ["debug", "trace", "info", "notice", "warn", "warning", "error", "fatal", "critical"].contains(lower)
    }

    // Immutable prebuilt formatters — safe to read concurrently (each
    // formatter's `dateFormat` is set once at init). Previously this code
    // mutated `dateFormat` on a shared static, which races when multiple
    // CSV files are parsed in parallel.
    private static let dateFormatters: [DateFormatter] = {
        [
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ss.SSS",
            "yyyy-MM-dd HH:mm:ss,SSS",
            "yyyy-MM-dd HH:mm:ss",
            "MM/dd/yyyy HH:mm:ss",
        ].map { format in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            return f
        }
    }()

    private static func dateValue(_ value: String) -> Date? {
        let str = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for f in Self.dateFormatters {
            if let date = f.date(from: str) { return date }
        }
        return nil
    }

    func parseCSVRow(_ line: String) -> [String] {
        Self.splitRow(line, delimiter: delimiter)
    }

    private static func splitRow(_ line: String, delimiter: Character) -> [String] {
        var columns: [String] = []
        var current = ""
        var inQuotes = false

        var index = line.startIndex
        while index < line.endIndex {
            let char = line[index]
            let next = line.index(after: index)
            if char == "\"" {
                if inQuotes && next < line.endIndex && line[next] == "\"" {
                    current.append("\"")
                    index = line.index(after: next)
                    continue
                } else {
                    inQuotes.toggle()
                }
            } else if char == delimiter && !inQuotes {
                columns.append(current)
                current = ""
            } else {
                current.append(char)
            }
            index = next
        }
        columns.append(current)
        return columns
    }
}
