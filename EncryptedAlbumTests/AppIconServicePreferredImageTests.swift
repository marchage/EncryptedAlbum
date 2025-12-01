import XCTest

@testable import EncryptedAlbum

final class AppIconServicePreferredImageTests: XCTestCase {
    // Helper: create a UIImage (iOS) or NSImage (macOS) with a given point width
    func makeImage(width: CGFloat) -> PlatformImage {
        #if os(macOS)
            return NSImage(size: NSSize(width: width, height: width))
        #else
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: width))
            return renderer.image { ctx in
                UIColor.clear.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: width, height: width))
            }
        #endif
    }

    func test_choosePrefersGeneratedWhenRuntimeIsSmaller() {
        let runtime = makeImage(width: 50)
        let generated = makeImage(width: 1024)
        let chosen = AppIconService.chooseBestMarketingImage(runtime: runtime, generated: generated, visualCap: 256)
        XCTAssertNotNil(chosen)
        XCTAssertEqual(chosen?.size.width, generated.size.width)
    }

    func test_choosePrefersRuntimeWhenRuntimeIsLargeEnough() {
        let runtime = makeImage(width: 300)
        let generated = makeImage(width: 1024)
        let chosen = AppIconService.chooseBestMarketingImage(runtime: runtime, generated: generated, visualCap: 256)
        XCTAssertNotNil(chosen)
        XCTAssertEqual(chosen?.size.width, runtime.size.width)
    }

    func test_chooseFallsBackToGeneratedWhenRuntimeNil() {
        let generated = makeImage(width: 1024)
        let chosen = AppIconService.chooseBestMarketingImage(runtime: nil, generated: generated, visualCap: 256)
        XCTAssertNotNil(chosen)
        XCTAssertEqual(chosen?.size.width, generated.size.width)
    }

    func test_chooseKeepsRuntimeWhenGeneratedSmaller() {
        let runtime = makeImage(width: 200)
        let generated = makeImage(width: 128)
        let chosen = AppIconService.chooseBestMarketingImage(runtime: runtime, generated: generated, visualCap: 256)
        XCTAssertNotNil(chosen)
        XCTAssertEqual(chosen?.size.width, runtime.size.width)
    }
}
