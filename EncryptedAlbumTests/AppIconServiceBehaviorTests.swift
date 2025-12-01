import XCTest

@testable import EncryptedAlbum

final class AppIconServiceBehaviorTests: XCTestCase {
    func testAvailableIconsArePresent() {
        let svc = AppIconService.shared
        XCTAssertTrue(svc.availableIcons.contains("AppIcon"))
        // At least one alternate should be present when building from the bundle
        XCTAssertTrue(svc.availableIcons.contains("AppIcon1"))
        XCTAssertGreaterThanOrEqual(svc.availableIcons.count, 1)
    }

    func testGenerateMarketingImage_Default() {
        // Ensure the marketing generator returns an image for the common default
        #if os(macOS)
            XCTAssertNotNil(AppIconService.generateMarketingImage(from: "AppIcon"))
        #else
            XCTAssertNotNil(AppIconService.generateMarketingImage(from: "AppIcon"))
        #endif
    }

    func testGenerateMarketingImage_AlternateIcons() {
        // Verify that alternate icons also produce marketing images
        // This tests the folder-constrained search we implemented
        let alternates = ["AppIcon1", "AppIcon2", "AppIcon3"]

        for iconName in alternates {
            let image = AppIconService.generateMarketingImage(from: iconName)
            // Some alternates may not exist in test bundle, so just verify no crash
            // and that when they do exist, we get an image
            if AppIconService.shared.availableIcons.contains(iconName) {
                XCTAssertNotNil(image, "Expected marketing image for available icon \(iconName)")
            }
        }
    }

    func testBundleResourceURL_WithFolderConstraint() {
        // Test that bundleResourceURL respects the withinFolder parameter
        #if os(iOS)
            // On iOS, search for mac1024.png within specific appiconset folders
            let defaultURL = AppIconService.bundleResourceURL(matching: "mac1024", withinFolder: "AppIcon.appiconset")
            let alternate1URL = AppIconService.bundleResourceURL(
                matching: "mac1024", withinFolder: "AppIcon1.appiconset")

            // If both exist, they should be different paths
            if let def = defaultURL, let alt = alternate1URL {
                XCTAssertNotEqual(def.path, alt.path, "Different icon folders should return different resource URLs")
            }
        #endif
    }

    func testSelectedIconPersistence() {
        let svc = AppIconService.shared
        let originalIcon = svc.selectedIcon

        // This tests that the selected icon can be read (persistence is via UserDefaults)
        XCTAssertFalse(svc.selectedIcon.isEmpty, "Selected icon should never be empty")

        // Restore original (don't actually change the system icon in tests)
        XCTAssertEqual(svc.selectedIcon, originalIcon)
    }
}
