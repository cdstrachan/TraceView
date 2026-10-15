import XCTest
@testable import TraceViewCore

final class DelimitedLogParserTests: XCTestCase {
    func testPythonTimestampsInHeaderlessSemicolonLogs() throws {
        let lines = [
            "2026-07-17 14:17:16,115;DEBUG;Loading KWallet",
            "2026-07-17 14:17:16,117;DEBUG;Loading SecretService",
            "2026-07-17 14:17:16,117;DEBUG;Loading Windows",
            "2026-07-17 14:17:16,118;DEBUG;Loading chainer",
            "2026-07-17 14:17:16,119;DEBUG;Loading libsecret",
            "2026-07-17 14:17:16,120;DEBUG;Loading macOS"
        ]
        for options in [DelimitedLogOptions(), DelimitedLogOptions(delimiter: ";")] {
            let parser = try XCTUnwrap(ParserRegistry.shared.detectParser(
                sampleLines: lines, delimitedOptions: options
            ) as? CSVLogParser)
            XCTAssertEqual(parser.delimiter, ";")
            XCTAssertNil(parser.headers)
            let first = parser.parse(line: lines[0], lineNumber: 1, entryID: 0)
            let last = parser.parse(line: lines[5], lineNumber: 6, entryID: 5)
            let date = try XCTUnwrap(first.timestamp)
            let lastDate = try XCTUnwrap(last.timestamp)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            XCTAssertEqual(formatter.string(from: date), "2026-07-17 14:17:16.115")
            XCTAssertEqual(lastDate.timeIntervalSince(date), 0.005, accuracy: 0.0001)
            XCTAssertEqual(first.message, "Loading KWallet")
            XCTAssertEqual(first.level, .debug)
            XCTAssertEqual(first.rawLine, lines[0])
        }
    }

