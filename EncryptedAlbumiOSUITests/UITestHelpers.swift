import Foundation
import XCTest

extension XCTestCase {
    func setupPasswordAndUnlock(app: XCUIApplication) {
        let biometricToggle = app.switches["biometricToggle"]
        if biometricToggle.waitForExistence(timeout: 1.5),
            (biometricToggle.value as? String) == "1"
        {
            biometricToggle.tap()
        } else {
            let labeledToggle = app.switches["Use Auto-Generated Password"]
            if labeledToggle.exists,
                (labeledToggle.value as? String) == "1"
            {
                labeledToggle.tap()
            }
        }

        guard let passwordField = locateSecureField(
            app: app,
            preferredIdentifiers: ["Enter password", "Password"],
            fallbackIndex: 0,
            timeout: 10.0)
        else {
            print("DEBUG: Hierarchy at failure:\n\(app.debugDescription)")
            XCTFail("Should be on Setup Password screen (Password field not found). App might not have reset correctly.")
            return
        }

        guard focus(element: passwordField, app: app) else {
            XCTFail("Failed to focus password field for setup.")
            return
        }
        app.typeText("TestPass123!")

        guard let confirmField = locateSecureField(
            app: app,
            preferredIdentifiers: ["Re-enter password", "Confirm Password"],
            fallbackIndex: 1,
            timeout: 2.0,
            excluding: passwordField)
        else {
            print("DEBUG: Hierarchy at failure (confirm field missing):\n\(app.debugDescription)")
            XCTFail("Should be able to confirm password during setup.")
            return
        }

        guard focus(element: confirmField, app: app) else {
            XCTFail("Failed to focus confirm password field for setup.")
            return
        }
        app.typeText("TestPass123!")

        app.staticTexts["Welcome to Encrypted Album"].tap()

        app.buttons["Create Album"].tap()

        if app.buttons["Unlock"].waitForExistence(timeout: 1.0) {
            let unlockField = app.secureTextFields["Password"]
            unlockField.tap()
            unlockField.typeText("TestPass123!")
            app.buttons["Unlock"].tap()
        }
    }

    func openPhotosPicker(app: XCUIApplication) {
        let addPhotosButton = toolbarButton(app: app, identifier: "addPhotosButton")
        XCTAssertTrue(addPhotosButton.waitForExistence(timeout: 5.0), "Add Photos toolbar button should exist")
        addPhotosButton.tap()

        for _ in 0..<2 {
            if !handlePhotosPermissionIfNeeded(app: app) {
                break
            }
        }
    }

    @discardableResult
    func handlePhotosPermissionIfNeeded(app: XCUIApplication) -> Bool {
        var handledAlert = false
        let monitor = addUIInterruptionMonitor(withDescription: "Photos Permission") { alert -> Bool in
            let affirmativeButtons = [
                "Allow Full Access",
                "Allow Access to All Photos",
                "Allow",
                "OK",
                "Continue",
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

    func toolbarButton(app: XCUIApplication, identifier: String, fallbackIdentifiers: [String] = []) -> XCUIElement {
        let candidates = [identifier] + fallbackIdentifiers
        for candidate in candidates {
            let directByIdentifier = app.buttons.matching(identifier: candidate).firstMatch
            if directByIdentifier.exists { return directByIdentifier }

            let directByLabel = app.buttons.matching(NSPredicate(format: "label == %@", candidate)).firstMatch
            if directByLabel.exists { return directByLabel }

            let toolbarByIdentifier = app.toolbars.buttons.matching(identifier: candidate).firstMatch
            if toolbarByIdentifier.exists { return toolbarByIdentifier }

            let toolbarByLabel = app.toolbars.buttons.matching(NSPredicate(format: "label == %@", candidate)).firstMatch
            if toolbarByLabel.exists { return toolbarByLabel }
        }

        return app.buttons.matching(identifier: identifier).firstMatch
    }
}

private extension XCTestCase {
    /// Attempts to find a secure text field using common accessibility identifiers, falling back to index lookup.
    func locateSecureField(
        app: XCUIApplication,
        preferredIdentifiers: [String],
        fallbackIndex: Int,
        timeout: TimeInterval,
        excluding: XCUIElement? = nil
    ) -> XCUIElement? {
        let query = app.secureTextFields

        for identifier in preferredIdentifiers {
            let candidate = query[identifier]
            if candidate.waitForExistence(timeout: timeout), candidate != excluding {
                return candidate
            }
        }

        let fallback = query.element(boundBy: fallbackIndex)
        if fallback.waitForExistence(timeout: timeout), fallback != excluding {
            return fallback
        }

        // If the preferred index does not exist, fall back to the first available field.
        if let first = query.allElementsBoundByIndex.first(where: { $0 != excluding }) {
            if first.waitForExistence(timeout: timeout) {
                return first
            }
        }

        return nil
    }

    /// Attempts to bring keyboard focus to the specified element by tapping directly or via coordinate fallback.
    func focus(element: XCUIElement, app: XCUIApplication, maxAttempts: Int = 4, timeout: TimeInterval = 2.0) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }

        for attempt in 0..<maxAttempts {
            if app.keyboards.count > 0 { return true }

            if element.exists {
                if element.isHittable {
                    element.tap()
                } else {
                    let coordinate = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    coordinate.tap()
                }
            }

            // Give UIKit a brief moment to update focus after the interaction.
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))

            if app.keyboards.count > 0 { return true }

            // As a last resort, try a longer press on the final attempt to wake the hardware keyboard focus.
            if attempt == maxAttempts - 1, element.exists {
                let coordinate = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                coordinate.press(forDuration: 0.2)
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                if app.keyboards.count > 0 { return true }
            }
        }

        // Keyboard might be hidden because the simulator is connected to a hardware keyboard, but the element still got focus.
        print("DEBUG: Unable to confirm keyboard presence after focusing \(element). Continuing anyway.")
        return element.exists
    }
}
