import XCTest
@testable import EncryptedAlbum

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