    func testPythonTimestampInNamedColumnAndQuotedCommaCSV() throws {
        for (delimiter, lines) in [
            (";" as Character, ["message;timestamp;level", "hello;2026-07-17 14:17:16,115;DEBUG"]),
            ("," as Character, ["message,timestamp,level", #"hello,"2026-07-17 14:17:16,115",DEBUG"#])
        ] {
            let parser = CSVLogParser(delimiter: delimiter, sampleLines: lines)
            let record = parser.parse(line: lines[1], lineNumber: 2, entryID: 1)
            XCTAssertNotNil(record.timestamp)
            XCTAssertEqual(record.message, "hello")
            XCTAssertEqual(record.level, .debug)
        }
    }

    func testHeaderRowNamesBecomeGridColumnTitles() throws {
        let lines = ["event_time;sev;svc;details", "2026-10-15 12:00:00;error;api;Boom"]
        let parser = CSVLogParser(delimiter: ";", sampleLines: lines, headerMode: .headers)
        XCTAssertEqual(parser.columnTitles, [
            .timestamp: "event_time", .level: "sev", .field(2): "svc", .message: "details"
        ])
        let headerless = CSVLogParser(delimiter: ";", sampleLines: lines, headerMode: .noHeaders)
        XCTAssertTrue(headerless.columnTitles.isEmpty)
    }

    func testUnmappedFieldsBecomeExtraGridColumns() throws {
        let lines = [
            "time,level,host,user,message",
            "2026-10-15 12:00:00,INFO,web-1,alice,Started",
        ]
        let parser = CSVLogParser(delimiter: ",", sampleLines: lines)
        XCTAssertEqual(parser.extraFieldColumns, [2, 3])
        XCTAssertEqual(parser.gridColumns, [.timestamp, .level, .field(2), .field(3), .message])
        XCTAssertEqual(parser.columnTitles[.field(2)], "host")
        XCTAssertEqual(parser.columnTitles[.field(3)], "user")
        XCTAssertEqual(parser.fieldValues(for: lines[1])[3], "alice")
        XCTAssertEqual(parser.fieldTitle(0), "time")
        XCTAssertEqual(CSVLogParser(delimiter: ",", sampleLines: lines, headerMode: .noHeaders).fieldTitle(0), "Column 1")
    }

    func testAutomaticSeparatorsAndNamedColumns() throws {
        for separator in DelimitedLogOptions.automaticDelimiters {
            let lines = [
                ["message", "thread", "level", "timestamp", "service"].joined(separator: String(separator)),
                ["hello", "123", "error", "2026-10-15 12:00:00", "api"].joined(separator: String(separator))
            ]
            let parser = try XCTUnwrap(ParserRegistry.shared.detectParser(
                sampleLines: lines, delimitedOptions: DelimitedLogOptions()
            ) as? CSVLogParser)
            XCTAssertEqual(parser.delimiter, separator)
            let record = parser.parse(line: lines[1], lineNumber: 2, entryID: 1)
            XCTAssertEqual(record.message, "hello")
            XCTAssertEqual(record.threadID, "123")
            XCTAssertEqual(record.component, "api")
            XCTAssertEqual(record.level, .error)
            XCTAssertNotNil(record.timestamp)
            XCTAssertEqual(record.rawLine, lines[1])
        }
    }

    func testHeaderlessDetectionPreservesFirstRecord() throws {
        let lines = ["2026-10-15 12:00:00|error|First message", "2026-10-15 12:01:00|info|Next message"]
        let parser = try XCTUnwrap(ParserRegistry.shared.detectParser(
            sampleLines: lines, delimitedOptions: DelimitedLogOptions()
        ) as? CSVLogParser)
        XCTAssertNil(parser.headers)
        let record = parser.parse(line: lines[0], lineNumber: 1, entryID: 0)
        XCTAssertEqual(record.message, "First message")
        XCTAssertEqual(record.level, .error)
        XCTAssertNotNil(record.timestamp)
        XCTAssertTrue(ParsedLogDetail(entry: record, csvParser: parser).copyText.hasPrefix("Column 1:"))
    }

    func testManualHyphenAndUnicodeSeparator() throws {
        for separator in ["-", "💠"] {
            let lines = ["level\(separator)message", "info\(separator)hello"]
            let parser = try XCTUnwrap(ParserRegistry.shared.detectParser(
                sampleLines: lines, delimitedOptions: .init(delimiter: separator)
            ) as? CSVLogParser)
            XCTAssertEqual(parser.delimiter, separator.first)
            XCTAssertEqual(parser.parse(line: lines[1], lineNumber: 2, entryID: 1).message, "hello")
            XCTAssertEqual(
                ParsedLogDetail(entry: parser.parse(line: lines[1], lineNumber: 2, entryID: 1),
                                csvParser: parser).copyText,
                "level: info\nmessage: hello"
            )
        }
    }

    func testQuotedSeparatorsQuotesAndEmptyColumns() {
        let parser = CSVLogParser(delimiter: ";")
        XCTAssertEqual(parser.parseCSVRow(#"info;"hello; ""world""";;tail;"#),
                       ["info", #"hello; "world""#, "", "tail", ""])
        let unicode = CSVLogParser(delimiter: "💠")
        XCTAssertEqual(unicode.parseCSVRow(#"a💠"b💠c"💠"#), ["a", "b💠c", ""])
    }

    func testJSONFieldIsFormattedWithoutLosingOtherColumns() {
        let parser = CSVLogParser(delimiter: ";", sampleLines: ["level;message", #"info;"{""value"":42}""#])
        let record = parser.parse(line: #"info;"{""value"":42}""#, lineNumber: 2, entryID: 1)
        XCTAssertEqual(ParsedLogDetail(entry: record, csvParser: parser).copyText,
                       "level: info\nmessage: {\n  \"value\" : 42\n}")
    }

    func testExplicitHeaderModesAndLeadingBlankLines() {
        let parser = CSVLogParser(delimiter: ";", sampleLines: ["", "thing;value", "foo;bar"], headerMode: .headers)
        XCTAssertEqual(parser.headerLineNumber, 2)
        XCTAssertEqual(parser.headers, ["thing", "value"])
        let noHeaders = CSVLogParser(delimiter: ";", sampleLines: ["message;level", "foo;bar"], headerMode: .noHeaders)
        XCTAssertNil(noHeaders.headers)
        XCTAssertEqual(noHeaders.parse(line: "message;level", lineNumber: 1, entryID: 0).level, .info)
        XCTAssertFalse(noHeaders.parse(line: "message;level", lineNumber: 1, entryID: 0).message.hasPrefix("CSV Header:"))
    }

    func testManualOverrideDoesNotRequireRecognizableLogColumns() throws {
        let parser = try XCTUnwrap(ParserRegistry.shared.detectParser(
            sampleLines: ["a:b", "c:d"],
            delimitedOptions: .init(delimiter: ":", headerMode: .noHeaders)
        ) as? CSVLogParser)
        XCTAssertEqual(parser.parseCSVRow("a:b"), ["a", "b"])
    }

    func testDetectionRejectsProseDatesInconsistentRowsAndJSON() {
        for lines in [
            ["Hello, world", "Goodbye, friend"],
            ["2026-10-15 12:00:00 info hello", "2026-10-16 12:00:00 info bye"],
            ["level;message", "info;hello;extra"],
            [#"{"level":"info","message":"hello"}"#, #"{"level":"error","message":"bye"}"#]
        ] {
            XCTAssertFalse(ParserRegistry.shared.detectParser(
                sampleLines: lines, delimitedOptions: DelimitedLogOptions()
            ) is CSVLogParser)
        }
    }

    func testCustomDelimiterValidation() {
        for value in ["", "ab", "\"", "\n", "\r", "\r\n"] {
            XCTAssertNotNil(DelimitedLogOptions.validationError(for: value))
        }
        for value in [";", "-", "\t", " ", "💠", "é"] {
            XCTAssertNil(DelimitedLogOptions.validationError(for: value))
        }
    }

    func testStreamsKeepLegacyCommaOnlyDetection() {
        let semicolon = ["level;message", "info;hello"]
        XCTAssertFalse(ParserRegistry.shared.detectParser(sampleLines: semicolon) is CSVLogParser)
        let comma = ["level,message", "info,hello"]
        XCTAssertTrue(ParserRegistry.shared.detectParser(sampleLines: comma) is CSVLogParser)
        let headerless = ["info,hello", "error,bye"]
        XCTAssertFalse(ParserRegistry.shared.detectParser(sampleLines: headerless) is CSVLogParser)
    }
}

final class DelimitedLogPreferenceTests: XCTestCase {
    func testPreferencesRoundTripIsolationAndReset() throws {
        let suite = "TraceView.DelimitedTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = URL(fileURLWithPath: "/tmp/traceview-first.log.gz")
        let second = URL(fileURLWithPath: "/tmp/traceview-second.log")
        let options = DelimitedLogOptions(delimiter: "💠", headerMode: .noHeaders)
        try SettingsManager.saveDelimitedOptions(options, for: first, defaults: defaults)
        XCTAssertEqual(SettingsManager.delimitedOptions(for: first, defaults: defaults), options)
        XCTAssertEqual(SettingsManager.delimitedOptions(for: second, defaults: defaults), DelimitedLogOptions())
        try SettingsManager.saveDelimitedOptions(DelimitedLogOptions(), for: first, defaults: defaults)
        XCTAssertEqual(SettingsManager.delimitedOptions(for: first, defaults: defaults), DelimitedLogOptions())
    }

    func testInvalidOverrideIsRejectedWithoutOverwritingPreferences() throws {
        let suite = "TraceView.DelimitedTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = URL(fileURLWithPath: "/tmp/traceview-validation.log")
        let options = DelimitedLogOptions(delimiter: ";")
        try SettingsManager.saveDelimitedOptions(options, for: url, defaults: defaults)
        XCTAssertThrowsError(try SettingsManager.saveDelimitedOptions(
            .init(delimiter: "\n"), for: url, defaults: defaults
        ))
        XCTAssertEqual(SettingsManager.delimitedOptions(for: url, defaults: defaults), options)
    }
}
