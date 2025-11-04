import Foundation
import Photos

enum LibraryType {
    case personal
    case shared
    case both
}

class PhotosLibraryService {
    static let shared = PhotosLibraryService()
    
    private init() {}
    
    func requestAccess(completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }
    
    func getAllAlbums(libraryType: LibraryType = .both) -> [(name: String, collection: PHAssetCollection)] {
        var albums: [(String, PHAssetCollection)] = []
        
        // Determine which library sources to include
        let includePersonal = libraryType == .personal || libraryType == .both
        let includeShared = libraryType == .shared || libraryType == .both
        
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
        
        // Smart albums
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
                albums.append((name, collection))
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
        
        let result = PHAsset.fetchAssets(in: collection, options: fetchOptions)
        result.enumerateObjects { asset, _, _ in
            if asset.mediaType == .image {
                assets.append(asset)
            }
        }
        
        return assets
    }
    
    func getImageData(for asset: PHAsset, completion: @escaping (Data?, String, Date?) -> Void) {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
            let resources = PHAssetResource.assetResources(for: asset)
            let filename = resources.first?.originalFilename ?? "photo_\(UUID().uuidString).jpg"
            let dateTaken = asset.creationDate
            
            DispatchQueue.main.async {
                completion(data, filename, dateTaken)
            }
        }
    }
}
