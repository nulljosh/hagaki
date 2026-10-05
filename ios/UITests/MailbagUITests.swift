import XCTest

/// End to end against the live demo inbox: open it, file everything, sign out.
extension NSPredicate {
    func wait(on element: XCUIElement, timeout: TimeInterval = 20) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: self, object: element)], timeout: timeout) == .completed
    }
}

final class MailbagUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    #if os(macOS)
    /// The Mac app is one number and one button: clear the demo inbox, then sign out.
    func testDemoClearsInboxThenSignsOut() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "YES"]
        app.launch()
        let clear = app.buttons["clear"]
        if !clear.waitForExistence(timeout: 20) { print("DBG-START\n" + app.debugDescription + "\nDBG-END") }
        XCTAssertTrue(clear.exists, "inbox never loaded")
        // SwiftUI on the Mac puts a Text's string in `value`, not `label`
        let count = app.staticTexts["count"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertTrue(NSPredicate(format: "value == '10'").wait(on: count), "demo inbox should show 10")
        // A click on a window that lost focus only activates it, so bring the app forward and retry.
        let zero = app.images["zero"]
        for _ in 0..<3 where !zero.exists {
            app.activate()
            if clear.exists { clear.click() }
            _ = zero.waitForExistence(timeout: 12)
        }
        XCTAssertTrue(zero.exists, "inbox did not clear")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value == 'Demo inbox zero'")).firstMatch.exists)
        let signOut = app.buttons["signout"]
        for _ in 0..<3 where !signOut.exists {
            app.activate()
            app.buttons["settings"].click()
            _ = signOut.waitForExistence(timeout: 6)
        }
        if !signOut.exists { print("DBG-START\n" + app.debugDescription + "\nDBG-END") }
        XCTAssertTrue(signOut.exists, "settings did not open")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value == 'Demo inbox' OR label == 'Demo inbox'")).firstMatch.exists, "settings should list the account")
        signOut.click()
        XCTAssertTrue(app.buttons["Try the demo inbox"].waitForExistence(timeout: 10), "sign out did not return to sign-in")
    }
    #else
    func testDemoFilesEverythingThenSignsOut() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "YES"]
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
