import SwiftUI

import SwiftUI

#if canImport(UIKit)
import UIKit

/// A simple SwiftUI wrapper around `UIActivityViewController` for sharing files on iOS.
public struct ActivityView: UIViewControllerRepresentable {
    public let activityItems: [Any]
    public let applicationActivities: [UIActivity]? = nil
    public let completion: ((Bool) -> Void)?

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            completion?(completed)
        }
        return controller
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#else
import AppKit

/// macOS wrapper that presents `NSSharingServicePicker` when inserted into the view hierarchy.
public struct ActivityView: NSViewRepresentable {
    public let activityItems: [Any]
    public let completion: ((Bool) -> Void)?

    public func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)

        DispatchQueue.main.async {
            guard !activityItems.isEmpty else {
                completion?(false)
                return
            }

            let picker = NSSharingServicePicker(items: activityItems)
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)

            // No reliable completion callback available; assume success when shown.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                completion?(true)
            }
        }

        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif


