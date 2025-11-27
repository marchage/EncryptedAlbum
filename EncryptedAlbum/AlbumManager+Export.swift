import Foundation
import SwiftUI

extension AlbumManager {
    struct ExportResult {
        let successCount: Int
        let failureCount: Int
        let wasCancelled: Bool
        let error: Error?
    }

    func startExport(photos: [SecurePhoto], to folderURL: URL, completion: @escaping (ExportResult) -> Void) {
        exportTask?.cancel()
        exportTask = Task(priority: .userInitiated) {
            let result = await runExportOperation(photos: photos, to: folderURL)
            await MainActor.run {
                completion(result)
                self.exportTask = nil
            }
        }
    }

    func cancelExport() {
        Task { @MainActor in
            guard exportProgress.isExporting, !exportProgress.cancelRequested else { return }
            exportProgress.cancelRequested = true
            exportProgress.statusMessage = "Canceling export…"
            exportProgress.detailMessage = "Finishing current file"
        }
        exportTask?.cancel()
    }

    private func runExportOperation(photos: [SecurePhoto], to folderURL: URL) async -> ExportResult {
        guard !photos.isEmpty else {
            return ExportResult(successCount: 0, failureCount: 0, wasCancelled: false, error: nil)
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file

        await MainActor.run {
            exportProgress.reset(totalItems: photos.count)
        }

        var successCount = 0
        var failureCount = 0
        var firstError: Error?
        var wasCancelled = false
        let fileManager = FileManager.default

        for (index, photo) in photos.enumerated() {
            if Task.isCancelled {
                wasCancelled = true
                break
            }
            
            let cancelRequested = await MainActor.run { exportProgress.cancelRequested }
            if cancelRequested {
                wasCancelled = true
                break
            }

            let expectedSize = photo.fileSize
            let expectedSizeText = expectedSize > 0 ? formatter.string(fromByteCount: expectedSize) : nil
            
            await MainActor.run {
                exportProgress.statusMessage = "Decrypting \(photo.filename)…"
                exportProgress.detailMessage = detailText(for: index + 1, total: photos.count, sizeDescription: expectedSizeText)
                exportProgress.itemsProcessed = index
                exportProgress.bytesProcessed = 0
                exportProgress.bytesTotal = expectedSize
            }

            var destinationURL: URL?

            do {
                let tempURL = try await decryptPhotoToTemporaryURL(photo)
                defer { try? fileManager.removeItem(at: tempURL) }

                destinationURL = folderURL.appendingPathComponent(photo.filename)

                if fileManager.fileExists(atPath: destinationURL!.path) {
                    try fileManager.removeItem(at: destinationURL!)
                }

                let fileSizeValue = fileSizeValue(for: tempURL)
                let sizeText = fileSizeValue > 0 ? formatter.string(fromByteCount: fileSizeValue) : nil
                let detail = detailText(for: index + 1, total: photos.count, sizeDescription: sizeText)

                await MainActor.run {
                    exportProgress.statusMessage = "Exporting \(photo.filename)…"
                    exportProgress.detailMessage = detail
                    exportProgress.itemsProcessed = index
                    exportProgress.bytesTotal = fileSizeValue
                    exportProgress.bytesProcessed = 0
                }

                try Task.checkCancellation()
                try await copyFileWithProgress(from: tempURL, to: destinationURL!, fileSize: fileSizeValue)
                successCount += 1
            } catch is CancellationError {
                wasCancelled = true
                if let destinationURL = destinationURL {
                    try? fileManager.removeItem(at: destinationURL)
                }
                break
            } catch {
                if let destinationURL = destinationURL {
                    try? fileManager.removeItem(at: destinationURL)
                }
                failureCount += 1
                if firstError == nil {
                    firstError = error
                }
                await MainActor.run {
                    exportProgress.statusMessage = "Failed \(photo.filename)"
                    exportProgress.detailMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                exportProgress.itemsProcessed = index + 1
                exportProgress.bytesProcessed = exportProgress.bytesTotal
            }
        }

        if Task.isCancelled {
            wasCancelled = true
        }

        await MainActor.run {
            exportProgress.finish()
        }
        
        return ExportResult(
            successCount: successCount,
            failureCount: failureCount,
            wasCancelled: wasCancelled,
            error: firstError
        )
    }
    
    private func detailText(for index: Int, total: Int, sizeDescription: String?) -> String {
        var parts: [String] = ["Item \(index) of \(total)"]
        if let sizeDescription = sizeDescription {
            parts.append(sizeDescription)
        }
        return parts.joined(separator: " • ")
    }
    
    private func fileSizeValue(for url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? NSNumber
        else {
            return 0
        }
        return size.int64Value
    }

    private func copyFileWithProgress(from sourceURL: URL, to destinationURL: URL, fileSize: Int64) async throws {
        let chunkSize = 1_048_576  // 1 MB
        let inputHandle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? inputHandle.close() }

        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: destinationURL)
        defer { try? outputHandle.close() }

        var totalCopied: Int64 = 0

        while true {
            try Task.checkCancellation()
            guard let data = try inputHandle.read(upToCount: chunkSize), !data.isEmpty else {
                break
            }
            try outputHandle.write(contentsOf: data)
            totalCopied += Int64(data.count)
            let currentTotal = totalCopied
            await MainActor.run {
                exportProgress.bytesProcessed = currentTotal
            }
        }
    }
}
