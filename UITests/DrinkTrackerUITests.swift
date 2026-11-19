import XCTest

final class DrinkTrackerUITests: XCTestCase {
    @MainActor func testTrackingHistoryAndResume() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let action = app.buttons["trackingAction"]
        XCTAssertTrue(action.waitForExistence(timeout: 15))
        XCTAssertTrue(action.label.contains("Start Tracking"))
        XCTAssertFalse(app.buttons["water-plus"].isEnabled)
        action.tap()
        XCTAssertTrue(app.buttons["water-plus"].waitForExistence(timeout: 5))
        let plus = app.buttons["water-plus"]
        XCTAssertTrue(plus.isEnabled)
        plus.tap(); plus.tap()
        XCTAssertTrue(app.staticTexts["water-total"].label.contains("2"))
        action.tap()
        XCTAssertTrue(action.label.contains("Resume"))
        XCTAssertFalse(plus.isEnabled)
        app.segmentedControls.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "History with paused current day"; screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons.matching(NSPredicate(format: "label CONTAINS '🍺'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Tracking activity"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["water-plus"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.segmentedControls.buttons["Tracking"].tap()
        action.tap()
        XCTAssertTrue(app.buttons["water-plus"].isEnabled)
        XCTAssertTrue(app.staticTexts["water-total"].label.contains("2"))
        let tracking = XCTAttachment(screenshot: app.screenshot())
        tracking.name = "Tracking after resume"; tracking.lifetime = .keepAlways
        add(tracking)
    }
}
