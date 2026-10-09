//
//  SidebarRenameUITests.swift
//  moodyUITests
//
//  Inline rename in the sidebar, via double-click and the context menu.
//  Launches with -inMemoryStore so the user's real library is untouched.
//  Results are asserted through the window title, which mirrors the
//  selected row's name.
//

import XCTest

final class SidebarRenameUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    /// The first (and in these tests only) sidebar row.
    private var firstRow: XCUIElement {
        app.outlines.cells.firstMatch
    }

    /// The selected row's name, as mirrored in the window title by the
    /// detail view's navigationTitle. (The sidebar cell's own text isn't
    /// reliably queryable through XCUITest.)
    private func waitUntilSelectedNameIs(_ name: String) -> Bool {
        let window = app.windows.firstMatch
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if window.title == name {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    /// Creates an item via the toolbar "New" menu, accepting the default name from the
    /// automatic rename it starts in.
    private func createItem(_ menuItem: String, named initialName: String) -> XCUIElement {
        let newMenu = app.toolbars.menuButtons["New"].firstMatch
        XCTAssertTrue(newMenu.waitForExistence(timeout: 2), "New toolbar menu not visible")
        newMenu.click()
        app.menuItems[menuItem].click()
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntilSelectedNameIs(initialName), "\(initialName) row missing")
        return firstRow
    }

    private func typeNewName(_ newName: String) {
        // Give the field a moment to take focus from the sidebar's outline view.
        Thread.sleep(forTimeInterval: 0.5)
        app.typeKey("a", modifierFlags: .command)
        app.typeText(newName + "\r")
        XCTAssertTrue(waitUntilSelectedNameIs(newName), "\(newName) not shown after rename")
    }

    @MainActor
    func testDoubleClickRenamesBoard() {
        createItem("New Board", named: "Untitled Board").doubleClick()
        typeNewName("Double Clicked Board")
    }

    @MainActor
    func testContextMenuRenamesBoard() {
        createItem("New Board", named: "Untitled Board").rightClick()
        app.menuItems["Rename"].click()
        typeNewName("Menu Board")
    }

    @MainActor
    func testDoubleClickRenamesFolder() {
        createItem("New Folder", named: "Untitled Folder").doubleClick()
        typeNewName("Double Clicked Folder")
    }

    @MainActor
    func testContextMenuRenamesFolder() {
        createItem("New Folder", named: "Untitled Folder").rightClick()
        app.menuItems["Rename"].click()
        typeNewName("Menu Folder")
    }

    @MainActor
    func testContextMenuRenamesUnselectedRow() {
        // The second folder is created inside the selected first one and
        // becomes the selection; rename the (now unselected) parent at row 0.
        _ = createItem("New Folder", named: "Untitled Folder")
        _ = createItem("New Folder", named: "Untitled Folder")
        app.outlines.cells.element(boundBy: 0).rightClick()
        app.menuItems["Rename"].click()
        Thread.sleep(forTimeInterval: 0.5)
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Renamed Unselected\r")
        // Select it so the window title shows its name.
        app.outlines.cells.element(boundBy: 0).click()
        XCTAssertTrue(waitUntilSelectedNameIs("Renamed Unselected"))
    }
}
