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

        let homeTab = navigationButton("home", app: app)
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10))
        XCTAssertTrue(homeTab.isSelected)
        XCTAssertTrue(app.descendants(matching: .any)["harbor.home.wordmark"].exists)
        capture("Home", app: app)

        let discoverTab = navigationButton("discover", app: app)
        discoverTab.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["harbor.discover.header"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(discoverTab.isSelected)
        capture("Discover", app: app)

        let libraryTab = navigationButton("library", app: app)
        libraryTab.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["harbor.library.header"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(libraryTab.isSelected)
        capture("Library", app: app)

        let settingsTab = navigationButton("settings", app: app)
        settingsTab.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["harbor.settings.header"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(settingsTab.isSelected)
        capture("Settings", app: app)
    }

    private func navigationButton(_ name: String, app: XCUIApplication) -> XCUIElement {
        let compact = app.buttons["harbor.tab.\(name)"]
        if compact.waitForExistence(timeout: 2) { return compact }
        return app.buttons["harbor.sidebar.\(name)"]
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Harbor-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
