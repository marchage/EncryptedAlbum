import XCTest

final class SecretVaultMacUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launchArguments = ["--reset-state"]
        app.launch()
    }

    func testMenuContainsExpectedActions() throws {
        let app = XCUIApplication()
        setupPasswordAndUnlock(app: app)

        let menuButton = toolbarButton(
            app: app,
            identifier: "More",
            fallbackIdentifiers: ["More", "Lock Vault", "ellipsis", "ellipsis.circle"])
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5.0), "Menu button should exist")
        menuButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let removeDuplicatesButton = app.buttons["Remove Duplicates"]
        let removeDuplicatesMenuItem = app.menuItems["Remove Duplicates"]
        XCTAssertTrue(
            removeDuplicatesButton.waitForExistence(timeout: 2.0)
                || removeDuplicatesMenuItem.waitForExistence(timeout: 2.0),
            "Remove Duplicates action should appear")

        let lockVaultButton = app.buttons["Lock Vault"]
        let lockVaultMenuItem = app.menuItems["Lock Vault"]
        XCTAssertTrue(lockVaultButton.exists || lockVaultMenuItem.exists, "Lock Vault should remain accessible")

        dismissOverflowMenu(app: app)
    }

    func testToolbarButtonsAreVisible() throws {
        let app = XCUIApplication()
        setupPasswordAndUnlock(app: app)

        let addPhotos = toolbarButton(
            app: app,
            identifier: "addPhotosButton",
            fallbackIdentifiers: ["Add Photos", "plus", "Add"])
        let addPhotosExists = addPhotos.waitForExistence(timeout: 5.0)
            || app.buttons["Add Photos"].waitForExistence(timeout: 2.0)
            || app.toolbarButtons["Add Photos"].waitForExistence(timeout: 2.0)
        XCTAssertTrue(addPhotosExists, "Add Photos toolbar button should appear")

        let cameraButton = toolbarButton(
            app: app,
            identifier: "camera.fill",
            fallbackIdentifiers: ["Camera", "camera.fill", "Camera Capture"])
        let cameraExists = cameraButton.waitForExistence(timeout: 5.0)
            || app.buttons["Camera"].waitForExistence(timeout: 2.0)
            || app.toolbarButtons["Camera"].waitForExistence(timeout: 2.0)
        XCTAssertTrue(cameraExists, "Camera capture button should appear")
    }

    private func dismissOverflowMenu(app: XCUIApplication) {
        if app.menuBars.count > 0 {
            app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        } else if app.windows.firstMatch.exists {
            app.windows.firstMatch.tap()
        }
    }
}
