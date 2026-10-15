import Foundation
import CoreGraphics

/// Identifies a column in the custom log view. Raw values match the
/// identifiers used by NSLogTableView so saved widths and order from
/// `ColumnLayoutStore` round-trip across the two renderers during the
/// feature-flag period. `field(n)` is the zero-based nth field of a
/// delimited log that isn't already shown by a built-in column.
enum ColumnID: Hashable {
    case lineNumber
    case timestamp
    case level
    case component
    case sourceLabel
    case message
    case field(Int)

    var isField: Bool {
        if case .field = self { return true }
        return false
    }

    /// Initial width when no saved width is present. Mirrors the
    /// NSTableColumn defaults at NSLogTableView.swift:96-138.
    var defaultWidth: CGFloat {
        switch self {
        case .field:       return 120
        case .lineNumber:  return 48
        case .timestamp:   return 110
        case .level:       return 52
        case .component:   return 110
        case .sourceLabel: return 130
        case .message:     return 200
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .field:       return 50
        case .lineNumber:  return 48
        case .timestamp:   return 80
        case .level:       return 40
        case .component:   return 60
        case .sourceLabel: return 80
        case .message:     return 200
        }
    }

    /// `nil` for the autoresizing column (message). Every other column has
    /// a hard upper bound so a stray drag can't swallow the message column.
    var maxWidth: CGFloat? {
        switch self {
        case .field:       return 600
        case .lineNumber:  return 80
        case .timestamp:   return 280
        case .level:       return 80
        case .component:   return 320
        case .sourceLabel: return 240
        case .message:     return nil
        }
    }

    /// Title rendered by the column header. Matches the titles used by
    /// the NSTableColumn defaults in NSLogTableView (e.g. "#" for the
    /// line-number gutter) so users see the same labels regardless of
    /// which renderer is active.
    var title: String {
        switch self {
        case .field(let index): return "Column \(index + 1)"
        case .lineNumber:  return "#"
        case .timestamp:   return "Timestamp"
        case .level:       return "Level"
        case .component:   return "Component"
        case .sourceLabel: return "Source"
        case .message:     return "Message"
        }
    }
}

extension ColumnID: RawRepresentable {
    private static let fieldPrefix = "field."

    init?(rawValue: String) {
        switch rawValue {
        case "lineNumber":  self = .lineNumber
        case "timestamp":   self = .timestamp
        case "level":       self = .level
        case "component":   self = .component
        case "sourceLabel": self = .sourceLabel
        case "message":     self = .message
        default:
            guard rawValue.hasPrefix(Self.fieldPrefix),
                  let index = Int(rawValue.dropFirst(Self.fieldPrefix.count)),
                  index >= 0 else { return nil }
            self = .field(index)
        }
    }

    var rawValue: String {
        switch self {
        case .lineNumber:  return "lineNumber"
        case .timestamp:   return "timestamp"
        case .level:       return "level"
        case .component:   return "component"
        case .sourceLabel: return "sourceLabel"
        case .message:     return "message"
        case .field(let index): return "\(Self.fieldPrefix)\(index)"
        }
    }
}

/// Computed frame of a single column in the layout. `x` is the column's
/// left edge in document-view coordinates; `width` is its rendered width.
struct ColumnFrame: Equatable {
    let id: ColumnID
    let x: CGFloat
    let width: CGFloat
}

/// Which columns are currently rendered. `.level` and `.message` are
/// always visible, so they don't appear as toggleable fields here. The
/// three user toggles (line number, timestamp, component) and the
/// document-driven source column are the only configurable ones.
///
/// `fileColumns`, when set (delimited logs), replaces the built-in column
/// set: the grid shows exactly the file's fields in file order, after the
/// optional line-number column.
struct ColumnVisibility: Equatable {
    var showLineNumber: Bool
    var showTimestamp: Bool
    var showComponent: Bool
    var showSource: Bool
    var fileColumns: [ColumnID]? = nil

    func isVisible(_ id: ColumnID) -> Bool {
        if let fileColumns, id != .lineNumber {
            guard fileColumns.contains(id) else { return false }
            return id == .timestamp ? showTimestamp : true
        }
        switch id {
        case .field:       return false
        case .lineNumber:  return showLineNumber
        case .timestamp:   return showTimestamp
        case .level:       return true
        case .component:   return showComponent
        case .sourceLabel: return showSource
        case .message:     return true
        }
    }
}

/// Pure-value layout computation for the custom log view's columns.
/// Splitting this out from `LogScrollDocumentView` keeps the geometry math
/// unit-testable without spinning up an `NSView`. P2.2 (column resize +
/// reorder + persistence) wires `savedWidths` and `order` through; PR #1
/// always passes nil and gets the defaults.
enum LogScrollColumnLayout {
    /// Default left-to-right column order: line number, timestamp, level,
    /// component, source, message. Source appears between component and
    /// message because that matches the natural read order on merged-view
    /// rows (timestamp · level · component · source · message).
    static let defaultOrder: [ColumnID] = [
        .lineNumber, .timestamp, .level, .component, .sourceLabel, .message
    ]

