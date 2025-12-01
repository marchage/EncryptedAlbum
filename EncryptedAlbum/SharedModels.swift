import Foundation
import SwiftUI

// Small, widely used models shared across the app UI. These are intentionally
// extracted out of AlbumManager so views can compile independently of that
// large file during refactors.

public enum MediaType: String, Codable {
    case photo
    case video
}

/// Describes how raw media should be read when encrypting or importing.
public enum MediaSource {
    case data(Data)
    case fileURL(URL)
}

public enum HideNotificationType {
    case success
    case failure
    case info
}

public struct HideNotification {
    public let message: String
    public let type: HideNotificationType
    public let photos: [SecurePhoto]?

    public init(message: String, type: HideNotificationType, photos: [SecurePhoto]?) {
        self.message = message
        self.type = type
        self.photos = photos
    }
}

public struct SecurePhoto: Identifiable, Codable {
    public let id: UUID
    public var encryptedDataPath: String
    public var thumbnailPath: String
    public var encryptedThumbnailPath: String?
    public var filename: String
    public var dateAdded: Date
    public var dateTaken: Date?
    public var sourceAlbum: String?
    public var albumAlbum: String?
    public var fileSize: Int64
    public var originalAssetIdentifier: String?
    public var mediaType: MediaType
    public var duration: TimeInterval?
    public var location: Location?
    public var isFavorite: Bool?

    public struct Location: Codable {
        public let latitude: Double
        public let longitude: Double
    }

    public init(
        id: UUID = UUID(),
        encryptedDataPath: String,
        thumbnailPath: String,
        encryptedThumbnailPath: String? = nil,
        filename: String,
        dateTaken: Date? = nil,
        sourceAlbum: String? = nil,
        albumAlbum: String? = nil,
        fileSize: Int64 = 0,
        originalAssetIdentifier: String? = nil,
        mediaType: MediaType = .photo,
        duration: TimeInterval? = nil,
        location: Location? = nil,
        isFavorite: Bool? = nil
    ) {
        self.id = id
        self.encryptedDataPath = encryptedDataPath
        self.thumbnailPath = thumbnailPath
        self.encryptedThumbnailPath = encryptedThumbnailPath
        self.filename = filename
        self.dateAdded = Date()
        self.dateTaken = dateTaken
        self.sourceAlbum = sourceAlbum
        self.albumAlbum = albumAlbum
        self.fileSize = fileSize
        self.originalAssetIdentifier = originalAssetIdentifier
        self.mediaType = mediaType
        self.duration = duration
        self.location = location
        self.isFavorite = isFavorite
    }
}

@MainActor
public class DirectImportProgress: ObservableObject {
    @Published public var isImporting: Bool = false
    @Published public var statusMessage: String = ""
    @Published public var detailMessage: String = ""
    @Published public var itemsProcessed: Int = 0
    @Published public var itemsTotal: Int = 0
    @Published public var bytesProcessed: Int64 = 0
    @Published public var bytesTotal: Int64 = 0
    @Published public var cancelRequested: Bool = false
    private var lastBytesUpdateTime: CFAbsoluteTime = 0
    private var lastReportedBytes: Int64 = 0

    public init() {}

    public func reset(totalItems: Int) {
        isImporting = true
        statusMessage = "Preparing import…"
        detailMessage = "\(totalItems) item(s)"
        itemsProcessed = 0
        itemsTotal = totalItems
        bytesProcessed = 0
        bytesTotal = 0
        cancelRequested = false
        lastBytesUpdateTime = 0
        lastReportedBytes = 0
    }

    public func finish() {
        isImporting = false
        statusMessage = ""
        detailMessage = ""
        itemsProcessed = 0
        itemsTotal = 0
        bytesProcessed = 0
        bytesTotal = 0
        cancelRequested = false
        lastBytesUpdateTime = 0
        lastReportedBytes = 0
    }

    public func throttledUpdateBytesProcessed(_ value: Int64) {
        let clampedValue = max(0, value)
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastBytesUpdateTime
        let byteDelta = abs(clampedValue - lastReportedBytes)

        let minimumInterval: CFTimeInterval = 0.05
        let minimumByteDelta = max(bytesTotal / 200, Int64(128 * 1024))

        if lastBytesUpdateTime == 0 || elapsed >= minimumInterval || byteDelta >= minimumByteDelta
            || clampedValue >= bytesTotal
        {
            bytesProcessed = min(clampedValue, bytesTotal > 0 ? bytesTotal : clampedValue)
            lastReportedBytes = clampedValue
            lastBytesUpdateTime = now
        }
    }

    public func forceUpdateBytesProcessed(_ value: Int64) {
        let clampedValue = max(0, value)
        bytesProcessed = min(clampedValue, bytesTotal > 0 ? bytesTotal : clampedValue)
        lastReportedBytes = clampedValue
        lastBytesUpdateTime = CFAbsoluteTimeGetCurrent()
    }
}
// (Duplicate local model definitions removed — SharedModels.swift keeps the public model types above.)
