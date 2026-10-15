import SwiftUI
import XCTest
@testable import TraceViewCore

final class JSONSyntaxHighlighterTests: XCTestCase {
    func testTokenColorsAndTextArePreservedAcrossThemes() {
        let text = #"{"key":"escaped \"quote\" and \\ slash 😀","number":-1.25e+3,"flag":true,"empty":null,"items":[false,2]}"#
        let themes: [any AppTheme] = [ConsoleTheme(), LightTheme(), DarkTheme(), NeonTheme()]
        for theme in themes {
            let highlighted = JSONSyntaxHighlighter.highlight(text, theme: theme)
            XCTAssertEqual(String(highlighted.characters), text)
            for (token, expected) in [
                (#""key""#, theme.timestampText),
                (#""escaped \"quote\" and \\ slash 😀""#, theme.followingIndicator),
                ("-1.25e+3", theme.warningText),
                ("true", theme.errorCodeLink),
                ("false", theme.errorCodeLink),
                ("null", theme.errorCodeLink)
            ] {
                guard let range = highlighted.range(of: token) else {
                    XCTFail("Missing token \(token)")
                    continue
                }
                XCTAssertEqual(highlighted[range].foregroundColor, JSONSyntaxHighlighter.syntaxColor(expected))
            }
            if let range = highlighted.range(of: "{") {
                XCTAssertNil(highlighted[range].foregroundColor)
            }
        }
    }

    func testPlainTextAndMalformedJSONAreNotColored() {
        for text in ["plain 42 true", "{invalid}", "[broken", "", "hello \"world\""] {
            let result = JSONSyntaxHighlighter.highlight(text, theme: ConsoleTheme())
            XCTAssertEqual(result, AttributedString(text))
        }

        func testSyntaxColorsAreDarkerWithoutChangingOpacity() {
            let color = Color(.sRGB, red: 0.5, green: 0.75, blue: 1, opacity: 0.9)
            let result = JSONSyntaxHighlighter.syntaxColor(color).resolve(in: EnvironmentValues())
            XCTAssertEqual(result.red, 0.4, accuracy: 0.001)
            XCTAssertEqual(result.green, 0.6, accuracy: 0.001)
            XCTAssertEqual(result.blue, 0.8, accuracy: 0.001)
            XCTAssertEqual(result.opacity, 0.9, accuracy: 0.001)
        }
    }
}
