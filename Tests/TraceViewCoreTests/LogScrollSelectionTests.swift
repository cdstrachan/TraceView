import AppKit
import XCTest
@testable import TraceViewCore

final class LogScrollSelectionTests: XCTestCase {
    private func entries(_ ids: [Int]) -> FilteredEntries {
        FilteredEntries(backing: .materialized(ids.map { index in
            LogEntry(
                id: index, lineNumber: index + 1, timestamp: nil, level: .info,
                message: "parsed \(index)", component: nil, threadID: nil,
                source: nil, rawLine: "raw \(index)"
            )
        }))
    }

    private func apply(_ ids: [Int], to view: LogScrollDocumentView) {
        view.apply(
            entries: entries(ids), theme: ThemeManager().current, fontSize: 12,
            isFollowing: false, bookmarkedLines: [], highlightRules: [],
            expandedEntryID: nil, inlineExpansionEnabled: false,
            sourceNameForID: { _ in nil }, horizontalScrollEnabled: false,
            colorLogRowsByLevel: false
        )
    }

    private func makeView() -> LogScrollDocumentView {
        let view = LogScrollDocumentView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        apply([0, 1, 2, 3, 4], to: view)
        return view
    }

    private func click(
        row: Int, in view: LogScrollDocumentView, shift: Bool = false
    ) throws {
        let event = try mouseEvent(row: row, in: view, shift: shift)
        view.mouseDown(with: event)
    }

    private func mouseEvent(
        row: Int, in view: LogScrollDocumentView, shift: Bool = false,
        type: NSEvent.EventType = .leftMouseDown
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: NSPoint(x: 20, y: view.rowFrame(for: row).minY + 1),
            modifierFlags: shift ? .shift : [], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
    }

    func testShiftClickCopiesOriginalRecordsInDisplayOrder() throws {
        let view = makeView()
        try click(row: 1, in: view)
        try click(row: 3, in: view, shift: true)
        XCTAssertEqual(view.selectedOriginalText, "raw 1\nraw 2\nraw 3")
        XCTAssertEqual(view.selectedRow, 3)
    }

    func testReverseRangeKeepsAnchorWhenShrinkingAndCrossing() throws {
        let view = makeView()
        try click(row: 3, in: view)
        try click(row: 0, in: view, shift: true)
        XCTAssertEqual(view.selectedOriginalText, "raw 0\nraw 1\nraw 2\nraw 3")
        try click(row: 2, in: view, shift: true)
        XCTAssertEqual(view.selectedOriginalText, "raw 2\nraw 3")
        try click(row: 4, in: view, shift: true)
        XCTAssertEqual(view.selectedOriginalText, "raw 3\nraw 4")
    }

    func testPlainClickOnRangeEndpointCollapsesToSingleRecord() throws {
        let view = makeView()
        try click(row: 1, in: view)
        try click(row: 3, in: view, shift: true)
        try click(row: 3, in: view)
        XCTAssertEqual(view.selectedOriginalText, "raw 3")
        try click(row: 3, in: view)
        XCTAssertNil(view.selectedOriginalText)
    }

    func testShiftArrowExtendsSelection() throws {
        let view = makeView()
        try click(row: 1, in: view)
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .shift,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}",
            isARepeat: false, keyCode: 125
        ))
        view.keyDown(with: event)
        XCTAssertEqual(view.selectedOriginalText, "raw 1\nraw 2")
    }

    func testRightClickInsideRangePreservesItAndOffersCopyOriginal() throws {
        let view = makeView()
        try click(row: 1, in: view)
        try click(row: 3, in: view, shift: true)
        let event = try mouseEvent(row: 2, in: view, type: .rightMouseDown)
        let menu = try XCTUnwrap(view.menu(for: event))
        XCTAssertEqual(view.selectedOriginalText, "raw 1\nraw 2\nraw 3")
        XCTAssertNotNil(menu.items.first { $0.title == "Copy Original" })
    }

    func testSelectAllIncludesOnlyVisibleRecords() {
        let view = makeView()
        apply([0, 2, 4], to: view)
        view.selectAll(nil)
        XCTAssertEqual(view.selectedOriginalText, "raw 0\nraw 2\nraw 4")
    }

    func testFilteringInvalidatesRangeWhenAnchorChanges() throws {
        let view = makeView()
        try click(row: 1, in: view)
        try click(row: 3, in: view, shift: true)
        apply([0, 2, 3, 4], to: view)
        XCTAssertNil(view.selectedOriginalText)
        XCTAssertNil(view.selectedRow)
    }

    func testShrinkingPastAnchorClearsReverseRange() throws {
        let view = makeView()
        try click(row: 4, in: view)
        try click(row: 1, in: view, shift: true)
        apply([0, 1, 2], to: view)
        XCTAssertNil(view.selectedOriginalText)
    }

    func testTrailingAppendPreservesRange() throws {
        let view = makeView()
        try click(row: 1, in: view)
        try click(row: 3, in: view, shift: true)
        apply([0, 1, 2, 3, 4, 5], to: view)
        XCTAssertEqual(view.selectedOriginalText, "raw 1\nraw 2\nraw 3")
    }
}