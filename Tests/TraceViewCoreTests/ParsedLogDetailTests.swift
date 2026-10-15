import XCTest
@testable import TraceViewCore

final class ParsedLogDetailTests: XCTestCase {
    private func entry(raw: String, message: String? = nil) -> LogEntry {
        LogEntry(
            id: 0, lineNumber: 2, timestamp: nil, level: .info,
            message: message ?? raw, component: nil, threadID: nil,
            source: nil, rawLine: raw
        )
    }

    func testJSONDisplaysFullRecordAndPreservesValues() throws {
        let raw = #"{"message":"hello","extra":{"items":[1,true,null],"url":"https://example.com"}} "#
        let record = JSONLogParser().parse(line: raw, lineNumber: 1, entryID: 0)
        let detail = ParsedLogDetail(entry: record)
        XCTAssertTrue(detail.copyText.contains("\n"))
        XCTAssertTrue(detail.copyText.contains("https://example.com"))
        let original = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? NSDictionary
        let formatted = try JSONSerialization.jsonObject(with: Data(detail.copyText.utf8)) as? NSDictionary
        XCTAssertEqual(original, formatted)
        XCTAssertEqual(record.rawLine, raw)
        XCTAssertEqual(record.message, "hello")
        XCTAssertEqual(record.gridMessage, raw)
    }

    func testUnifiedJSONGridShowsRawRecordWithoutChangingMessage() {
        let raw = #"{"messageType":"info","eventMessage":"hello","subsystem":"example"}"#
        let record = UnifiedLogParser().parse(line: raw, lineNumber: 1, entryID: 0)
        XCTAssertEqual(record.gridMessage, raw)
        XCTAssertEqual(record.message, "hello")
    }

    func testTextAndCSVGridKeepParsedMessage() {
        let text = entry(raw: "INFO hello", message: "hello")
        XCTAssertEqual(text.gridMessage, "hello")
        let csv = CSVLogParser().parse(line: "info,hello world", lineNumber: 2, entryID: 0)
        XCTAssertEqual(csv.gridMessage, "hello world")
    }

    func testJSONMessageInTextLogIsPrettyPrinted() {
        let detail = ParsedLogDetail(entry: entry(
            raw: #"INFO {"nested":{"value":42}}"#,
            message: #"{"nested":{"value":42}}"#
        ))
        XCTAssertEqual(detail.copyText, "{\n  \"nested\" : {\n    \"value\" : 42\n  }\n}")
    }

    func testJSONArrayIsPrettyPrinted() throws {
        let detail = ParsedLogDetail(entry: entry(raw: #"[{"value":1},{"value":2}]"#))
        XCTAssertTrue(detail.copyText.contains("\n"))
        let array = try JSONSerialization.jsonObject(with: Data(detail.copyText.utf8)) as? [[String: Int]]
        XCTAssertEqual(array, [["value": 1], ["value": 2]])
    }

    func testPlainTextAndMalformedJSONKeepOriginalMessage() {
        for message in ["hello, world", "{invalid json", "[not an array", ""] {
            XCTAssertEqual(
                ParsedLogDetail(entry: entry(raw: "INFO \(message)", message: message)),
                .text(message)
            )
        }
    }

    func testCSVFieldsUseHeadersAndDecodeQuotesCommasAndEmptyValues() {
        let raw = #"info,"hello, ""world""",,tail,"#
        let detail = ParsedLogDetail(
            entry: entry(raw: raw),
            csvHeaders: ["Level", "Message", "Empty", "Extra", "Trailing"]
        )
        XCTAssertEqual(detail, .fields([
            .init(label: "Level", value: "info"),
            .init(label: "Message", value: #"hello, "world""#),
            .init(label: "Empty", value: ""),
            .init(label: "Extra", value: "tail"),
            .init(label: "Trailing", value: "")
        ]))
        XCTAssertEqual(detail.copyText, "Level: info\nMessage: hello, \"world\"\nEmpty: \nExtra: tail\nTrailing: ")
    }

    func testCSVUnnamedExtraAndDuplicateColumnsArePreserved() {
        let detail = ParsedLogDetail(
            entry: entry(raw: "a,b,c,d"),
            csvHeaders: ["Name", "Name", " "]
        )
        XCTAssertEqual(detail, .fields([
            .init(label: "Name", value: "a"),
            .init(label: "Name", value: "b"),
            .init(label: "Column 3", value: "c"),
            .init(label: "Column 4", value: "d")
        ]))
    }

    func testCSVQuotedJSONValueIsPrettyPrinted() {
        let detail = ParsedLogDetail(
            entry: entry(raw: #""{""value"":42}""#),
            csvHeaders: ["Payload"]
        )
        XCTAssertEqual(detail, .fields([.init(label: "Payload", value: "{\n  \"value\" : 42\n}")]))
    }

    func testCSVParserPreservesEscapedQuoteAtStartOfField() {
        let parser = CSVLogParser()
        XCTAssertEqual(parser.parseCSVRow("\"\"\"\",\"\"\"hello\"\"\",plain"), ["\"", "\"hello\"", "plain"])
        let raw = #"info,"said ""hello"", friend""#
        let record = parser.parse(line: raw, lineNumber: 2, entryID: 0)
        XCTAssertEqual(record.message, #"said "hello", friend"#)
        XCTAssertEqual(record.rawLine, raw)
    }
}
