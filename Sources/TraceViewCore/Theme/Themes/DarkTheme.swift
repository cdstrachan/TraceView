import SwiftUI

struct DarkTheme: AppTheme {
    let name = "Dark"

    // Surfaces
    var windowBackground: Color { Color(hex: 0x1A1A1E) }
    var sidebarBackground: Color { Color(hex: 0x232328) }
    var tableBackground: Color { Color(hex: 0x1E1E22) }
    var filterBarBackground: Color { Color(hex: 0x232328) }
    var statusBarBackground: Color { Color(hex: 0x19191D) }
    var cardBackground: Color { Color(hex: 0x28282D) }
    var inputBackground: Color { Color(hex: 0x2C2C31) }

    // Borders
    var border: Color { Color(hex: 0x3A3A3F) }
    var borderSubtle: Color { Color(hex: 0x2E2E33) }
    var focusRing: Color { Color(hex: 0x4A9EFF, opacity: 0.4) }

    // Text
    var primaryText: Color { Color(hex: 0xE5E5EA) }
    var secondaryText: Color { Color(hex: 0x8E8E93) }
    var tertiaryText: Color { Color(hex: 0x636366) }
    var timestampText: Color { Color(hex: 0x7EB6FF) }
    var componentText: Color { Color(hex: 0xA9A9AE) }

    // Interactive
    var sidebarHover: Color { Color(hex: 0x2C2C31) }
    var sidebarActive: Color { Color(hex: 0x343439) }
    var tableRowHover: Color { Color.white.opacity(0.04) }
    var tableRowSelected: Color { Color(hex: 0x4A9EFF, opacity: 0.15) }
    var accentColor: Color { Color(hex: 0x4A9EFF) }

    // Log level — row backgrounds
    var errorHighlight: Color { Color(hex: 0x322126) }
    var criticalHighlight: Color { Color(hex: 0x3B1F24) }
    var warningHighlight: Color { Color(hex: 0x302919) }

    func rowBackground(for level: LogLevel) -> Color {
        switch level {
        case .critical: return Color(hex: 0x3B1F24)
        case .error: return Color(hex: 0x322126)
        case .warning: return Color(hex: 0x302919)
        case .notice: return Color(hex: 0x202A38)
        case .info: return Color(hex: 0x1D2D22)
        case .debug, .unknown: return Color(hex: 0x26292E)
        }
    }

    // Log level — text
    var errorText: Color { Color(hex: 0xFF6961) }
    var warningText: Color { Color(hex: 0xFFD60A) }
    var debugText: Color { Color(hex: 0xA1A1AA) }

    // Semantic
    var followingIndicator: Color { Color(hex: 0x32D74B) }
    var pausedIndicator: Color { Color(hex: 0x636366) }
    var searchHighlight: Color { Color(hex: 0xFFD60A, opacity: 0.30) }
    var searchHighlightActive: Color { Color(hex: 0xFFD60A, opacity: 0.55) }
    var errorCodeLink: Color { Color(hex: 0x64D2FF) }
    var liveIndicator: Color { Color(hex: 0xFF9F0A) }

    // Badges
    func badgeBackground(for level: LogLevel) -> Color {
        switch level {
        case .critical: return Color(hex: 0x7F0000)
        case .error: return Color(hex: 0x6B2A30)
        case .warning: return Color(hex: 0x5A451A)
        case .notice: return Color(hex: 0x233B59)
        case .info: return Color(hex: 0x21472E)
        case .debug, .unknown: return Color(hex: 0x33383F)
        }
    }

    func badgeText(for level: LogLevel) -> Color {
        switch level {
        case .critical: return Color(hex: 0xFFFFFF)
        case .error: return Color(hex: 0xFFD9DD)
        case .warning: return Color(hex: 0xFFE2A3)
        case .notice: return Color(hex: 0xC7DDFF)
        case .info: return Color(hex: 0xB7F2C0)
        case .debug, .unknown: return Color(hex: 0xE5E7EB)
        }
    }
}
