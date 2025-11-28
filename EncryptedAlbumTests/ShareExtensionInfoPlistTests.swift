import XCTest

final class ShareExtensionInfoPlistTests: XCTestCase {
    func testShareExtensionInfoPlistHasActivationKeys() throws {
        // Paths relative to repo — tests are executed in CI where workspace root is available
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sharePlist = repoRoot.appendingPathComponent("ShareExtension/Info.plist")
        let shareMacPlist = repoRoot.appendingPathComponent("ShareExtensionMac/Info.plist")

        func check(plistURL: URL) throws {
            let data = try Data(contentsOf: plistURL)
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let dict = plist as? [String: Any],
                  let ext = dict["NSExtension"] as? [String: Any],
                  let attrs = ext["NSExtensionAttributes"] as? [String: Any]
            else {
                XCTFail("Malformed plist at \(plistURL.path)")
                return
            }

            let hasImageKey = attrs.keys.contains("NSExtensionActivationSupportsImageWithMaxCount")
            let hasMovieKey = attrs.keys.contains("NSExtensionActivationSupportsMovieWithMaxCount")

            XCTAssertTrue(hasImageKey || hasMovieKey, "Share extension Info.plist must contain activation keys for images or movies: \(plistURL.path)")
        }

        try check(plistURL: sharePlist)
        try check(plistURL: shareMacPlist)
    }
}
