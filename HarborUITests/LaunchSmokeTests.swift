import XCTest

final class LaunchSmokeTests: XCTestCase {
    func testFreshLaunchShowsLoginScreen() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Harbor"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["Email"].exists)
        XCTAssertTrue(app.secureTextFields["Password"].exists)
        XCTAssertTrue(app.buttons["Sign In"].exists)
        capture("Login", app: app)
    }

    func testSignedInDesignNavigationShowsPrimaryScreens() {
        let app = XCUIApplication()
        app.launchArguments.append("-HarborUITestSignedIn")
        app.launch()

        let homeTab = app.buttons["harbor.tab.home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10))
        XCTAssertTrue(homeTab.isSelected)
        XCTAssertTrue(app.descendants(matching: .any)["harbor.home.wordmark"].exists)
        capture("Home", app: app)

        let discoverTab = app.buttons["harbor.tab.discover"]
        discoverTab.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["harbor.discover.header"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(discoverTab.isSelected)
        capture("Discover", app: app)

        let libraryTab = app.buttons["harbor.tab.library"]
        libraryTab.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["harbor.library.header"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(libraryTab.isSelected)
        capture("Library", app: app)

        let settingsTab = app.buttons["harbor.tab.settings"]
        settingsTab.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["harbor.settings.header"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(settingsTab.isSelected)
        capture("Settings", app: app)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Harbor-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
