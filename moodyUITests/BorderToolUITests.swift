//
//  BorderToolUITests.swift
//  moodyUITests
//
//  Tools ▸ Add Border… opens its sheet from the keyboard and Cancel closes it.
//  Launches with -inMemoryStore so the user's real library is untouched.
//

import XCTest

final class BorderToolUITests: XCTestCase {
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

    func testShortcutOpensTheSheetAndCancelClosesIt() {
        app.typeKey("b", modifierFlags: [.command, .shift])
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))
        XCTAssertTrue(sheet.buttons["Choose Images…"].exists)

        sheet.buttons["Cancel"].click()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 3))
    }
}