    /// Build `[ColumnFrame]` for the visible columns at the given bounds
    /// width. The `.message` column always fills the remainder; if the
    /// remainder would fall below its `minWidth`, message gets exactly its
    /// minWidth and the layout overflows past `boundsWidth` (caller's
    /// `NSScrollView` clips). Saved widths are clamped to each column's
    /// `[minWidth, maxWidth]` band. Unlisted IDs in `order` fall in at the
    /// end using `defaultOrder`'s positions.
    ///
    /// `messageContentWidth`, when non-nil, is the no-wrap horizontal-scroll
    /// mode: the message column is widened to at least that value (the
    /// measured width of its content) so long lines extend past the viewport
    /// and the caller's horizontal scroller reveals them. It still fills the
    /// remainder when the content is narrower than the viewport, so the
    /// column never leaves a gap on the right.
    static func compute(
        boundsWidth: CGFloat,
        visibility: ColumnVisibility,
        savedWidths: [ColumnID: CGFloat] = [:],
        order: [ColumnID]? = nil,
        messageContentWidth: CGFloat? = nil
    ) -> [ColumnFrame] {
        let resolvedOrder = visibility.fileColumns.map { [.lineNumber] + $0 }
            ?? resolve(order: order)
        let visibleIDs = resolvedOrder.filter { visibility.isVisible($0) }

        func clampedWidth(_ id: ColumnID, _ raw: CGFloat) -> CGFloat {
            if let maxW = id.maxWidth { return max(id.minWidth, min(maxW, raw)) }
            return max(id.minWidth, raw)
        }

        var widths: [ColumnID: CGFloat] = [:]
        if visibility.fileColumns != nil {
            // File-order layout: Message may sit mid-row, so every column
            // (Message included) has its own resizable width and the last
            // column stretches to fill any spare room.
            for id in visibleIDs {
                var raw = savedWidths[id] ?? id.defaultWidth
                if id == .message, savedWidths[id] == nil {
                    raw = max(Self.fileMessageWidth, messageContentWidth ?? 0)
                }
                widths[id] = clampedWidth(id, raw)
            }
            if let last = visibleIDs.last {
                let others = visibleIDs.dropLast().reduce(CGFloat(0)) { $0 + (widths[$1] ?? 0) }
                widths[last] = max(widths[last] ?? 0, boundsWidth - others)
            }
            return frames(for: visibleIDs, widths: widths)
        }

        var nonMessageTotal: CGFloat = 0
        for id in visibleIDs where id != .message {
            let clamped = clampedWidth(id, savedWidths[id] ?? id.defaultWidth)
            widths[id] = clamped
            nonMessageTotal += clamped
        }

        if visibility.isVisible(.message) {
            let remainder = boundsWidth - nonMessageTotal
            var messageWidth = max(ColumnID.message.minWidth, remainder)
            if let messageContentWidth {
                messageWidth = max(messageWidth, messageContentWidth)
            }
            widths[.message] = messageWidth
        }

        return frames(for: visibleIDs, widths: widths)
    }

    /// Starting width for Message when it isn't the autofill column.
    static let fileMessageWidth: CGFloat = 400

    private static func frames(for ids: [ColumnID], widths: [ColumnID: CGFloat]) -> [ColumnFrame] {
        var frames: [ColumnFrame] = []
        var x: CGFloat = 0
        for id in ids {
            let w = widths[id] ?? 0
            frames.append(ColumnFrame(id: id, x: x, width: w))
            x += w
        }
        return frames
    }

    /// Merge a partial saved order with the default order:
    /// 1. Listed columns keep their relative positions (less message).
    /// 2. Unlisted columns slot in at the end in default-order positions.
    /// 3. `.message` is forced to the final slot regardless of where the
    ///    caller placed it — message is the autoresize column and must
    ///    always sit at the right edge, otherwise its width-fills-remainder
    ///    math leaves trailing columns drawn off-screen.
    ///
    /// Header drag-reorder relies on (3): the user can drag any non-message
    /// column anywhere in the header, but the message column is locked at
    /// the right edge.
    private static func resolve(order: [ColumnID]?) -> [ColumnID] {
        let baseOrder = order ?? defaultOrder
        var withoutMessage = baseOrder.filter { $0 != .message && !$0.isField }
        let seen = Set(withoutMessage)
        withoutMessage.append(contentsOf: defaultOrder.filter { !seen.contains($0) && $0 != .message })
        withoutMessage.append(.message)
        return withoutMessage
    }
}
