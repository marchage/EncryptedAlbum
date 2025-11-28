import Foundation
import XCTest

final class EncryptedAlbumUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false

        let app = XCUIApplication()
        // This argument tells the app to wipe data on launch
        app.launchArguments = ["--reset-state"]
        print("Launching app with arguments: \(app.launchArguments)")
        app.launch()
    }

    // MARK: - Tests

    func testUnlockFlow() throws {
        let app = XCUIApplication()
        setupPasswordAndUnlock(app: app)

        // Verify we are inside the album
        let navBar = app.navigationBars["Encrypted Items"]
        XCTAssertTrue(navBar.waitForExistence(timeout: 2.0), "Should be inside the album")
    }

    func testLockAlbum() throws {
        let app = XCUIApplication()
        setupPasswordAndUnlock(app: app)

        // 1. Open Menu
        // The button has an image "ellipsis.circle" but SwiftUI might expose it as "More"
        // or simply by its image name if no label is provided.
        // Based on the error, it is exposed as "More".
        let menuButton = toolbarButton(
            app: app, identifier: "More", fallbackIdentifiers: ["More", "Lock Album", "ellipsis"])

        XCTAssertTrue(menuButton.waitForExistence(timeout: 10.0), "Menu button should exist")

        // Force tap to avoid "Failed to scroll to visible" errors in toolbar
        menuButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // 2. Tap Lock
        let lockButton = app.buttons["Lock Album"]
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
        let menuButton = toolbarButton(
            app: app, identifier: "More", fallbackIdentifiers: ["More", "Lock Album", "ellipsis"])
        XCTAssertTrue(menuButton.waitForExistence(timeout: 10.0), "Menu button should exist")

        // Force tap to avoid "Failed to scroll to visible" errors in toolbar
        menuButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        app.buttons["Lock Album"].tap()

        // 2. Enter Wrong Password
        let unlockField = app.secureTextFields["Password"]
        XCTAssertTrue(unlockField.waitForExistence(timeout: 2.0))

        unlockField.tap()
        unlockField.typeText("WrongPass")

        // Dismiss keyboard to ensure Unlock button is visible
        // The title is "Encrypted Album" or "Enter your password to unlock" based on the error log
        app.staticTexts["Encrypted Album"].tap()

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
        // In MainAlbumView: Label(privacyModeEnabled ? "Privacy Mode On" : "Privacy Mode Off", ...)
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

    func testMenuContainsExpectedActions() throws {
        let app = XCUIApplication()
        setupPasswordAndUnlock(app: app)

        let menuButton = toolbarButton(
            app: app, identifier: "More", fallbackIdentifiers: ["More", "Lock Album", "ellipsis"])
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5.0), "Menu button should exist")
        menuButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(app.buttons["Remove Duplicates"].waitForExistence(timeout: 2.0), "Remove Duplicates action should appear")
        XCTAssertTrue(app.buttons["Lock Album"].exists, "Lock Album should remain accessible")

        app.tap()
    }

    func testToolbarButtonsAreVisible() throws {
        let app = XCUIApplication()
        setupPasswordAndUnlock(app: app)

        let addPhotos = toolbarButton(app: app, identifier: "addPhotosButton")
        XCTAssertTrue(addPhotos.waitForExistence(timeout: 5.0), "Add Photos toolbar button should appear")

        let cameraButton = toolbarButton(app: app, identifier: "camera.fill", fallbackIdentifiers: ["camera.fill"])
        XCTAssertTrue(cameraButton.waitForExistence(timeout: 5.0), "Camera capture button should appear")
    }

    func testPreferencesEnableLockdownShowsToolbarIndicator() throws {
        let app = XCUIApplication()
        setupPasswordAndUnlock(app: app)

        // Open menu and tap Settings
        let menuButton = toolbarButton(app: app, identifier: "More", fallbackIdentifiers: ["More", "Lock Album", "ellipsis"])
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5.0))
        menuButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 2.0))
        settingsButton.tap()

        // Ensure the Toggle is present and enable it (confirmation dialog)
        let lockdownSwitch = app.switches["lockdownToggle"]
        XCTAssertTrue(lockdownSwitch.waitForExistence(timeout: 5.0))

        // Tap the switch and confirm enabling via alert
        lockdownSwitch.tap()
        let enableButton = app.buttons["Enable"]
        XCTAssertTrue(enableButton.waitForExistence(timeout: 2.0))
        enableButton.tap()

        // Close preferences
        let closeButton = app.buttons["Close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 2.0))
        closeButton.tap()

        // Verify the toolbar indicates lockdown is active
        let lockdownLabel = app.staticTexts["Lockdown"]
        XCTAssertTrue(lockdownLabel.waitForExistence(timeout: 3.0), "Toolbar should show Lockdown indicator after enabling in Preferences")
    }

    func testUnlockButtonsAreInsetFromEdges() throws {
        let app = XCUIApplication()
        setupPasswordAndUnlock(app: app)

        // Lock the album to return to the unlock screen
        let menuButton = toolbarButton(app: app, identifier: "More", fallbackIdentifiers: ["More", "Lock Album", "ellipsis"])
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5.0), "Menu button should exist")
        menuButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let lockButton = app.buttons["Lock Album"]
        XCTAssertTrue(lockButton.waitForExistence(timeout: 2.0), "Lock button should appear in menu")
        lockButton.tap()

        // Now the unlock screen should be visible
        let unlockButton = app.buttons["unlock.unlockButton"]
        XCTAssertTrue(unlockButton.waitForExistence(timeout: 2.0), "Unlock button should be present on lock screen")

        // The unlock button should not be flush to the screen edges
        let screenWidth = app.frame.width
        XCTAssertTrue(unlockButton.frame.minX >= 12, "Unlock button should be inset from left edge")
        XCTAssertTrue(unlockButton.frame.maxX <= screenWidth - 12, "Unlock button should be inset from right edge")

        // If biometric button is present, it should also be inset
        let bioButton = app.buttons["unlock.biometricButton"]
        if bioButton.exists {
            XCTAssertTrue(bioButton.frame.minX >= 12, "Biometric button should be inset from left edge")
            XCTAssertTrue(bioButton.frame.maxX <= screenWidth - 12, "Biometric button should be inset from right edge")
        }
    }
}
