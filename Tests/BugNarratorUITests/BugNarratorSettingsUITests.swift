import AppKit
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
    func testSettingsAtAGlanceStatusRowsExist() throws {
        let app = launchSettingsApp(scope: "at-a-glance-status")
        defer { app.terminate() }

        let settingsWindow = app.windows["BugNarrator Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        waitForSettingsLayout()

        XCTAssertTrue(app.descendants(matching: .any)["OpenAI status: Needs setup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["GitHub export status: Needs setup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Jira export status: Needs setup"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsCredentialFieldsAcceptTypingWithoutLockingWindow() throws {
        let app = launchSettingsApp(scope: "credential-fields-editable")
        defer { app.terminate() }

        let settingsWindow = app.windows["BugNarrator Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        waitForSettingsLayout()

        let openAIKeyField = app.textFields["OpenAI API Key"]
        XCTAssertTrue(waitForSettingsElement(openAIKeyField, in: settingsWindow))
        clickWhenHittable(openAIKeyField, in: settingsWindow)
        openAIKeyField.typeText("sk-smoke-test")
        XCTAssertTrue(settingsWindow.exists)

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
    func testSettingsDialogCoversControlsFieldsButtonsAndScrollContainer() throws {
        let app = launchSettingsApp(scope: "settings-dialog-full-coverage")
        defer { app.terminate() }

        let settingsWindow = app.windows["BugNarrator Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        waitForSettingsLayout()
        XCTAssertTrue(settingsWindow.scrollViews.firstMatch.exists)

        let openAIKeyField = app.textFields["OpenAI API Key"]
        XCTAssertTrue(waitForSettingsElement(openAIKeyField, in: settingsWindow))
        replaceText(in: openAIKeyField, with: "sk-ui-test")
        XCTAssertTrue(button(matchingAnyOf: ["Save & Validate Key", "Validate Key"], in: app).exists)

        let modelField = app.textFields["Transcription model"]
        XCTAssertTrue(waitForSettingsElement(modelField, in: settingsWindow))
        replaceText(in: modelField, with: "whisper-1")

        let languageField = app.textFields["Transcription language hint"]
        XCTAssertTrue(waitForSettingsElement(languageField, in: settingsWindow))
        replaceText(in: languageField, with: "en")

        let promptEditor = app.textViews["Transcription prompt"]
        XCTAssertTrue(waitForSettingsElement(promptEditor, in: settingsWindow))
        replaceText(in: promptEditor, with: "Capture product defects and exact reproduction steps.")

        let extractionModelField = app.textFields["Issue extraction model"]
        XCTAssertTrue(waitForSettingsElement(extractionModelField, in: settingsWindow))
        replaceText(in: extractionModelField, with: "gpt-4.1-mini")

        for checkboxLabel in [
            "Run issue extraction automatically after transcription",
            "Auto-copy transcript to clipboard",
            "Open BugNarrator at startup",
            "Debug mode enables verbose local diagnostics"
        ] {
            let checkbox = settingsWindow.checkBoxes[checkboxLabel]
            XCTAssertTrue(waitForSettingsElement(checkbox, in: settingsWindow), checkboxLabel)
            XCTAssertTrue(checkbox.isEnabled, checkboxLabel)
        }

        let assignButton = app.buttons["Assign shortcut for Start Recording"].firstMatch
        XCTAssertTrue(waitForSettingsElement(assignButton, in: settingsWindow), "Assign")
        let clearButton = app.buttons["Clear shortcut for Start Recording"].firstMatch
        XCTAssertTrue(waitForSettingsElement(clearButton, in: settingsWindow), "Clear")

        let gitHubTokenField = app.textFields["GitHub personal access token"]
        XCTAssertTrue(waitForSettingsElement(gitHubTokenField, in: settingsWindow))
        replaceText(in: gitHubTokenField, with: "github_pat_ui_test")

        let gitHubOwnerField = app.textFields["GitHub repository owner"]
        XCTAssertTrue(waitForSettingsElement(gitHubOwnerField, in: settingsWindow))
        replaceText(in: gitHubOwnerField, with: "deffenda")

        let gitHubRepoField = app.textFields["GitHub repository name"]
        XCTAssertTrue(waitForSettingsElement(gitHubRepoField, in: settingsWindow))
        replaceText(in: gitHubRepoField, with: "bug-narrator")

        let gitHubLabelsField = app.textFields["GitHub default labels"]
        XCTAssertTrue(waitForSettingsElement(gitHubLabelsField, in: settingsWindow))
        replaceText(in: gitHubLabelsField, with: "bug, ui-test")

        let loadGitHubButton = button(matchingAnyOf: ["Save & Load GitHub Repos", "Load GitHub Repos", "Refresh GitHub Repos"], in: app)
        XCTAssertTrue(waitForSettingsElement(loadGitHubButton, in: settingsWindow))
        XCTAssertTrue(loadGitHubButton.isEnabled)
        loadGitHubButton.click()
        XCTAssertTrue(settingsWindow.exists)

        let jiraURLField = app.textFields["Jira Cloud URL"]
        XCTAssertTrue(waitForSettingsElement(jiraURLField, in: settingsWindow))
        replaceText(in: jiraURLField, with: "https://example.atlassian.net")

        let jiraEmailField = app.textFields["Jira email"]
        XCTAssertTrue(waitForSettingsElement(jiraEmailField, in: settingsWindow))
        replaceText(in: jiraEmailField, with: "tester@example.com")

        let jiraTokenField = app.textFields["Jira API token"]
        XCTAssertTrue(waitForSettingsElement(jiraTokenField, in: settingsWindow))
        replaceText(in: jiraTokenField, with: "jira-ui-test-token")

        let loadJiraButton = button(matchingAnyOf: ["Save & Load Jira Projects", "Load Jira Projects", "Refresh Jira Projects"], in: app)
        XCTAssertTrue(waitForSettingsElement(loadJiraButton, in: settingsWindow))
        XCTAssertTrue(loadJiraButton.isEnabled)
        loadJiraButton.click()
        XCTAssertTrue(settingsWindow.exists)
    }

    @MainActor
    func testSessionLibraryDialogCoversIssueEditingAndExportActions() throws {
        let app = launchSessionLibraryApp(scope: "session-library-export-coverage")
        defer { app.terminate() }

        let sessionsWindow = app.windows["BugNarrator Sessions"]
        XCTAssertTrue(sessionsWindow.waitForExistence(timeout: 5))
        waitForSettingsLayout()
        let scrollableContainerCount = sessionsWindow.scrollViews.count + sessionsWindow.tables.count + sessionsWindow.outlines.count
        XCTAssertGreaterThanOrEqual(scrollableContainerCount, 1)

        XCTAssertTrue(app.descendants(matching: .any)["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["All Sessions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Sort sessions"].waitForExistence(timeout: 5))

        let searchField = app.textFields["Search sessions"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        replaceText(in: searchField, with: "export")
        let clearSearch = app.buttons["Clear search"]
        XCTAssertTrue(clearSearch.waitForExistence(timeout: 3))
        clearSearch.click()

        let issueSelection = app.checkBoxes["Select issue Settings export smoke issue for export"]
        XCTAssertTrue(waitForElement(issueSelection, in: sessionsWindow))
        XCTAssertTrue(issueSelection.isEnabled)

        let issueTitle = app.textFields["Issue title for Settings export smoke issue"]
        XCTAssertTrue(waitForElement(issueTitle, in: sessionsWindow))
        replaceText(in: issueTitle, with: "Settings export smoke issue updated")

        let component = app.textFields["Suggested component for Settings export smoke issue updated"]
        XCTAssertTrue(waitForElement(component, in: sessionsWindow))
        replaceText(in: component, with: "Session Library Export")

        let gitHubOwner = app.textFields["GitHub repository owner for Settings export smoke issue updated"]
        XCTAssertTrue(waitForElement(gitHubOwner, in: sessionsWindow))
        replaceText(in: gitHubOwner, with: "deffenda")

        let gitHubRepo = app.textFields["GitHub repository name for Settings export smoke issue updated"]
        XCTAssertTrue(waitForElement(gitHubRepo, in: sessionsWindow))
        replaceText(in: gitHubRepo, with: "bug-narrator")

        let gitHubLabels = app.textFields["GitHub labels for Settings export smoke issue updated"]
        XCTAssertTrue(waitForElement(gitHubLabels, in: sessionsWindow))
        replaceText(in: gitHubLabels, with: "bug, ui-test")

        let jiraProject = app.textFields["Jira project key for Settings export smoke issue updated"]
        XCTAssertTrue(waitForElement(jiraProject, in: sessionsWindow))
        replaceText(in: jiraProject, with: "UCAP")

        let jiraIssueType = app.textFields["Jira issue type for Settings export smoke issue updated"]
        XCTAssertTrue(waitForElement(jiraIssueType, in: sessionsWindow))
        replaceText(in: jiraIssueType, with: "Task")

        let dedupHint = app.textFields["Deduplication hint for Settings export smoke issue updated"]
        XCTAssertTrue(waitForElement(dedupHint, in: sessionsWindow))
        replaceText(in: dedupHint, with: "settings-export-smoke-updated")

        let actionEditor = app.textViews["Action"]
        XCTAssertTrue(actionEditor.waitForExistence(timeout: 5))

        let expectedEditor = app.textViews["Expected"]
        XCTAssertTrue(expectedEditor.waitForExistence(timeout: 5))

        let actualEditor = app.textViews["Actual"]
        XCTAssertTrue(actualEditor.waitForExistence(timeout: 5))

        let sendGitHub = app.buttons["Send to GitHub"]
        XCTAssertTrue(waitForElement(sendGitHub, in: sessionsWindow))
        XCTAssertTrue(sendGitHub.isEnabled)
        sendGitHub.click()
        XCTAssertTrue(sessionsWindow.exists)

        let sendJira = app.buttons["Send to Jira"]
        XCTAssertTrue(waitForElement(sendJira, in: sessionsWindow))
        XCTAssertTrue(sendJira.isEnabled)
        sendJira.click()
        XCTAssertTrue(sessionsWindow.exists)
    }

    @MainActor
    func testRecordingControlsDialogCoversButtonsAndSafeStateTransitions() throws {
        let app = launchRecordingControlsApp(scope: "recording-controls-coverage")
        defer { app.terminate() }

        let controlsWindow = app.windows["BugNarrator Controls"]
        XCTAssertTrue(controlsWindow.waitForExistence(timeout: 5))
        waitForSettingsLayout()

        let status = app.descendants(matching: .any)["Recording status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))

        let startButton = app.buttons["Start Recording"]
        let stopButton = app.buttons["Stop Recording"]
        let screenshotButton = app.buttons["Capture Screenshot"]
        let closeButton = app.buttons["Close"]

        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5))
        XCTAssertTrue(screenshotButton.waitForExistence(timeout: 5))
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        XCTAssertTrue(startButton.isEnabled)
        XCTAssertFalse(stopButton.isEnabled)
        XCTAssertFalse(screenshotButton.isEnabled)

        startButton.click()
        XCTAssertTrue(waitUntil(stopButton, isEnabled: true))
        XCTAssertTrue(waitUntil(screenshotButton, isEnabled: true))
        XCTAssertFalse(startButton.isEnabled)

        screenshotButton.click()
        XCTAssertTrue(controlsWindow.exists)
        waitForSettingsLayout(interval: 0.5)
        XCTAssertTrue(waitUntil(stopButton, isEnabled: true))

        stopButton.click()
        XCTAssertTrue(waitUntil(startButton, isEnabled: true, timeout: 15))
        XCTAssertFalse(stopButton.isEnabled)
        XCTAssertFalse(screenshotButton.isEnabled)
    }

    @MainActor
    private func launchSettingsApp(scope: String, launchAtLoginStatus: String = "disabled") -> XCUIApplication {
        launchApp(scope: scope, openSettings: true, launchAtLoginStatus: launchAtLoginStatus)
    }

    @MainActor
    private func launchSessionLibraryApp(scope: String) -> XCUIApplication {
        launchApp(scope: scope, openSessionLibrary: true, seedSessionLibrary: true)
    }

    @MainActor
    private func launchRecordingControlsApp(scope: String) -> XCUIApplication {
        launchApp(scope: scope, openRecordingControls: true, seedSessionLibrary: true)
    }

    @MainActor
    private func launchApp(
        scope: String,
        openSettings: Bool = false,
        openSessionLibrary: Bool = false,
        openRecordingControls: Bool = false,
        seedSessionLibrary: Bool = false,
        launchAtLoginStatus: String = "disabled"
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BUGNARRATOR_SETTINGS_UI_SMOKE_TEST"] = "1"
        app.launchEnvironment["BUGNARRATOR_UI_TEST_MODE"] = "1"
        app.launchEnvironment["BUGNARRATOR_UI_TEST_SAFE_SERVICES"] = "1"
        app.launchEnvironment["BUGNARRATOR_OPEN_SETTINGS_ON_LAUNCH"] = openSettings ? "1" : "0"
        app.launchEnvironment["BUGNARRATOR_OPEN_SESSION_LIBRARY_ON_LAUNCH"] = openSessionLibrary ? "1" : "0"
        app.launchEnvironment["BUGNARRATOR_OPEN_RECORDING_CONTROLS_ON_LAUNCH"] = openRecordingControls ? "1" : "0"
        app.launchEnvironment["BUGNARRATOR_SEED_SESSION_LIBRARY_UI_TEST_DATA"] = seedSessionLibrary ? "1" : "0"
        app.launchEnvironment["BUGNARRATOR_SETTINGS_UI_SMOKE_SCOPE"] = scope
        app.launchEnvironment["BUGNARRATOR_TEST_LAUNCH_AT_LOGIN_STATUS"] = launchAtLoginStatus
        app.launch()
        return app
    }

    @MainActor
    private func waitForSettingsElement(_ element: XCUIElement, in settingsWindow: XCUIElement) -> Bool {
        if element.waitForExistence(timeout: 4), element.isHittable {
            return true
        }

        let labeledScrollView = settingsWindow.scrollViews["Settings scroll area"].firstMatch
        let scrollView = labeledScrollView.exists ? labeledScrollView : settingsWindow.scrollViews.firstMatch
        guard scrollView.waitForExistence(timeout: 2) else {
            return false
        }

        for deltaY in [-700, 700] {
            for _ in 0..<8 {
                scrollView.scroll(byDeltaX: 0, deltaY: CGFloat(deltaY))
                waitForSettingsLayout(interval: 0.15)
                if element.waitForExistence(timeout: 0.5), element.isHittable {
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
        let labeledScrollView = settingsWindow.scrollViews["Settings scroll area"].firstMatch
        let scrollView = labeledScrollView.exists ? labeledScrollView : settingsWindow.scrollViews.firstMatch
        for deltaY in [-700, 700] {
            for _ in 0..<8 where !element.isHittable {
                scrollView.scroll(byDeltaX: 0, deltaY: CGFloat(deltaY))
                waitForSettingsLayout(interval: 0.15)
            }
        }

        XCTAssertTrue(element.isHittable, file: file, line: line)
        element.click()
    }

    @MainActor
    private func waitForElement(_ element: XCUIElement, in window: XCUIElement) -> Bool {
        if element.waitForExistence(timeout: 4), isReadyForInput(element) {
            return true
        }

        let preferredScrollLabels = ["Session detail", "Settings scroll area", "Session filters"]
        var scrollViews: [XCUIElement] = preferredScrollLabels
            .map { window.scrollViews[$0].firstMatch }
            .filter(\.exists)
        scrollViews.append(contentsOf: (0..<window.scrollViews.count).map {
            window.scrollViews.element(boundBy: $0)
        })

        for scrollView in scrollViews {
            guard scrollView.exists, scrollView.isHittable else { continue }

            for deltaY in [-650, 650] {
                for _ in 0..<6 where !isReadyForInput(element) {
                    scrollView.scroll(byDeltaX: 0, deltaY: CGFloat(deltaY))
                    waitForSettingsLayout(interval: 0.12)
                    if element.waitForExistence(timeout: 0.4), isReadyForInput(element) {
                        return true
                    }
                }
            }
        }

        return isReadyForInput(element)
    }

    @MainActor
    private func replaceText(in element: XCUIElement, with text: String) {
        XCTAssertTrue(element.exists)
        let deadline = Date().addingTimeInterval(5)
        while !isReadyForInput(element), Date() < deadline {
            waitForSettingsLayout(interval: 0.15)
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertTrue(element.isEnabled || element.elementType == .textView)
        element.click()
        element.typeKey("a", modifierFlags: .command)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        element.typeKey("v", modifierFlags: .command)
    }

    @MainActor
    private func isReadyForInput(_ element: XCUIElement) -> Bool {
        element.exists && element.isHittable && (element.isEnabled || element.elementType == .textView)
    }

    @MainActor
    private func button(matchingAnyOf labels: [String], in app: XCUIApplication) -> XCUIElement {
        for label in labels {
            let button = app.buttons[label]
            if button.exists {
                return button
            }
        }

        return app.buttons[labels[0]]
    }

    @MainActor
    private func waitUntil(_ element: XCUIElement, isEnabled expected: Bool, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists, element.isEnabled == expected {
                return true
            }
            waitForSettingsLayout(interval: 0.15)
        } while Date() < deadline

        return element.exists && element.isEnabled == expected
    }

    @MainActor
    private func waitForSettingsLayout(interval: TimeInterval = 0.75) {
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }
}
