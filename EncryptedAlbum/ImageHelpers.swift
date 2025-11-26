import SwiftUI

#if os(macOS)
    import AppKit
    typealias PlatformImage = NSImage
#else
    import UIKit
    typealias PlatformImage = UIImage
#endif

extension Image {
    init?(data: Data) {
        #if os(macOS)
            guard let nsImage = NSImage(data: data) else { return nil }
            self.init(nsImage: nsImage)
        #else
            guard let uiImage = UIImage(data: data) else { return nil }
            self.init(uiImage: uiImage)
        #endif
    }
    
    init(platformImage: PlatformImage) {
        #if os(macOS)
            self.init(nsImage: platformImage)
        #else
            self.init(uiImage: platformImage)
        #endif
    }
}
