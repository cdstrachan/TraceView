import SwiftUI

enum JSONSyntaxHighlighter {
    static func syntaxColor(_ color: Color) -> Color {
        let resolved = color.resolve(in: EnvironmentValues())
        return Color(
            .sRGB,
            red: Double(resolved.red) * 0.8,
            green: Double(resolved.green) * 0.8,
            blue: Double(resolved.blue) * 0.8,
            opacity: Double(resolved.opacity)
        )
    }

    static func highlight(_ text: String, theme: any AppTheme) -> AttributedString {
        var result = AttributedString(text)
        let first = text.first { !$0.isWhitespace }
        guard first == "{" || first == "[",
              (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil else {
            return result
        }

        var index = text.startIndex
        while index < text.endIndex {
            let start = index
            let character = text[index]
            let color: Color
            if character == "\"" {
                index = text.index(after: index)
                while index < text.endIndex {
                    let current = text[index]
                    index = text.index(after: index)
                    if current == "\\" && index < text.endIndex {
                        index = text.index(after: index)
                    } else if current == "\"" {
                        break
                    }
                }
                let next = text[index...].first { !$0.isWhitespace }
                color = next == ":" ? theme.timestampText : theme.followingIndicator
            } else if character == "-" || character.isNumber {
                index = text.index(after: index)
                while index < text.endIndex && "-+0123456789.eE".contains(text[index]) {
                    index = text.index(after: index)
                }
                color = theme.warningText
            } else if character.isLetter {
                index = text.index(after: index)
                while index < text.endIndex && text[index].isLetter {
                    index = text.index(after: index)
                }
                color = theme.errorCodeLink
            } else {
                index = text.index(after: index)
                continue
            }
            if let lower = AttributedString.Index(start, within: result),
               let upper = AttributedString.Index(index, within: result) {
                result[lower..<upper].foregroundColor = syntaxColor(color)
            }
        }
        return result
    }
}
