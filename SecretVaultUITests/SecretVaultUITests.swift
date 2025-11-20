import XCTest

final class SecretVaultUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        
        let app = XCUIApplication()
        // This argument tells the app to wipe data on launch
        app.launchArguments = ["--reset-state"]
        app.launch()
    }

    // MARK: - Helpers
    
    func setupPasswordAndUnlock(app: XCUIApplication) {
        // 1. Verify we are on setup screen
        let passwordField = app.secureTextFields["Enter password"]
        let confirmField = app.secureTextFields["Re-enter password"]
        
        if !passwordField.waitForExistence(timeout: 75.0) {
            print("DEBUG: Hierarchy at failure:\n\(app.debugDescription)")
            XCTFail("Should be on Setup Password screen (Password field not found)")
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
        menuButton.tap()
        
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
        menuButton.tap()
        
        app.buttons["Lock Vault"].tap()
        
        // 2. Enter Wrong Password
        let unlockField = app.secureTextFields["Password"]
        XCTAssertTrue(unlockField.waitForExistence(timeout: 2.0))
        
        unlockField.tap()
        unlockField.typeText("WrongPass")
        
        app.buttons["Unlock"].tap()
        
        // 3. Verify Error Message
        let errorText = app.staticTexts["Incorrect password"]
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
        let offLabel = app.staticTexts["Privacy Mode Off"]
        XCTAssertTrue(offLabel.waitForExistence(timeout: 1.0), "Should switch to Privacy Mode Off")
    }
}
