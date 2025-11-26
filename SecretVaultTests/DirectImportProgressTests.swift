import XCTest
#if canImport(SecretVault)
@testable import SecretVault
#else
@testable import SecretVault_iOS
#endif

@MainActor
final class DirectImportProgressTests: XCTestCase {
    func testResetInitializesState() {
        let progress = DirectImportProgress()
        progress.reset(totalItems: 4)

        XCTAssertTrue(progress.isImporting)
        XCTAssertEqual(progress.statusMessage, "Preparing import…")
        XCTAssertEqual(progress.detailMessage, "4 item(s)")
        XCTAssertEqual(progress.itemsProcessed, 0)
        XCTAssertEqual(progress.itemsTotal, 4)
        XCTAssertEqual(progress.bytesProcessed, 0)
        XCTAssertEqual(progress.bytesTotal, 0)
        XCTAssertFalse(progress.cancelRequested)
    }

    func testFinishClearsState() {
        let progress = DirectImportProgress()
        progress.reset(totalItems: 3)
        progress.itemsProcessed = 2
        progress.itemsTotal = 3
        progress.bytesTotal = 512 * 1024
        progress.forceUpdateBytesProcessed(128 * 1024)
        progress.cancelRequested = true

        progress.finish()

        XCTAssertFalse(progress.isImporting)
        XCTAssertTrue(progress.statusMessage.isEmpty)
        XCTAssertTrue(progress.detailMessage.isEmpty)
        XCTAssertEqual(progress.itemsProcessed, 0)
        XCTAssertEqual(progress.itemsTotal, 0)
        XCTAssertEqual(progress.bytesProcessed, 0)
        XCTAssertEqual(progress.bytesTotal, 0)
        XCTAssertFalse(progress.cancelRequested)
    }

    func testThrottledUpdateBytesProcessedHonorsThresholds() async throws {
        let progress = DirectImportProgress()
        progress.bytesTotal = 10 * 1024 * 1024

        progress.throttledUpdateBytesProcessed(0)
        progress.throttledUpdateBytesProcessed(64 * 1024)
        XCTAssertEqual(progress.bytesProcessed, 0)

        try await Task.sleep(nanoseconds: 60_000_000)
        progress.throttledUpdateBytesProcessed(5 * 1024 * 1024)
        XCTAssertEqual(progress.bytesProcessed, 5 * 1024 * 1024)
    }

    func testForceUpdateBytesProcessedBypassesThrottle() {
        let progress = DirectImportProgress()
        progress.bytesTotal = 2 * 1024 * 1024
        progress.throttledUpdateBytesProcessed(0)

        progress.forceUpdateBytesProcessed(512 * 1024)

        XCTAssertEqual(progress.bytesProcessed, 512 * 1024)
    }
}
