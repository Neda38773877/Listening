import XCTest

final class HoerenTrainerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testLaunchShowsMeetingsTab() {
        XCTAssertTrue(app.navigationBars["Meetings"].waitForExistence(timeout: 10))
    }

    func testImportSheetOpens() {
        XCTAssertTrue(app.buttons["Import"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Import"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Import meeting"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
    }

    func testTabsExist() {
        let tabNames = ["Words", "Review", "Search", "Progress", "Settings"]
        for name in tabNames {
            XCTAssertTrue(app.buttons[name].firstMatch.waitForExistence(timeout: 5), "Tab '\(name)' not found")
        }
    }
}
