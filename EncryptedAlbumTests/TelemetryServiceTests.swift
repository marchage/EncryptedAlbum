import XCTest

#if canImport(EncryptedAlbum)
    @testable import EncryptedAlbum
#elseif canImport(EncryptedAlbum_iOS)
    @testable import EncryptedAlbum_iOS
#endif

final class TelemetryServiceTests: XCTestCase {
    func testTelemetryDefaultsDisabled() {
        let svc = TelemetryService.shared
        svc.setEnabled(false)
        XCTAssertFalse(svc.isEnabled)
    }

    func testEnableDisableLifecycle() {
        let svc = TelemetryService.shared
        svc.setEnabled(false)
        XCTAssertFalse(svc.isEnabled)
        svc.setEnabled(true)
        XCTAssertTrue(svc.isEnabled)
        svc.setEnabled(false)
        XCTAssertFalse(svc.isEnabled)
    }
}
