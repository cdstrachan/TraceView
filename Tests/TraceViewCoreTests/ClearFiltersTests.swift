import XCTest
import AppKit
@testable import TraceViewCore

final class ClearFiltersTests: XCTestCase {
    func testClearResetsEveryFilterWithoutChangingOtherPaneOrFindMode() {
        let document = LogDocument(source: .stdin, displayName: "Test")
        let first = LogDocumentViewModel(document: document)
        let second = LogDocumentViewModel(document: document)
        first.findMode = .find
        first.filter.searchText = "missing"
        first.filter.isRegex = true
        first.filter.caseSensitive = true
        first.filter.minimumLevel = .error
        first.filter.enabledLevels = [.error]
        first.filter.component = "api"
        first.filter.hiddenSourceIDs = [UUID()]
        second.filter.component = "database"
        first.clearFilters()
        XCTAssertEqual(first.filter, LogFilter())
        XCTAssertEqual(first.findMode, .find)
        XCTAssertEqual(second.filter.component, "database")
    }

    func testEmptyGridContextMenuCanClearFilters() throws {
        let view = LogScrollDocumentView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        var cleared = false
        view.onClearFilters = { cleared = true }
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown, location: NSPoint(x: 20, y: 20),
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ))
        let menu = try XCTUnwrap(view.menu(for: event))
        let item = try XCTUnwrap(menu.items.first { $0.title == "Clear Filters" })
        let action = try XCTUnwrap(item.action)
        view.perform(action, with: item)
        XCTAssertTrue(cleared)
    }
}
