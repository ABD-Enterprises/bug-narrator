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

        XCTAssertTrue(app.descendants(matching: .any)["AI provider status: Needs setup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["GitHub export status: Needs setup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Jira export status: Needs setup"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSavedOpenAIKeyKeepsSettingsCredentialActionsEnabled() throws {
        let app = launchSettingsApp(scope: "saved-openai-key-actions", seedCredentials: true)
        defer { app.terminate() }

        let settingsWindow = app.windows["BugNarrator Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        waitForSettingsLayout()

        XCTAssertTrue(app.descendants(matching: .any)["AI provider status: Ready"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved key"].waitForExistence(timeout: 5))

        let validateKeyButton = app.buttons["Validate Key"]
        XCTAssertTrue(waitForSettingsElement(validateKeyButton, in: settingsWindow))
        XCTAssertTrue(validateKeyButton.isEnabled)

        let removeKeyButton = app.buttons["Remove Key"]
        XCTAssertTrue(waitForSettingsElement(removeKeyButton, in: settingsWindow))
        XCTAssertTrue(removeKeyButton.isEnabled)
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

        XCTAssertTrue(app.descendants(matching: .any)["AI Provider Setup section"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Transcription Defaults section"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Issue Extraction section"].waitForExistence(timeout: 5))

        let openAIKeyField = app.textFields["OpenAI API Key"]
        XCTAssertTrue(waitForSettingsElement(openAIKeyField, in: settingsWindow))
        replaceText(in: openAIKeyField, with: "sk-ui-test")
        XCTAssertTrue(button(matchingAnyOf: ["Save & Validate Key", "Validate Key"], in: app).exists)

        let modelSelector = modelControl(named: "Transcription model", in: app)
        XCTAssertTrue(waitForSettingsElement(modelSelector, in: settingsWindow))
        XCTAssertTrue(modelSelector.isEnabled)

        let languageField = app.textFields["Transcription language hint"]
        XCTAssertTrue(waitForSettingsElement(languageField, in: settingsWindow))
        replaceText(in: languageField, with: "en")

        let promptEditor = app.textViews["Transcription prompt"]
        XCTAssertTrue(waitForSettingsElement(promptEditor, in: settingsWindow))
        replaceText(in: promptEditor, with: "Capture product defects and exact reproduction steps.")

        let extractionModelSelector = modelControl(named: "Issue extraction model", in: app)
        XCTAssertTrue(waitForSettingsElement(extractionModelSelector, in: settingsWindow))
        XCTAssertTrue(extractionModelSelector.isEnabled)

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
        replaceText(in: gitHubOwnerField, with: "ABD-Enterprises")

        let gitHubRepoField = app.textFields["GitHub repository name"]
        XCTAssertTrue(waitForSettingsElement(gitHubRepoField, in: settingsWindow))
        replaceText(in: gitHubRepoField, with: "bug-narrator")

        let gitHubLabelsField = app.textFields["GitHub default labels"]
        XCTAssertTrue(waitForSettingsElement(gitHubLabelsField, in: settingsWindow))
        replaceText(in: gitHubLabelsField, with: "bug, ui-test")

        let loadGitHubButton = button(matchingAnyOf: ["Save & Load GitHub Repos", "Load GitHub Repos", "Refresh GitHub Repos"], in: app)
        XCTAssertTrue(waitForSettingsElement(loadGitHubButton, in: settingsWindow))
        XCTAssertTrue(waitForReady(loadGitHubButton), "Load GitHub Repos never became ready")
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
        XCTAssertTrue(waitForReady(loadJiraButton), "Load Jira Projects never became ready")
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
        XCTAssertTrue(waitForReady(clearSearch), "Clear search never became ready")
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
        replaceText(in: gitHubOwner, with: "ABD-Enterprises")

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
        XCTAssertTrue(waitForReady(sendGitHub), "Send to GitHub never became ready")
        sendGitHub.click()
        XCTAssertTrue(sessionsWindow.exists)

        let sendJira = app.buttons["Send to Jira"]
        XCTAssertTrue(waitForElement(sendJira, in: sessionsWindow))
        XCTAssertTrue(waitForReady(sendJira), "Send to Jira never became ready")
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

        // Start Recording is clicked below, so wait for it to be fully ready.
        // The others are asserted in their (disabled) initial state, so wait only
        // for attachment — controls in this separate window can attach well after
        // the window exists, which was the observed flake here.
        XCTAssertTrue(waitForReady(startButton), "Start Recording never became ready")
        XCTAssertTrue(waitForAttachment(stopButton), "Stop Recording never attached")
        XCTAssertTrue(waitForAttachment(screenshotButton), "Capture Screenshot never attached")
        XCTAssertTrue(waitForAttachment(closeButton), "Close never attached")
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
    private func launchSettingsApp(
        scope: String,
        launchAtLoginStatus: String = "disabled",
        seedCredentials: Bool = false
    ) -> XCUIApplication {
        launchApp(
            scope: scope,
            openSettings: true,
            seedSessionLibrary: seedCredentials,
            launchAtLoginStatus: launchAtLoginStatus
        )
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
    private func modelControl(named label: String, in app: XCUIApplication) -> XCUIElement {
        let popUpButton = app.popUpButtons[label].firstMatch
        if popUpButton.exists {
            return popUpButton
        }

        let button = app.buttons[label].firstMatch
        if button.exists {
            return button
        }

        return app.descendants(matching: .any)[label].firstMatch
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

        // Poll for readiness after scrolling rather than asserting hittability
        // once — the single-shot assert raced layout settling.
        XCTAssertTrue(waitForReady(element), "Element never became ready to click", file: file, line: line)
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
    private func replaceText(
        in element: XCUIElement,
        with text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // Poll for the composite input-ready state before interacting, rather than
        // asserting `isHittable`/`isEnabled` once after a fixed deadline — the
        // latter races element attachment/layout and was the primary flake source.
        XCTAssertTrue(
            waitForInputReady(element),
            "Element never became input-ready before typing",
            file: file,
            line: line
        )
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

    /// Polls until an element is fully ready for a positive interaction
    /// (attached, hittable, and enabled), pumping the run loop between checks.
    /// Use before clicking a control that is expected to be enabled — never for
    /// controls that are expected disabled (that state is real behavior; assert
    /// it with `waitForAttachment` + an explicit `XCTAssertFalse(isEnabled)` or
    /// `waitUntil(_:isEnabled:false)` instead).
    @MainActor
    private func waitForReady(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists, element.isHittable, element.isEnabled {
                return true
            }
            waitForSettingsLayout(interval: 0.15)
        } while Date() < deadline

        return element.exists && element.isHittable && element.isEnabled
    }

    /// Polls until an element is ready to receive text input (attached, hittable,
    /// and either enabled or a text view — text views report `isEnabled == false`
    /// while still editable). Use before typing into a field.
    @MainActor
    private func waitForInputReady(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if isReadyForInput(element) {
                return true
            }
            waitForSettingsLayout(interval: 0.15)
        } while Date() < deadline

        return isReadyForInput(element)
    }

    /// Polls only for attachment (existence) — the correct wait before asserting a
    /// control's *disabled*/negative state, which `waitForReady` cannot be used
    /// for (it requires `isEnabled`). Separate windows (e.g. Recording Controls)
    /// can attach their controls well after the window itself exists.
    @MainActor
    private func waitForAttachment(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists {
                return true
            }
            waitForSettingsLayout(interval: 0.15)
        } while Date() < deadline

        return element.exists
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
