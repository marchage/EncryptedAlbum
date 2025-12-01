import Foundation
import Photos

#if canImport(EncryptedAlbum)
    @testable import EncryptedAlbum
#else
    @testable import EncryptedAlbum_iOS
#endif

final class MockPhotosLibraryService: PhotosLibraryServiceProtocol {
    var savedFiles: [(url: URL, filename: String, mediaType: MediaType)] = []
    var batchDeletedAssets: [[PHAsset]] = []
    var saveCompletions: [((Bool, Error?) -> Void)] = []

    func requestAccess(completion: @escaping (Bool) -> Void) {
        completion(true)
    }

    func getAllAlbums(libraryType: LibraryType) -> [(name: String, collection: PHAssetCollection)] { [] }

    func getAssets(from collection: PHAssetCollection) -> [PHAsset] { [] }

    func getMediaDataAsync(for asset: PHAsset) async -> MediaFetchResult? { return nil }

    func saveMediaFileToLibrary(
        _ fileURL: URL, filename: String, mediaType: MediaType, toAlbum albumName: String?, creationDate: Date?,
        location: SecurePhoto.Location?, isFavorite: Bool?, completion: @escaping (Bool, Error?) -> Void
    ) {
        savedFiles.append((fileURL, filename, mediaType))
        // record completion to allow tests to trigger different outcomes
        saveCompletions.append(completion)
        // by default succeed
        completion(true, nil)
    }

    func batchDeleteAssets(_ assets: [PHAsset], completion: @escaping (Bool) -> Void) {
        batchDeletedAssets.append(assets)
        completion(true)
    }

    func batchSaveMediaToLibrary(
        _ mediaItems: [(
            data: Data, filename: String, mediaType: MediaType, creationDate: Date?, location: SecurePhoto.Location?,
            isFavorite: Bool?
        )], toAlbum albumName: String?, completion: @escaping (Int) -> Void
    ) {
        completion(0)
    }
}
