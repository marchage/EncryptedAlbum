import Foundation
import Photos
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
import CoreLocation

enum LibraryType {
    case personal
    case shared
    case both
}

/// Service for interacting with the Photos library across platforms.
class PhotosLibraryService {
    static let shared = PhotosLibraryService()
    
    private init() {}
    
    /// Requests read/write access to the Photos library.
    /// - Parameter completion: Called with true if access granted, false otherwise
    func requestAccess(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch status {
        case .authorized, .limited:
            DispatchQueue.main.async {
                completion(true)
            }
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    completion(newStatus == .authorized || newStatus == .limited)
                }
            }
        default:
            DispatchQueue.main.async {
                completion(false)
            }
        }
    }
    
    /// Fetches all albums from the Photos library.
    /// - Parameter libraryType: Type of library to fetch from (.personal, .shared, or .both)
    /// - Returns: Array of tuples containing album name and collection
    func getAllAlbums(libraryType: LibraryType = .both) -> [(name: String, collection: PHAssetCollection)] {
        var albums: [(String, PHAssetCollection)] = []
        var seenIds = Set<String>() // Avoid duplicates across different fetches
        
        NSLog("📚 getAllAlbums called with libraryType: \(libraryType)")
        
        // Explicitly fetch Hidden album FIRST (most important) - always from personal library
        if libraryType == .personal || libraryType == .both {
            let hiddenAlbum = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: .smartAlbumAllHidden,
                options: nil
            )
            
            hiddenAlbum.enumerateObjects { collection, _, _ in
                let countOptions = PHFetchOptions()
                if #available(macOS 13.0, *) {
                    countOptions.includeHiddenAssets = true
                }
                let assetCount = PHAsset.fetchAssets(in: collection, options: countOptions).count
                NSLog("Found Hidden album with \(assetCount) items")
                
                var name = collection.localizedTitle ?? "Hidden"
                if libraryType == .both {
                    name = "👤 " + name
                }
                albums.append((name, collection))
            }
        }
        
        // Fetch user albums and filter based on library type
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            let albumName = collection.localizedTitle ?? "Untitled"
            let subtypeRaw = collection.assetCollectionSubtype.rawValue
            NSLog("  🧭 Album subtype raw=\(subtypeRaw) name='\(albumName)'")
            
            // Determine if this is a "shared" album (either cloud shared album OR from shared library)
            let isCloudSharedAlbum = collection.assetCollectionSubtype == .albumCloudShared
            let isFromSharedLibrary = isCloudSharedAlbum || self.isFromSharedLibrary(collection)
            
            NSLog("  📁 Album '\(albumName)': cloudShared=\(isCloudSharedAlbum), assetFromShared=\(self.isFromSharedLibrary(collection)), final isShared=\(isFromSharedLibrary)")
            
            // Apply library type filter
            if libraryType == .personal && isFromSharedLibrary {
                NSLog("    ⛔ Skipped (personal filter, album is shared)")
                return // Skip shared albums in personal view
            }
            if libraryType == .shared && !isFromSharedLibrary {
                NSLog("    ⛔ Skipped (shared filter, album is personal)")
                return // Skip personal albums in shared view
            }
            
            // Add album with appropriate prefix
            var name = albumName
            if libraryType == .both {
                name = (isFromSharedLibrary ? "📤 " : "👤 ") + name
            }
            if !seenIds.contains(collection.localIdentifier) {
                NSLog("    ✅ Added: \(name)")
                albums.append((name, collection))
                seenIds.insert(collection.localIdentifier)
            } else {
                NSLog("    🔁 Skipped duplicate id=\(collection.localIdentifier)")
            }
        }
        
        // Explicit fetch of Cloud Shared Albums (albums you explicitly share with people)
        let cloudShared = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumCloudShared, options: nil)
        cloudShared.enumerateObjects { collection, _, _ in
            let albumName = collection.localizedTitle ?? "Shared Album"
            let isShared = true // By definition
            
            if libraryType == .personal && isShared {
                NSLog("    ⛔ Skipped cloud shared in personal view: \(albumName)")
                return
            }
            if libraryType == .shared || libraryType == .both {
                var name = albumName
                if libraryType == .both { name = "📤 " + name }
                if !seenIds.contains(collection.localIdentifier) {
                    NSLog("    ✅ Added cloud shared: \(name)")
                    albums.append((name, collection))
                    seenIds.insert(collection.localIdentifier)
                }
            }
        }
        
        // Smart albums
        let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        smartAlbums.enumerateObjects { collection, _, _ in
            // Check if from shared library
            let isFromSharedLibrary = self.isFromSharedLibrary(collection)
            
            // Apply library type filter
            if libraryType == .personal && isFromSharedLibrary {
                return
            }
            if libraryType == .shared && !isFromSharedLibrary {
                return
            }
            
            var name = collection.localizedTitle ?? "Untitled"
            if libraryType == .both {
                name = (isFromSharedLibrary ? "📤 " : "👤 ") + name
            }
            
            // Avoid duplicating Hidden album
            if !seenIds.contains(collection.localIdentifier) {
                albums.append((name, collection))
                seenIds.insert(collection.localIdentifier)
            }
        }
        
        return albums.sorted { (a, b) in a.0 < b.0 }
    }
    
    private func isFromSharedLibrary(_ collection: PHAssetCollection) -> Bool {
        // Check if the album's assets are from iCloud Shared Photo Library
        if #available(macOS 13.0, *) {
            let fetchOptions = PHFetchOptions()
            fetchOptions.fetchLimit = 5 // Check first 5 assets to be sure
            let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
            
            var sharedCount = 0
            var totalCount = 0
            
            assets.enumerateObjects { asset, _, _ in
                totalCount += 1
                let sourceType = asset.sourceType
                
                // Check if this is a shared library asset
                // sourceType values: 1 = typeUserLibrary, 2 = typeCloudShared, 8 = typeiTunesSynced
                if sourceType == .typeCloudShared {
                    sharedCount += 1
                }
            }
            
            // If majority of assets are from shared library, consider the album as shared
            let isShared = sharedCount > 0 && (Double(sharedCount) / Double(totalCount)) > 0.5
            return isShared
        }
        
        return false
    }
    
    /// Gets all photo and video assets from a collection.
    /// - Parameter collection: The asset collection to fetch from
    /// - Returns: Array of PHAsset items
    func getAssets(from collection: PHAssetCollection) -> [PHAsset] {
        var assets: [PHAsset] = []
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // Critical: include hidden assets when fetching from the Hidden smart album
        if #available(macOS 13.0, *), collection.assetCollectionSubtype == .smartAlbumAllHidden {
            fetchOptions.includeHiddenAssets = true
        }
        
        let result = PHAsset.fetchAssets(in: collection, options: fetchOptions)
        result.enumerateObjects { asset, _, _ in
            if asset.mediaType == .image || asset.mediaType == .video {
                assets.append(asset)
            }
        }
        
        return assets
    }
    
    /// Retrieves media data for a Photos asset asynchronously.
    /// - Parameter asset: The PHAsset to fetch
    /// - Returns: Tuple with data, filename, metadata, and type
    func getMediaDataAsync(for asset: PHAsset) async -> (data: Data?, filename: String, dateTaken: Date?, mediaType: MediaType, duration: TimeInterval?, location: SecurePhoto.Location?, isFavorite: Bool?)? {
        // Use Task with timeout pattern for better control
        let result = await withTaskGroup(of: (data: Data?, filename: String, dateTaken: Date?, mediaType: MediaType, duration: TimeInterval?, location: SecurePhoto.Location?, isFavorite: Bool?)?.self) { group in
            // Add timeout task
            group.addTask {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 second timeout
                print("⏱️ Timeout (30s) fetching media data for asset: \(asset.localIdentifier)")
                return nil
            }
            
            // Add actual fetch task
            group.addTask {
                await withCheckedContinuation { continuation in
                    if asset.mediaType == .image {
                        self.getImageData(for: asset) { data, filename, dateTaken, mediaType, duration, location, isFavorite in
                            continuation.resume(returning: (data: data, filename: filename, dateTaken: dateTaken, mediaType: mediaType, duration: duration, location: location, isFavorite: isFavorite))
                        }
                    } else if asset.mediaType == .video {
                        self.getVideoData(for: asset) { data, filename, dateTaken, mediaType, duration, location, isFavorite in
                            continuation.resume(returning: (data: data, filename: filename, dateTaken: dateTaken, mediaType: mediaType, duration: duration, location: location, isFavorite: isFavorite))
                        }
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
            
            // Return the first result (either timeout or actual data)
            if let firstResult = await group.next() {
                group.cancelAll() // Cancel the other task
                return firstResult
            }
            return nil
        }
        
        return result
    }
    
    func getImageData(for asset: PHAsset, completion: @escaping (Data?, String, Date?, MediaType, TimeInterval?, SecurePhoto.Location?, Bool?) -> Void) {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
            // Check for errors or cancellation
            if let error = info?[PHImageErrorKey] as? Error {
                print("❌ PHImageManager error for asset \(asset.localIdentifier): \(error.localizedDescription)")
            }
            
            if let isCancelled = info?[PHImageCancelledKey] as? Bool, isCancelled {
                print("⚠️ Image request was cancelled for asset \(asset.localIdentifier)")
                DispatchQueue.main.async {
                    completion(nil, "", nil, .photo, nil, nil, nil)
                }
                return
            }
            
            let resources = PHAssetResource.assetResources(for: asset)
            let filename = resources.first?.originalFilename ?? "photo_\(UUID().uuidString).jpg"
            let dateTaken = asset.creationDate
            
            // Extract metadata
            let location = asset.location.map { SecurePhoto.Location(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
            let isFavorite = asset.isFavorite
            
            // Log result
            if let data = data {
                print("✅ Successfully retrieved image data for \(filename): \(data.count) bytes")
            } else {
                print("❌ Image data is nil for asset \(asset.localIdentifier), filename: \(filename)")
            }
            
            DispatchQueue.main.async {
                completion(data, filename, dateTaken, .photo, nil, location, isFavorite)
            }
        }
    }
    
    func getVideoData(for asset: PHAsset, completion: @escaping (Data?, String, Date?, MediaType, TimeInterval?, SecurePhoto.Location?, Bool?) -> Void) {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
            // Check for errors
            if let error = info?[PHImageErrorKey] as? Error {
                print("❌ Video request error for asset \(asset.localIdentifier): \(error.localizedDescription)")
            }
            
            guard let urlAsset = avAsset as? AVURLAsset else {
                print("❌ Failed to get AVURLAsset for video \(asset.localIdentifier)")
                DispatchQueue.main.async {
                    completion(nil, "", nil, .video, nil, nil, nil)
                }
                return
            }
            
            do {
                let data = try Data(contentsOf: urlAsset.url)
                let resources = PHAssetResource.assetResources(for: asset)
                let filename = resources.first?.originalFilename ?? "video_\(UUID().uuidString).mov"
                let dateTaken = asset.creationDate
                let duration = asset.duration
                
                // Extract metadata
                let location = asset.location.map { SecurePhoto.Location(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
                let isFavorite = asset.isFavorite
                
                print("✅ Successfully retrieved video data for \(filename): \(data.count) bytes")
                
                DispatchQueue.main.async {
                    completion(data, filename, dateTaken, .video, duration, location, isFavorite)
                }
            } catch {
                print("❌ Failed to load video data for \(asset.localIdentifier): \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil, "", nil, .video, nil, nil, nil)
                }
            }
        }
    }
    
    func hideAssetInLibrary(_ asset: PHAsset, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetChangeRequest(for: asset)
            request.isHidden = true
        }) { success, error in
            if let error = error {
                print("Failed to hide photo in library: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
    
    /// Permanently deletes an asset from the Photos library.
    /// - Parameters:
    ///   - asset: The PHAsset to delete
    ///   - completion: Called with true if successful
    func deleteAssetFromLibrary(_ asset: PHAsset, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }) { success, error in
            if let error = error {
                print("Failed to delete photo from library: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
    
    /// Deletes multiple assets from the Photos library in a single transaction.
    /// - Parameters:
    ///   - assets: Array of PHAssets to delete
    ///   - completion: Called with true if successful
    func batchDeleteAssets(_ assets: [PHAsset], completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }) { success, error in
            if let error = error {
                print("Failed to batch delete photos from library: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
    
    func saveImageToLibrary(_ imageData: Data, filename: String, toAlbum albumName: String? = nil, completion: @escaping (Bool) -> Void) {
        // Validate that we can create an image from the data
        #if os(macOS)
        guard NSImage(data: imageData) != nil else {
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }
        #else
        guard UIImage(data: imageData) != nil else {
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }
        #endif
        
        PHPhotoLibrary.shared().performChanges({
            let creationRequest = PHAssetCreationRequest.forAsset()
            creationRequest.addResource(with: .photo, data: imageData, options: nil)
            
            // Add to album if specified
            if let albumName = albumName, let assetPlaceholder = creationRequest.placeholderForCreatedAsset {
                // Try to find existing album
                let fetchOptions = PHFetchOptions()
                fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
                let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
                
                if let album = collections.firstObject {
                    // Add to existing album
                    if let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) {
                        albumChangeRequest.addAssets([assetPlaceholder] as NSArray)
                    }
                } else {
                    // Create new album and add photo
                    let createAlbumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                    // Add the asset to the newly created album
                    createAlbumRequest.addAssets([assetPlaceholder] as NSArray)
                }
            }
        }) { success, error in
            if let error = error {
                print("Failed to save photo to library: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
    
    /// Saves media (photo or video) to the Photos library with metadata.
    /// - Parameters:
    ///   - mediaData: Raw media data
    ///   - filename: Filename for the media
    ///   - mediaType: Type of media (.photo or .video)
    ///   - albumName: Optional album to save to
    ///   - creationDate: Original creation date
    ///   - location: GPS coordinates
    ///   - isFavorite: Favorite status
    ///   - completion: Called with true if successful
    func saveMediaToLibrary(_ mediaData: Data, filename: String, mediaType: MediaType, toAlbum albumName: String? = nil, creationDate: Date? = nil, location: SecurePhoto.Location? = nil, isFavorite: Bool? = nil, completion: @escaping (Bool) -> Void) {
        // For videos, we need to save to a temporary file first
        if mediaType == .video {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            do {
                try mediaData.write(to: tempURL)
                
                PHPhotoLibrary.shared().performChanges({
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationRequest.addResource(with: .video, fileURL: tempURL, options: nil)
                    
                    // Set metadata
                    if let creationDate = creationDate {
                        creationRequest.creationDate = creationDate
                    }
                    if let location = location {
                        creationRequest.location = CLLocation(latitude: location.latitude, longitude: location.longitude)
                    }
                    if let isFavorite = isFavorite {
                        creationRequest.isFavorite = isFavorite
                    }
                    
                    // Add to album if specified
                    if let albumName = albumName, let assetPlaceholder = creationRequest.placeholderForCreatedAsset {
                        // Try to find existing album
                        let fetchOptions = PHFetchOptions()
                        fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
                        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
                        
                        if let album = collections.firstObject {
                            // Add to existing album
                            if let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) {
                                albumChangeRequest.addAssets([assetPlaceholder] as NSArray)
                            }
                        } else {
                            // Create new album and add video
                            let createAlbumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                            createAlbumRequest.addAssets([assetPlaceholder] as NSArray)
                        }
                    }
                }) { success, error in
                    // Clean up temp file
                    try? FileManager.default.removeItem(at: tempURL)
                    
                    if let error = error {
                        print("Failed to save video to library: \(error.localizedDescription)")
                    }
                    DispatchQueue.main.async {
                        completion(success)
                    }
                }
            } catch {
                print("Failed to write video to temp file: \(error)")
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        } else {
            // For photos, save with metadata
            #if os(macOS)
            guard NSImage(data: mediaData) != nil else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
            #else
            guard UIImage(data: mediaData) != nil else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
            #endif
            
            PHPhotoLibrary.shared().performChanges({
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: mediaData, options: nil)
                
                // Set metadata
                if let creationDate = creationDate {
                    creationRequest.creationDate = creationDate
                }
                if let location = location {
                    creationRequest.location = CLLocation(latitude: location.latitude, longitude: location.longitude)
                }
                if let isFavorite = isFavorite {
                    creationRequest.isFavorite = isFavorite
                }
                
                // Add to album if specified
                if let albumName = albumName, let assetPlaceholder = creationRequest.placeholderForCreatedAsset {
                    // Try to find existing album
                    let fetchOptions = PHFetchOptions()
                    fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
                    let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
                    
                    if let album = collections.firstObject {
                        // Add to existing album
                        if let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) {
                            albumChangeRequest.addAssets([assetPlaceholder] as NSArray)
                        }
                    } else {
                        // Create new album and add photo
                        let createAlbumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                        createAlbumRequest.addAssets([assetPlaceholder] as NSArray)
                    }
                }
            }) { success, error in
                if let error = error {
                    print("Failed to save photo to library: \(error.localizedDescription)")
                }
                DispatchQueue.main.async {
                    completion(success)
                }
            }
        }
    }
    
    // Batch save multiple media items to library - prevents duplicate album creation
    func batchSaveMediaToLibrary(_ mediaItems: [(data: Data, filename: String, mediaType: MediaType, creationDate: Date?, location: SecurePhoto.Location?, isFavorite: Bool?)], toAlbum albumName: String? = nil, completion: @escaping (Int) -> Void) {
        // Write all videos to temp files first
        var tempVideoFiles: [(url: URL, filename: String)] = []
        for item in mediaItems where item.mediaType == .video {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(item.filename)
            do {
                try item.data.write(to: tempURL)
                tempVideoFiles.append((url: tempURL, filename: item.filename))
            } catch {
                print("Failed to write temp video file: \(error)")
            }
        }
        
        // Perform all changes in a single transaction
        PHPhotoLibrary.shared().performChanges({
            var albumRequest: PHAssetCollectionChangeRequest? = nil
            
            // Find or create album once
            if let albumName = albumName {
                let fetchOptions = PHFetchOptions()
                fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
                let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
                
                if let existingAlbum = collections.firstObject {
                    albumRequest = PHAssetCollectionChangeRequest(for: existingAlbum)
                } else {
                    let createAlbumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                    albumRequest = createAlbumRequest
                }
            }
            
            // Add all assets
            var successCount = 0
            for item in mediaItems {
                let creationRequest = PHAssetCreationRequest.forAsset()
                
                // Add media resource
                if item.mediaType == .video {
                    if let tempFile = tempVideoFiles.first(where: { $0.filename == item.filename }) {
                        creationRequest.addResource(with: .video, fileURL: tempFile.url, options: nil)
                    } else {
                        continue
                    }
                } else {
                    creationRequest.addResource(with: .photo, data: item.data, options: nil)
                }
                
                // Set metadata
                if let creationDate = item.creationDate {
                    creationRequest.creationDate = creationDate
                }
                if let location = item.location {
                    creationRequest.location = CLLocation(latitude: location.latitude, longitude: location.longitude)
                }
                if let isFavorite = item.isFavorite {
                    creationRequest.isFavorite = isFavorite
                }
                
                // Add to album
                if let assetPlaceholder = creationRequest.placeholderForCreatedAsset {
                    albumRequest?.addAssets([assetPlaceholder] as NSArray)
                    successCount += 1
                }
            }
            
        }) { success, error in
            // Clean up temp video files
            for tempFile in tempVideoFiles {
                try? FileManager.default.removeItem(at: tempFile.url)
            }
            
            if let error = error {
                print("Failed to batch save media to library: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(0)
                }
            } else {
                DispatchQueue.main.async {
                    completion(mediaItems.count)
                }
            }
        }
    }
}