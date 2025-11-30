import XCTest
@testable import EncryptedAlbum

final class AppIconServiceBehaviorTests: XCTestCase {
    func testAvailableIconsArePresent() {
        let svc = AppIconService.shared
        XCTAssertTrue(svc.availableIcons.contains("AppIcon"))
        // At least one alternate should be present when building from the bundle
        XCTAssertTrue(svc.availableIcons.contains("AppIcon 1"))
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
}
