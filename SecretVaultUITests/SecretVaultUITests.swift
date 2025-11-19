import XCTest

final class SecretVaultUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        
        let app = XCUIApplication()
        // This argument tells the app to wipe data on launch
        app.launchArguments = ["--reset-state"]
        app.launch()
    }

    func testUnlockFlow() throws {
        let app = XCUIApplication()
        
        // 1. Since we reset state, we expect the "Setup Password" screen
        let passwordField = app.secureTextFields["New Password"]
        let confirmField = app.secureTextFields["Confirm Password"]
        
        // Verify we are on setup screen
        XCTAssertTrue(passwordField.waitForExistence(timeout: 2.0), "Should be on Setup Password screen")
        
        // 2. Create a new password
        passwordField.tap()
        passwordField.typeText("TestPass123!")
        
        confirmField.tap()
        confirmField.typeText("TestPass123!")
        
        // 3. Tap Setup/Save button
        app.buttons["Set Password"].tap()
        
        // 4. Now we should be in the Vault (or asked to unlock)
        // Let's assume it logs us in or asks for unlock.
        // If it asks for unlock:
        if app.buttons["Unlock"].exists {
            let unlockField = app.secureTextFields["Password"]
            unlockField.tap()
            unlockField.typeText("TestPass123!")
            app.buttons["Unlock"].tap()
        }
        
        // 5. Verify we are inside the vault
        // Look for a key element like the "Add" button or navigation title
        let navBar = app.navigationBars["SecretVault"]
        XCTAssertTrue(navBar.waitForExistence(timeout: 2.0), "Should be inside the vault")
    }
}
