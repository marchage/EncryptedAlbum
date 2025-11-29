import XCTest
@testable import EncryptedAlbum

final class ImportSaverTests: XCTestCase {

    func testSaveFileToContainer_success() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        // create a small temp file
        let src = tmp.appendingPathComponent("test-image.jpg")
        try Data("hello".utf8).write(to: src)

        let container = tmp.appendingPathComponent("container")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)

        let ok = ImportSaver.saveFile(toContainerURL: container, from: src)
        XCTAssertTrue(ok, "Saving a file into the container should succeed")

        let inbox = container.appendingPathComponent("ImportInbox")
        let files = try FileManager.default.contentsOfDirectory(atPath: inbox.path)
        XCTAssertFalse(files.isEmpty)
    }

    func testSaveDataToContainer_success() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let container = tmp.appendingPathComponent("container")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)

        let data = "my-data".data(using: .utf8)!
        let ok = ImportSaver.saveData(toContainerURL: container, data, suggestedFilename: "some.jpg")
        XCTAssertTrue(ok)

        let inbox = container.appendingPathComponent("ImportInbox")
        let files = try FileManager.default.contentsOfDirectory(atPath: inbox.path)
        XCTAssertFalse(files.isEmpty)
    }

    func testSaveFileToContainer_failsWhenContainerIsAFile() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let notADir = tmp.appendingPathComponent("notadir")
        try Data("hello".utf8).write(to: notADir)

        // create a source file
        let src = tmp.appendingPathComponent("file.jpg")
        try Data("abc".utf8).write(to: src)

        // Passing a file URL as the container should fail
        let ok = ImportSaver.saveFile(toContainerURL: notADir, from: src)
        XCTAssertFalse(ok)
    }

    func testCopyFileWithProgress_reportsProgressAndCompletes() throws {
        let fm = FileManager.default
        let container = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: container, withIntermediateDirectories: true)

        // create a source file ~200KB
        let src = container.appendingPathComponent("big.bin")
        let size = 200 * 1024
        var bytes = Data(count: size)
        _ = bytes.withUnsafeMutableBytes { ptr in
            arc4random_buf(ptr.baseAddress, size)
        }
        try bytes.write(to: src)

        let expectProgress = expectation(description: "progress called")
        let expectCompletion = expectation(description: "completed")

        ImportSaver.copyFileWithProgress(toContainerURL: container, from: src, chunkSize: 16 * 1024, progress: { written, total in
            // progress should be increasing up to total
            XCTAssertTrue(written <= total)
            expectProgress.fulfill()
        }, completion: { success in
            XCTAssertTrue(success)
            expectCompletion.fulfill()
        })

        wait(for: [expectProgress, expectCompletion], timeout: 5.0)
    }

    func testWriteDataWithProgress_reportsProgressAndCompletes() throws {
        let fm = FileManager.default
        let container = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: container, withIntermediateDirectories: true)

        let size = 200 * 1024
        var data = Data(count: size)
        _ = data.withUnsafeMutableBytes { ptr in
            arc4random_buf(ptr.baseAddress, size)
        }

        let expectProgress = expectation(description: "progress called")
        let expectCompletion = expectation(description: "completed")

        ImportSaver.writeDataWithProgress(toContainerURL: container, data, chunkSize: 16 * 1024, progress: { written, total in
            XCTAssertTrue(written <= total)
            expectProgress.fulfill()
        }, completion: { success in
            XCTAssertTrue(success)
            expectCompletion.fulfill()
        })

        wait(for: [expectProgress, expectCompletion], timeout: 5.0)
    }
}
