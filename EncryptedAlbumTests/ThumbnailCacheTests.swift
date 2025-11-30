import XCTest
@testable import EncryptedAlbum

final class ThumbnailCacheTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ThumbnailCache.shared.clear()
    }

    override func tearDown() {
        ThumbnailCache.shared.clear()
        super.tearDown()
    }

    func testSetGetRemoveAndClear() {
        let id = UUID()
        let sample = "thumbnail-data".data(using: .utf8)!

        XCTAssertNil(ThumbnailCache.shared.get(id))

        ThumbnailCache.shared.set(sample, for: id)

        // Small delay for async set
        let expectation = XCTestExpectation(description: "wait for set")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        let fetched = ThumbnailCache.shared.get(id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched, sample)

        // Remove
        ThumbnailCache.shared.remove(id)
        // small delay
        let expect2 = XCTestExpectation(description: "wait for remove")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            expect2.fulfill()
        }
        wait(for: [expect2], timeout: 1.0)

        XCTAssertNil(ThumbnailCache.shared.get(id))

        // Re-add and clear full cache
        ThumbnailCache.shared.set(sample, for: id)
        let expect3 = XCTestExpectation(description: "wait for cache set 2")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            expect3.fulfill()
        }
        wait(for: [expect3], timeout: 1.0)

        XCTAssertNotNil(ThumbnailCache.shared.get(id))

        ThumbnailCache.shared.clear()
        let expect4 = XCTestExpectation(description: "wait for clear")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            expect4.fulfill()
        }
        wait(for: [expect4], timeout: 1.0)

        XCTAssertNil(ThumbnailCache.shared.get(id))
    }

}
