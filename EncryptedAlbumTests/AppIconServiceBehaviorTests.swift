import XCTest
@testable import EncryptedAlbum

final class AppIconServiceBehaviorTests: XCTestCase {
    func testAvailableIconsArePresent() {
        let svc = AppIconService.shared
        XCTAssertTrue(svc.availableIcons.contains("AppIcon"))
        XCTAssertTrue(svc.availableIcons.contains("AppIcon 1"))
        XCTAssertEqual(svc.availableIcons.count, 11)
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
