import XCTest

@testable import EncryptedAlbum

final class AppIconServiceTests: XCTestCase {
    func testGenerateMarketingImageForAvailableIcons() {
        // Check that we can produce a runtime marketing image for the default app icon
        #if os(macOS)
            XCTAssertNotNil(AppIconService.generateMarketingImage(from: "AppIcon"))
            // Sanity check the runtime marketing image (should map to the 512@2x rounded asset)
            XCTAssertNotNil(AppIconService.generateMarketingImage(from: "AppIconMarketingRuntime"))
        #else
            // On iOS, ensure the generator returns a UIImage for the default set
            XCTAssertNotNil(AppIconService.generateMarketingImage(from: "AppIcon"))
        #endif
    }
}
