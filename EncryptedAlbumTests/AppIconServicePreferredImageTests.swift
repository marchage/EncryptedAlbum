import XCTest

@testable import EncryptedAlbum

final class AppIconServicePreferredImageTests: XCTestCase {
    // Helper: create a UIImage (iOS) or NSImage (macOS) with a given point width
    // Note: On iOS, UIGraphicsImageRenderer creates images at scale 1.0 by default
    // so the pixel count equals point count
    func makeImage(width: CGFloat) -> PlatformImage {
        #if os(macOS)
            return NSImage(size: NSSize(width: width, height: width))
        #else
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0  // Ensure pixel width = point width for testing
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: width), format: format)
            return renderer.image { ctx in
                UIColor.clear.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: width, height: width))
            }
        #endif
    }

    func test_choosePrefersGeneratedWhenItHasMorePixels() {
        // Generated has 1024px, runtime has 50px - should prefer generated
        let runtime = makeImage(width: 50)
        let generated = makeImage(width: 1024)
        let chosen = Image.chooseBestMarketingImage(runtime: runtime, generated: generated, visualCap: 256)
        XCTAssertNotNil(chosen)
        XCTAssertEqual(chosen?.size.width, generated.size.width, "Should prefer generated when it has more pixels")
    }

    func test_choosePrefersGeneratedEvenWhenRuntimeSeemsBigEnough() {
        // NEW BEHAVIOR: Always prefer higher pixel count
        // Generated has 1024px, runtime has 300px - should prefer generated (more pixels)
        let runtime = makeImage(width: 300)
        let generated = makeImage(width: 1024)
        let chosen = Image.chooseBestMarketingImage(runtime: runtime, generated: generated, visualCap: 256)
        XCTAssertNotNil(chosen)
        XCTAssertEqual(chosen?.size.width, generated.size.width, "Should prefer generated when it has more pixels")
    }

    func test_chooseFallsBackToGeneratedWhenRuntimeNil() {
        let generated = makeImage(width: 1024)
        let chosen = Image.chooseBestMarketingImage(runtime: nil, generated: generated, visualCap: 256)
        XCTAssertNotNil(chosen)
        XCTAssertEqual(chosen?.size.width, generated.size.width)
    }

    func test_chooseKeepsRuntimeWhenGeneratedHasFewerPixels() {
        // Runtime has 200px, generated has 128px - should prefer runtime (more pixels)
        let runtime = makeImage(width: 200)
        let generated = makeImage(width: 128)
        let chosen = Image.chooseBestMarketingImage(runtime: runtime, generated: generated, visualCap: 256)
        XCTAssertNotNil(chosen)
        XCTAssertEqual(chosen?.size.width, runtime.size.width, "Should prefer runtime when it has more pixels")
    }

    func test_choosePrefersRuntimeWhenBothHaveSamePixels() {
        // Both have same pixel count - should prefer runtime
        let runtime = makeImage(width: 512)
        let generated = makeImage(width: 512)
        let chosen = Image.chooseBestMarketingImage(runtime: runtime, generated: generated, visualCap: 256)
        XCTAssertNotNil(chosen)
        XCTAssertEqual(chosen?.size.width, runtime.size.width, "Should prefer runtime when pixel counts are equal")
    }
}
