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
                    completion(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Resource temporarily unavailable"]))
                } else {
                    completion(nil)
                }
            }
        }
    }

    func testTransientFailuresThenSuccess() {
        // Choose a known icon name (prefer an alternate if available)
        let svc = AppIconService(iconApplier: TestIconApplier(failures: 2), maxApplyAttempts: 4, initialApplyDelay: 0.01)

        let candidate = svc.availableIcons.first ?? "AppIcon"
        let expectation = XCTestExpectation(description: "Icon apply eventually succeeds after retries")

        // Observe lastIconApplyError and wait for it to be nil (success)
        svc.select(iconName: candidate)

        // Poll until success or timeout
        let deadline = Date().addingTimeInterval(2.0)
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
        wait(for: [expectation], timeout: 3.0)
    }

    func testPermanentFailurePublishesError() {
        let svc = AppIconService(iconApplier: TestIconApplier(failures: 100), maxApplyAttempts: 3, initialApplyDelay: 0.01)
        let candidate = svc.availableIcons.first ?? "AppIcon"

        let expectation = XCTestExpectation(description: "Icon apply fails permanently and publishes error")

        svc.select(iconName: candidate)

        // Poll until final error appears
        let deadline = Date().addingTimeInterval(2.0)
        func check() {
            if let err = svc.lastIconApplyError, !err.isEmpty {
                expectation.fulfill()
            } else if Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { check() }
            } else {
                XCTFail("Expected final error but got none")
                expectation.fulfill()
            }
        }

        check()
        wait(for: [expectation], timeout: 3.0)
    }
}
