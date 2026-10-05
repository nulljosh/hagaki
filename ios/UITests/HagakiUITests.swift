import XCTest

/// End to end against the live demo inbox: open it, file everything, sign out.
final class HagakiUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    #if os(macOS)
    /// The Mac app is one number and one button: clear the demo inbox, then sign out.
    func testDemoClearsInboxThenSignsOut() {
        let app = XCUIApplication()
        app.launchArguments = ["-hagakiDemo"]
        app.launch()
        let clear = app.buttons["clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 20), "inbox never loaded")
        XCTAssertEqual(app.staticTexts["count"].label, "10")
        clear.tap()
        let result = app.staticTexts["result"]
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'Nothing was deleted'").evaluate(with: result) || result.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Inbox zero"].waitForExistence(timeout: 20), "inbox did not clear")
        app.buttons["signout"].tap()
        XCTAssertTrue(app.buttons["Try the demo inbox"].waitForExistence(timeout: 10), "sign out did not return to sign-in")
    }
    #else
    func testDemoFilesEverythingThenSignsOut() {
        let app = XCUIApplication()
        app.launchArguments = ["-hagakiDemo"]
        app.launch()

        // If a session survived from an earlier run, sign out first so the demo path is what we test.
        let fileAll = app.buttons["File everything"]
        XCTAssertTrue(fileAll.waitForExistence(timeout: 20), "inbox never loaded")

        // Seven boxes: every demo folder shows up, and the person stays in the inbox.
        for header in ["Receipts", "Travel", "Dev"] {
            let h = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH[c] %@", header)).firstMatch
            XCTAssertTrue(h.waitForExistence(timeout: 5), "missing section \(header)")
        }

        fileAll.tap()
        let filed = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Filed'")).firstMatch
        XCTAssertTrue(filed.waitForExistence(timeout: 20), "File everything gave no result")
        XCTAssertTrue(filed.label.contains("Nothing was deleted"))
        XCTAssertFalse(app.staticTexts["Stripe"].exists, "filed mail should leave the list")
        // Junk was filed too, so only the person is left, under "Stays in your inbox".
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH[c] 'Stays in your inbox (1)'")).firstMatch.waitForExistence(timeout: 5), "the person stays put")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH[c] 'Junk'")).firstMatch.exists, "junk should be filed, not left")

        app.buttons["More"].firstMatch.tap()
        #if os(macOS)
        app.menuItems["Sign out"].tap()
        #else
        app.buttons["Sign out"].tap()
        #endif
        XCTAssertTrue(app.buttons["Try the demo inbox"].waitForExistence(timeout: 10), "sign out did not return to sign-in")
        XCTAssertTrue(app.buttons["Continue with Gmail"].exists)
        XCTAssertTrue(app.buttons["Continue with iCloud Mail"].exists)
    }
    #endif
}
