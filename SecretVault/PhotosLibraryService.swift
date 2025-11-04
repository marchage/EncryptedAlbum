import Foundation
import Photos
import AppKit
import CoreLocation

enum LibraryType {
    case personal
    case shared
    case both
}

class PhotosLibraryService {
    static let shared = PhotosLibraryService()
    
    private init() {}
    
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
    
    func getAllAlbums(libraryType: LibraryType = .both) -> [(name: String, collection: PHAssetCollection)] {
        var albums: [(String, PHAssetCollection)] = []
        
        // Determine which library sources to include
        let includePersonal = libraryType == .personal || libraryType == .both
        let includeShared = libraryType == .shared || libraryType == .both
        
        // Explicitly fetch Hidden album FIRST (most important)
        if includePersonal || libraryType == .both {
            let hiddenAlbum = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: .smartAlbumAllHidden,
                options: nil
            )
            
            hiddenAlbum.enumerateObjects { collection, _, _ in
                // Include hidden assets when counting
                let countOptions = PHFetchOptions()
                if #available(macOS 13.0, *) {
                    countOptions.includeHiddenAssets = true
                }
                let assetCount = PHAsset.fetchAssets(in: collection, options: countOptions).count
                print("Found Hidden album with \(assetCount) items")
                
                var name = collection.localizedTitle ?? "Hidden"
                if libraryType == .both {
                    name = "👤 " + name
                }
                albums.append((name, collection))
            }
        }
        
        // User albums
        if includePersonal {
            let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
            userAlbums.enumerateObjects { collection, _, _ in
                if libraryType == .both {
                    let isShared = self.isSharedAlbum(collection)
                    let prefix = isShared ? "📤 " : "👤 "
                    albums.append((prefix + (collection.localizedTitle ?? "Untitled"), collection))
                } else {
                    albums.append((collection.localizedTitle ?? "Untitled", collection))
                }
            }
        }
        
        // Smart albums (including Hidden album)
        let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        smartAlbums.enumerateObjects { collection, _, _ in
            // Filter based on library type
            let isSharedAlbum = self.isSharedAlbum(collection)
            let shouldInclude = (includePersonal && !isSharedAlbum) || 
                               (includeShared && isSharedAlbum) ||
                               libraryType == .both
            
            if shouldInclude {
                var name = collection.localizedTitle ?? "Untitled"
                if libraryType == .both {
                    let prefix = isSharedAlbum ? "📤 " : "👤 "
                    name = prefix + name
                }
                // Avoid duplicating Hidden album
                if !albums.contains(where: { $0.0 == name }) {
                    albums.append((name, collection))
                }
            }
        }
        
        // Shared albums (only if including shared)
        if includeShared {
            let sharedAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumCloudShared, options: nil)
            sharedAlbums.enumerateObjects { collection, _, _ in
                let prefix = libraryType == .both ? "📤 " : ""
                albums.append((prefix + (collection.localizedTitle ?? "Shared Album"), collection))
            }
        }
        
        return albums.sorted { (a, b) in a.0 < b.0 }
    }
    
    private func isSharedAlbum(_ collection: PHAssetCollection) -> Bool {
        // Check if the album is from the shared library
        if #available(macOS 13.0, *) {
            let fetchOptions = PHFetchOptions()
            let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
            
            if assets.count > 0 {
                let firstAsset = assets.firstObject
                return firstAsset?.sourceType == .typeCloudShared
            }
        }
        
        // Fallback: check collection properties
        return collection.assetCollectionSubtype == .albumCloudShared
    }
    
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
    
    func getMediaData(for asset: PHAsset, completion: @escaping (Data?, String, Date?, MediaType, TimeInterval?, SecurePhoto.Location?, Bool?) -> Void) {
        if asset.mediaType == .video {
            getVideoData(for: asset, completion: completion)
        } else {
            getImageData(for: asset, completion: completion)
        }
    }
    
    func getImageData(for asset: PHAsset, completion: @escaping (Data?, String, Date?, MediaType, TimeInterval?, SecurePhoto.Location?, Bool?) -> Void) {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
            let resources = PHAssetResource.assetResources(for: asset)
            let filename = resources.first?.originalFilename ?? "photo_\(UUID().uuidString).jpg"
            let dateTaken = asset.creationDate
            
            // Extract metadata
            let location = asset.location.map { SecurePhoto.Location(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
            let isFavorite = asset.isFavorite
            
            DispatchQueue.main.async {
                completion(data, filename, dateTaken, .photo, nil, location, isFavorite)
            }
        }
    }
    
    func getVideoData(for asset: PHAsset, completion: @escaping (Data?, String, Date?, MediaType, TimeInterval?, SecurePhoto.Location?, Bool?) -> Void) {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            guard let urlAsset = avAsset as? AVURLAsset else {
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
                
                DispatchQueue.main.async {
                    completion(data, filename, dateTaken, .video, duration, location, isFavorite)
                }
            } catch {
                print("Failed to load video data: \(error)")
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
        guard NSImage(data: imageData) != nil else {
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }
        
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
    
    // Save media (photo or video) to library with metadata restoration
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
            guard NSImage(data: mediaData) != nil else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
            
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
}