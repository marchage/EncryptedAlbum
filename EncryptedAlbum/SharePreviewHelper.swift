import Foundation
import UniformTypeIdentifiers

/// Small helper used by both share extensions to count supported attachments and make tests easier.
public enum SharePreviewHelper {
    /// Count attachments that look like a supported file we would import (image, movie, or file-url)
    public static func countSupportedAttachments(in items: [NSExtensionItem]) -> Int {
        var total = 0
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
                    || provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
                    || provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                {
                    total += 1
                }
            }
        }
        return total
    }
}
