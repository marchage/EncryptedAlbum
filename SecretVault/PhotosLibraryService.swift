import Foundation
import Photos

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
    
    func getAllAlbums() -> [(name: String, collection: PHAssetCollection)] {
        var albums: [(String, PHAssetCollection)] = []
        
        // User albums
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            albums.append((collection.localizedTitle ?? "Untitled", collection))
        }
        
        // Smart albums (including Hidden)
        let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        smartAlbums.enumerateObjects { collection, _, _ in
            albums.append((collection.localizedTitle ?? "Untitled", collection))
        }
        
        return albums.sorted { (a, b) in a.0 < b.0 }
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
