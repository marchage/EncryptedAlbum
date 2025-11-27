import XCTest
#if canImport(EncryptedAlbum)
@testable import EncryptedAlbum
#else
@testable import EncryptedAlbum_iOS
#endif

final class SecureDeleteTests: XCTestCase {
    func testMaxSecureDeleteSize_100MB() {
        XCTAssertEqual(CryptoConstants.maxSecureDeleteSize, 100 * 1024 * 1024)
    }
}
