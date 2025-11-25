import XCTest

final class SecretVaultUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        
        let app = XCUIApplication()
        // This argument tells the app to wipe data on launch
        app.launchArguments = ["--reset-state"]
        print("Launching app with arguments: \(app.launchArguments)")
        app.launch()
    }

    // MARK: - Helpers
    
    func setupPasswordAndUnlock(app: XCUIApplication) {
        // 1. Verify we are on setup screen
        let passwordField = app.secureTextFields["Enter password"]
        let confirmField = app.secureTextFields["Re-enter password"]
        
        if !passwordField.waitForExistence(timeout: 10.0) {
            print("DEBUG: Hierarchy at failure:\n\(app.debugDescription)")
            XCTFail("Should be on Setup Password screen (Password field not found). App might not have reset correctly.")
            return
        }
        
        // 2. Create a new password
        passwordField.tap()
        passwordField.typeText("TestPass123!")
        
        confirmField.tap()
        confirmField.typeText("TestPass123!")
        
        // Dismiss keyboard if needed (tap somewhere else)
        app.staticTexts["Welcome to Secret Vault"].tap()
        
        // 3. Tap Setup/Save button
        app.buttons["Create Vault"].tap()
        
        // 4. Handle potential unlock prompt if it doesn't auto-login
        if app.buttons["Unlock"].waitForExistence(timeout: 1.0) {
            let unlockField = app.secureTextFields["Password"]
            unlockField.tap()
            unlockField.typeText("TestPass123!")
            app.buttons["Unlock"].tap()
        }
    }

    private func openPhotosPicker(app: XCUIApplication) {
        let addPhotosButton = app.buttons["addPhotosButton"]
        XCTAssertTrue(addPhotosButton.waitForExistence(timeout: 5.0), "Add Photos toolbar button should exist")
        addPhotosButton.tap()

        // Handle the system Photos permission alert the first time it appears
        for _ in 0..<2 {
            if !handlePhotosPermissionIfNeeded(app: app) {
                break
            }
        }
    }

    @discardableResult
    private func handlePhotosPermissionIfNeeded(app: XCUIApplication) -> Bool {
        var handledAlert = false

        let monitor = addUIInterruptionMonitor(withDescription: "Photos Permission") { alert -> Bool in
            let affirmativeButtons = [
                "Allow Full Access",
                "Allow Access to All Photos",
                "Allow",
                "OK",
                "Continue"
            ]

            for label in affirmativeButtons {
                if alert.buttons[label].exists {
                    alert.buttons[label].tap()
                    handledAlert = true
                    return true
                }
            }
            return false
        }

        defer { removeUIInterruptionMonitor(monitor) }

        app.tap()
        return handledAlert
    }

    // MARK: - Tests

    func testUnlockFlow() throws {
        let app = XCUIApplication()
        setupPasswordAndUnlock(app: app)
        
        // Verify we are inside the vault
        let navBar = app.navigationBars["Hidden Items"]
        XCTAssertTrue(navBar.waitForExistence(timeout: 2.0), "Should be inside the vault")
    }
    
    func testLockVault() throws {
        let app = XCUIApplication()
        setupPasswordAndUnlock(app: app)
        
        // 1. Open Menu
        // The button has an image "ellipsis.circle" but SwiftUI might expose it as "More"
        // or simply by its image name if no label is provided.
        // Based on the error, it is exposed as "More".
        let menuButton = app.buttons["More"]
        
        // Wait for the view to transition and the button to appear
        XCTAssertTrue(menuButton.waitForExistence(timeout: 10.0), "Menu button should exist")
        
        // Force tap to avoid "Failed to scroll to visible" errors in toolbar
        menuButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        
        // 2. Tap Lock
        let lockButton = app.buttons["Lock Vault"]
        XCTAssertTrue(lockButton.waitForExistence(timeout: 2.0), "Lock button should appear in menu")
        lockButton.tap()
        
        // 3. Verify we are back at Unlock Screen
        let unlockButton = app.buttons["Unlock"]
        XCTAssertTrue(unlockButton.waitForExistence(timeout: 2.0), "Should return to unlock screen")
    }
    
    func testWrongPassword() throws {
        let app = XCUIApplication()
        setupPasswordAndUnlock(app: app)
        
        // 1. Lock first
        let menuButton = app.buttons["More"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 10.0), "Menu button should exist")
        
        // Force tap to avoid "Failed to scroll to visible" errors in toolbar
        menuButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        
        app.buttons["Lock Vault"].tap()
        
        // 2. Enter Wrong Password
        let unlockField = app.secureTextFields["Password"]
        XCTAssertTrue(unlockField.waitForExistence(timeout: 2.0))
        
        unlockField.tap()
        unlockField.typeText("WrongPass")
        
        // Dismiss keyboard to ensure Unlock button is visible
        // The title is "Secret Vault" or "Enter your password to unlock" based on the error log
        app.staticTexts["Secret Vault"].tap()
        
        app.buttons["Unlock"].tap()
        
        // 3. Verify Error Message
        let errorText = app.staticTexts["Invalid password"]
        XCTAssertTrue(errorText.waitForExistence(timeout: 1.0), "Error message should appear")
    }
    
    func testPrivacyModeToggle() throws {
        let app = XCUIApplication()
        setupPasswordAndUnlock(app: app)
        
        // 1. Find Toggle
        // Toggles often don't have simple labels if .labelsHidden() is used, 
        // but we can find it by type
        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.exists, "Privacy Mode toggle should exist")
        
        // 2. Toggle it
        toggle.tap()
        
        // 3. Verify State Change (Optional: check label text if it changes)
        // In MainVaultView: Label(privacyModeEnabled ? "Privacy Mode On" : "Privacy Mode Off", ...)
        // We can check for the static text
        
        // Note: Since we start with Privacy Mode ON (default), tapping it turns it OFF.
        // Wait a bit longer for the toggle animation and state update
        let offLabel = app.staticTexts["Privacy Mode Off"]
        XCTAssertTrue(offLabel.waitForExistence(timeout: 5.0), "Should switch to Privacy Mode Off")
    }

    func testPhotosPickerPresentsAfterToolbarTap() throws {
        let app = XCUIApplication()
        setupPasswordAndUnlock(app: app)

        openPhotosPicker(app: app)

        let pickerTitle = app.staticTexts["Select Items to Hide"]
        XCTAssertTrue(pickerTitle.waitForExistence(timeout: 5.0), "Picker title should be visible")
    }

    func testPhotosPickerCancelDismissesSheet() throws {
        let app = XCUIApplication()
        setupPasswordAndUnlock(app: app)

        openPhotosPicker(app: app)

        let cancelButton = app.buttons["photosPickerCancelButton"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5.0), "Cancel button should appear on picker")
        cancelButton.tap()

        XCTAssertFalse(cancelButton.waitForExistence(timeout: 2.0), "Picker should dismiss after tapping Cancel")
        XCTAssertFalse(app.staticTexts["Select Items to Hide"].exists, "Picker title should disappear")
    }
}
