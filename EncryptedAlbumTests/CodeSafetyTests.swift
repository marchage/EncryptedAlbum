import XCTest

final class CodeSafetyTests: XCTestCase {

    /// Scan app source files (non-test) and assert there are no raw prints or unguarded destructive helpers.
    func test_no_raw_prints_or_unconditional_nuke() throws {
        // Locate repo root by walking up from this file
        var url = URL(fileURLWithPath: #file)
        while !FileManager.default.fileExists(atPath: url.appendingPathComponent("EncryptedAlbum.xcodeproj").path)
            && url.pathComponents.count > 1
        {
            url.deleteLastPathComponent()
        }

        let repoRoot = url
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("EncryptedAlbum.xcodeproj").path),
            "Repo root not found")

        // Walk EncryptedAlbum/ and ShareExtension/ sources
        let targets = ["EncryptedAlbum", "ShareExtension"]
        var violations: [String] = []

        for target in targets {
            let dir = repoRoot.appendingPathComponent(target)
            guard FileManager.default.fileExists(atPath: dir.path) else { continue }

            let enumerator = FileManager.default.enumerator(atPath: dir.path)
            while let item = enumerator?.nextObject() as? String {
                guard item.hasSuffix(".swift") else { continue }
                // skip tests
                let fullPath = dir.appendingPathComponent(item).path
                if fullPath.contains("/Tests/") || fullPath.contains("EncryptedAlbumTests")
                    || fullPath.contains("UITests")
                {
                    continue
                }

                let content = try String(contentsOfFile: fullPath)
                var debugNesting = 0
                let lines = content.components(separatedBy: .newlines)
                for (index, line) in lines.enumerated() {
                    // Normalize
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.range(of: "#if") != nil && trimmed.range(of: "DEBUG") != nil {
                        debugNesting += 1
                    }
                    if trimmed.range(of: "#endif") != nil && debugNesting > 0 {
                        debugNesting -= 1
                    }

                    // Only flag prints if not inside DEBUG-only region
                    if debugNesting == 0 {
                        if trimmed.contains("print(") || trimmed.contains("debugPrint(") || trimmed.contains("NSLog(")
                            || trimmed.contains("printf(")
                        {
                            violations.append("\(fullPath):\(index+1): \(line.trimmingCharacters(in: .whitespaces))")
                        }
                        if trimmed.contains("nukeAllData(") {
                            // nukeAllData must be DEBUG-only; since debugNesting==0 here this is a violation
                            violations.append("\(fullPath):\(index+1): unconditional nukeAllData found")
                        }
                    }
                }
            }
        }

        if !violations.isEmpty {
            XCTFail("Found forbidden logging/destructive patterns:\n\(violations.joined(separator: "\n"))")
        }
    }
}
