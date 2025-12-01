import XCTest

#if canImport(EncryptedAlbum)
    @testable import EncryptedAlbum
#else
    @testable import EncryptedAlbum_iOS
#endif

final class AppIconServiceRetryTests: XCTestCase {
    // Test applier that simulates N transient failures before success.
    class TestIconApplier: IconApplier {
        private var failuresRemaining: Int
        private let responseDelay: TimeInterval

        init(failures: Int, responseDelay: TimeInterval = 0.01) {
            self.failuresRemaining = failures
            self.responseDelay = responseDelay
        }

        func apply(iconName: String?, completion: @escaping (Error?) -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + responseDelay) { [weak self] in
                guard let self = self else { return }
                if self.failuresRemaining > 0 {
                    self.failuresRemaining -= 1
                    completion(
                        NSError(
                            domain: "test", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Resource temporarily unavailable"]))
                } else {
                    completion(nil)
                }
            }
        }
    }

    func testApplyFailsWhenApplierReportsError() {
        // If the applier returns an error we expect the service to publish the error
        // immediately (no retry/backoff behavior).
        let svc = AppIconService(iconApplier: TestIconApplier(failures: 2))

        let candidate = svc.availableIcons.first ?? "AppIcon"
        let expectation = XCTestExpectation(description: "Icon apply fails and publishes an error")

        svc.select(iconName: candidate)

        // Poll until we see an error or timeout
        let deadline = Date().addingTimeInterval(1.0)
        func check() {
            if let err = svc.lastIconApplyError, !err.isEmpty {
                expectation.fulfill()
            } else if Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { check() }
            } else {
                XCTFail("Expected error but got none")
                expectation.fulfill()
            }
        }

        check()
        wait(for: [expectation], timeout: 2.0)
    }

    func testApplySucceedsWhenApplierReturnsSuccess() {
        let svc = AppIconService(iconApplier: TestIconApplier(failures: 0))
        let candidate = svc.availableIcons.first ?? "AppIcon"
        let expectation = XCTestExpectation(description: "Icon apply succeeds and publishes no error")

        svc.select(iconName: candidate)

        // Poll until success (lastIconApplyError == nil)
        let deadline = Date().addingTimeInterval(1.0)
        func check() {
            if svc.lastIconApplyError == nil {
                expectation.fulfill()
            } else if Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { check() }
            } else {
                XCTFail("Icon apply did not succeed in time: \(String(describing: svc.lastIconApplyError))")
                expectation.fulfill()
            }
        }

        check()
        wait(for: [expectation], timeout: 2.0)
    }

    // The permanent-failure case is covered by testApplyFailsWhenApplierReportsError
}
