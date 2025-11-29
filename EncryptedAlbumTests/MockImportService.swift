import Foundation
import Photos

#if canImport(EncryptedAlbum)
@testable import EncryptedAlbum
#else
@testable import EncryptedAlbum_iOS
#endif

final class MockImportService: ImportService {
    /// Assets this mock should report as successfully imported
    var successfulAssetsToReturn: [PHAsset] = []

    override func importAssets(_ assets: [PHAsset], hider: @escaping AssetHider) async -> [PHAsset] {
        // Do not call the real hider in this mock — just return the preconfigured list
        return successfulAssetsToReturn
    }
}
