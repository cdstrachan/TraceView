import AppKit
import XCTest
@testable import TraceViewCore

@MainActor
final class DelimitedFormatMenuTests: XCTestCase {
    func testHeaderSubmenuIsEnabledAndDispatchesEveryChoice() throws {
        var selected: DelimitedLogOptions?
        let control = DelimitedFormatPopUp(
            title: "Manual: CSV",
            options: .init(delimiter: ";"),
            onSelect: { selected = $0 },
            onCustomSeparator: {}
        )
        let coordinator = control.makeCoordinator()
        let menu = coordinator.makeMenu()
        let firstRow = try XCTUnwrap(menu.items.first { $0.title == "First row" })
        let submenu = try XCTUnwrap(firstRow.submenu)
        XCTAssertTrue(firstRow.isEnabled)
        submenu.update()

        for (index, mode) in DelimitedLogOptions.HeaderMode.allCases.enumerated() {
            XCTAssertTrue(submenu.items[index].isEnabled)
            XCTAssertNotNil(submenu.items[index].target)
            submenu.performActionForItem(at: index)
            XCTAssertEqual(selected, .init(delimiter: ";", headerMode: mode))
        }
    }

    func testTrackingKeepsSubmenuAndUsesLatestOptions() throws {
        var selected: DelimitedLogOptions?
        let control = DelimitedFormatPopUp(
            title: "Auto: CSV",
            options: .init(),
            onSelect: { selected = $0 },
            onCustomSeparator: {}
        )
        let coordinator = control.makeCoordinator()
        let menu = coordinator.makeMenu()
        let submenu = try XCTUnwrap(menu.items.first { $0.title == "First row" }?.submenu)
        coordinator.menuWillOpen(menu)
        XCTAssertTrue(coordinator.isTracking)
        coordinator.parent = DelimitedFormatPopUp(
            title: "Manual: CSV",
            options: .init(delimiter: "|", headerMode: .noHeaders),
            onSelect: { selected = $0 },
            onCustomSeparator: {}
        )
        XCTAssertTrue(menu.items.last?.submenu === submenu)
        submenu.performActionForItem(at: 1)
        XCTAssertEqual(selected, .init(delimiter: "|", headerMode: .headers))
        coordinator.menuDidClose(menu)
        XCTAssertFalse(coordinator.isTracking)
        coordinator.menuWillOpen(menu)
        XCTAssertEqual(submenu.items[2].state, .on)
        XCTAssertEqual(submenu.items[1].state, .off)
    }

    func testSeparatorAndAutomaticActionsAndNoCircleImages() throws {
        var selected: DelimitedLogOptions?
        var customRequested = false
        let control = DelimitedFormatPopUp(
            title: "Manual: CSV",
            options: .init(delimiter: ";", headerMode: .headers),
            onSelect: { selected = $0 },
            onCustomSeparator: { customRequested = true }
        )
        let coordinator = control.makeCoordinator()
        let menu = coordinator.makeMenu()
        let commaIndex = try XCTUnwrap(menu.items.firstIndex { $0.title == "Comma (,)" })
        menu.performActionForItem(at: commaIndex)
        XCTAssertEqual(selected, .init(delimiter: ",", headerMode: .headers))
        let automaticIndex = try XCTUnwrap(menu.items.firstIndex { $0.title == "Automatic format" })
        menu.performActionForItem(at: automaticIndex)
        XCTAssertEqual(selected, .init())
        let customIndex = try XCTUnwrap(menu.items.firstIndex { $0.title == "Custom separator…" })
        menu.performActionForItem(at: customIndex)
        XCTAssertTrue(customRequested)
        XCTAssertTrue(menu.items.allSatisfy { $0.image == nil })
    }
}
