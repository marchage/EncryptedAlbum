import Foundation
import UniformTypeIdentifiers

enum SharePreviewHelper {
    static func countSupportedAttachments(in items: [NSExtensionItem]) -> Int {
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
