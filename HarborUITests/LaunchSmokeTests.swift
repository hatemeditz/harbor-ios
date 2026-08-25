import XCTest

final class LaunchSmokeTests: XCTestCase {
    func testFreshLaunchShowsLoginScreen() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Harbor"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["Email"].exists)
        XCTAssertTrue(app.secureTextFields["Password"].exists)
        XCTAssertTrue(app.buttons["Sign In"].exists)
    }
}
