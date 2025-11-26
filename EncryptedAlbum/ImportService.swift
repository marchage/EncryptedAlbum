import Foundation
import Photos
import SwiftUI

// Import progress tracking
class ImportProgress: ObservableObject {
    @Published var isImporting = false
    @Published var totalItems = 0
    @Published var processedItems = 0
    @Published var successItems = 0
    @Published var failedItems = 0
    @Published var currentBytesProcessed: Int64 = 0
    @Published var currentBytesTotal: Int64 = 0
    @Published var statusMessage: String = ""
    @Published var detailMessage: String = ""
    @Published var cancelRequested = false

    var progress: Double {
        guard totalItems > 0 else { return 0 }
        return Double(processedItems) / Double(totalItems)
    }

    func reset() {
        isImporting = false
        totalItems = 0
        processedItems = 0
        successItems = 0
        failedItems = 0
        currentBytesProcessed = 0
        currentBytesTotal = 0
        statusMessage = ""
        detailMessage = ""
        cancelRequested = false
    }
}

/// Service responsible for importing assets from the Photo Library into the album
class ImportService {
    private let progress: ImportProgress
    
    /// Closure type for hiding an asset. Matches AlbumManager.hidePhoto signature components.
    typealias AssetHider = (
        _ mediaSource: MediaSource,
        _ filename: String,
        _ dateTaken: Date?,
        _ sourceAlbum: String?,
        _ assetIdentifier: String?,
        _ mediaType: MediaType,
        _ duration: TimeInterval?,
        _ location: SecurePhoto.Location?,
        _ isFavorite: Bool?,
        _ progressHandler: ((Int64) async -> Void)?
    ) async throws -> Void
    
    init(progress: ImportProgress) {
        self.progress = progress
    }
    
    /// Imports assets from Photo Library into the album
    /// - Parameters:
    ///   - assets: The assets to import
    ///   - hider: The closure to call to actually hide/encrypt the asset
    /// - Returns: The list of successfully imported assets (so they can be deleted from library)
    func importAssets(_ assets: [PHAsset], hider: @escaping AssetHider) async -> [PHAsset] {
        guard !assets.isEmpty else { return [] }
        
        await MainActor.run {
            progress.reset()
            progress.isImporting = true
            progress.totalItems = assets.count
            progress.statusMessage = "Preparing import…"
            progress.detailMessage = "\(assets.count) item(s)"
        }

        // Add overall timeout to prevent hanging
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 300_000_000_000)  // 5 minute overall timeout
            if !Task.isCancelled {
                print("⚠️ Overall hide operation timed out after 5 minutes")
                await MainActor.run {
                    progress.isImporting = false
                    progress.statusMessage = "Import timed out"
                }
            }
        }

        defer {
            timeoutTask.cancel()
        }

        // Process assets with limited concurrency
        let maxConcurrentOperations = 2
        var successfulAssets: [PHAsset] = []

        // Create indexed list for tracking
        let indexedAssets = assets.enumerated().map { (index: $0.offset, asset: $0.element) }

        // Process assets in batches
        for batch in indexedAssets.chunked(into: maxConcurrentOperations) {
            if await MainActor.run(body: { progress.cancelRequested }) { break }
            
            let batchSuccessful = await withTaskGroup(of: (PHAsset, Bool).self) { group -> [PHAsset] in
                for (index, asset) in batch {
                    group.addTask {
                        await self.processSingleImport(asset: asset, index: index, total: assets.count, hider: hider)
                    }
                }

                var batchAssets: [PHAsset] = []
                // Collect results
                for await (asset, success) in group {
                    if success {
                        batchAssets.append(asset)
                    }
                    await MainActor.run {
                        progress.processedItems += 1
                        if success {
                            progress.successItems += 1
                        } else {
                            progress.failedItems += 1
                        }
                    }
                }
                return batchAssets
            }
            successfulAssets.append(contentsOf: batchSuccessful)
        }
        
        return successfulAssets
    }

    private func processSingleImport(
        asset: PHAsset, 
        index: Int, 
        total: Int, 
        hider: @escaping AssetHider
    ) async -> (PHAsset, Bool) {
        let itemNumber = index + 1
        
        guard let mediaResult = await PhotosLibraryService.shared.getMediaDataAsync(for: asset) else {
            print("❌ Failed to get media data for asset: \(asset.localIdentifier)")
            await MainActor.run {
                progress.detailMessage = "Failed to fetch item \(itemNumber)"
            }
            return (asset, false)
        }

        let fileSizeValue = estimatedSize(for: mediaResult)
        let sizeDescription = ByteCountFormatter.string(fromByteCount: fileSizeValue, countStyle: .file)

        await MainActor.run {
            progress.statusMessage = "Encrypting \(mediaResult.filename)…"
            progress.detailMessage = "Item \(itemNumber) of \(total) • \(sizeDescription)"
            progress.currentBytesTotal = fileSizeValue
            progress.currentBytesProcessed = 0
        }

        let cleanupURL = mediaResult.shouldDeleteFileWhenFinished ? mediaResult.fileURL : nil
        let progressHandler: ((Int64) async -> Void)? = mediaResult.fileURL != nil ? { bytesRead in
            await MainActor.run {
                self.progress.currentBytesProcessed = bytesRead
            }
        } : nil

        do {
            let mediaSource: MediaSource
            if let fileURL = mediaResult.fileURL {
                mediaSource = .fileURL(fileURL)
            } else if let mediaData = mediaResult.data {
                mediaSource = .data(mediaData)
            } else {
                return (asset, false)
            }

            defer {
                if let cleanupURL = cleanupURL {
                    try? FileManager.default.removeItem(at: cleanupURL)
                }
            }

            try await hider(
                mediaSource,
                mediaResult.filename,
                mediaResult.dateTaken,
                nil, // sourceAlbum
                asset.localIdentifier,
                mediaResult.mediaType,
                mediaResult.duration,
                mediaResult.location,
                mediaResult.isFavorite,
                progressHandler
            )

            return (asset, true)
        } catch {
            print("❌ Failed to add media to album: \(error.localizedDescription)")
            return (asset, false)
        }
    }

    private func estimatedSize(for mediaResult: MediaFetchResult) -> Int64 {
        if let fileURL = mediaResult.fileURL {
            return (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        }
        if let data = mediaResult.data {
            return Int64(data.count)
        }
        return 0
    }
}

// Helper extension for chunking
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
