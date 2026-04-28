import XCTest

final class BugNarratorSettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testStartupToggleIsEnabledWhenLoginItemIsNotRegistered() throws {
        let app = launchSettingsApp(scope: "startup-toggle-not-found", launchAtLoginStatus: "not_found")
        defer { app.terminate() }

        let settingsWindow = app.windows["BugNarrator Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        waitForSettingsLayout()

        let startupToggle = settingsWindow.checkBoxes["Open BugNarrator at startup"]
        XCTAssertTrue(startupToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(startupToggle.isEnabled)
    }

    @MainActor
    func testSettingsCredentialFieldsAcceptTypingWithoutLockingWindow() throws {
        let app = launchSettingsApp(scope: "credential-fields-editable")
        defer { app.terminate() }

        let settingsWindow = app.windows["BugNarrator Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        waitForSettingsLayout()

        let gitHubTokenField = app.textFields["GitHub personal access token"]
        XCTAssertTrue(waitForSettingsElement(gitHubTokenField, in: settingsWindow))
        clickWhenHittable(gitHubTokenField, in: settingsWindow)
        gitHubTokenField.typeText("github_pat_smoke_test")
        XCTAssertTrue(settingsWindow.exists)

        let gitHubLabelsField = app.textFields["GitHub default labels"]
        XCTAssertTrue(waitForSettingsElement(gitHubLabelsField, in: settingsWindow))
        clickWhenHittable(gitHubLabelsField, in: settingsWindow)
        gitHubLabelsField.typeText("bug,smoke")
        XCTAssertTrue(settingsWindow.exists)

        let jiraTokenField = app.textFields["Jira API token"]
        XCTAssertTrue(waitForSettingsElement(jiraTokenField, in: settingsWindow))
        clickWhenHittable(jiraTokenField, in: settingsWindow)
        jiraTokenField.typeText("jira-smoke-token")
        XCTAssertTrue(settingsWindow.exists)
    }

    @MainActor
    private func launchSettingsApp(scope: String, launchAtLoginStatus: String = "disabled") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BUGNARRATOR_SETTINGS_UI_SMOKE_TEST"] = "1"
        app.launchEnvironment["BUGNARRATOR_OPEN_SETTINGS_ON_LAUNCH"] = "1"
        app.launchEnvironment["BUGNARRATOR_SETTINGS_UI_SMOKE_SCOPE"] = scope
        app.launchEnvironment["BUGNARRATOR_TEST_LAUNCH_AT_LOGIN_STATUS"] = launchAtLoginStatus
        app.launch()
        return app
    }

    @MainActor
    private func waitForSettingsElement(_ element: XCUIElement, in settingsWindow: XCUIElement) -> Bool {
        if element.waitForExistence(timeout: 4) {
            return true
        }

        let scrollView = settingsWindow.scrollViews.firstMatch
        guard scrollView.waitForExistence(timeout: 2) else {
            return false
        }

        for deltaY in [-700, 700] {
            for _ in 0..<8 {
                scrollView.scroll(byDeltaX: 0, deltaY: CGFloat(deltaY))
                waitForSettingsLayout(interval: 0.15)
                if element.waitForExistence(timeout: 0.5) {
                    return true
                }
            }
        }

        return false
    }

    @MainActor
    private func clickWhenHittable(
        _ element: XCUIElement,
        in settingsWindow: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let scrollView = settingsWindow.scrollViews.firstMatch
        for _ in 0..<12 where !element.isHittable {
            scrollView.scroll(byDeltaX: 0, deltaY: -700)
        }

        XCTAssertTrue(element.isHittable, file: file, line: line)
        element.click()
    }

    @MainActor
    private func waitForSettingsLayout(interval: TimeInterval = 0.75) {
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }
}
