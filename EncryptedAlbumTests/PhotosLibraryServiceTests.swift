
import XCTest
import Photos
#if canImport(EncryptedAlbum)
@testable import EncryptedAlbum
#else
@testable import EncryptedAlbum_iOS
#endif

final class PhotosLibraryServiceTests: XCTestCase {
    
    var sut: PhotosLibraryService!
    
    override func setUp() {
        super.setUp()
        sut = PhotosLibraryService.shared
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    func testService_IsSingleton() {
        let instance1 = PhotosLibraryService.shared
        let instance2 = PhotosLibraryService.shared
        XCTAssertTrue(instance1 === instance2)
    }
    
    func testRequestAccess_ShouldReturnBool() {
        // This test is asynchronous and depends on system state.
        // We just verify it calls the completion handler.
        let expectation = expectation(description: "Access request completion")
        
        sut.requestAccess { granted in
            // We don't assert granted because it depends on the simulator/device state
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // Note: Most other methods in PhotosLibraryService require a populated Photos library
    // and user permissions, which are difficult to guarantee in a unit test environment.
    // We skip them to avoid flaky tests.
}
