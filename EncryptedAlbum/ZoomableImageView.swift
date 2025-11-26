import SwiftUI
import AVKit

#if os(macOS)
    import AppKit
#endif
#if os(iOS)
    import UIKit
#endif

// MARK: - Zoomable Image View

#if os(iOS)
    struct ZoomableImageView: UIViewControllerRepresentable {
        let image: UIImage

        func makeUIViewController(context: Context) -> ZoomableImageViewController {
            return ZoomableImageViewController(image: image)
        }

        func updateUIViewController(_ uiViewController: ZoomableImageViewController, context: Context) {
            uiViewController.updateImage(image)
        }
    }

    class ZoomableImageViewController: UIViewController, UIScrollViewDelegate {
        private let scrollView = UIScrollView()
        private let imageView = UIImageView()
        private var image: UIImage

        init(image: UIImage) {
            self.image = image
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()

            view.backgroundColor = .clear
            
            scrollView.delegate = self
            scrollView.frame = view.bounds
            scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            scrollView.minimumZoomScale = 1.0
            scrollView.maximumZoomScale = 5.0
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.showsVerticalScrollIndicator = false
            view.addSubview(scrollView)

            imageView.image = image
            imageView.contentMode = .scaleAspectFit
            imageView.frame = scrollView.bounds
            scrollView.addSubview(imageView)

            let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTapGesture.numberOfTapsRequired = 2
            scrollView.addGestureRecognizer(doubleTapGesture)
            
            updateLayout()
        }
        
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            updateLayout()
        }

        func updateImage(_ newImage: UIImage) {
            guard newImage != image else { return }
            image = newImage
            imageView.image = image
            updateLayout()
        }
        
        private func updateLayout() {
            // Reset zoom to calculate proper frames
            scrollView.zoomScale = 1.0
            
            guard let image = imageView.image else { return }
            
            let widthRatio = view.bounds.width / image.size.width
            let heightRatio = view.bounds.height / image.size.height
            let scale = min(widthRatio, heightRatio)
            
            let scaledWidth = image.size.width * scale
            let scaledHeight = image.size.height * scale
            
            // Center the image view within the scroll view
            imageView.frame = CGRect(
                x: (view.bounds.width - scaledWidth) / 2,
                y: (view.bounds.height - scaledHeight) / 2,
                width: scaledWidth,
                height: scaledHeight
            )
            
            scrollView.contentSize = view.bounds.size
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return imageView
        }
        
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
            let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
            
            scrollView.contentInset = UIEdgeInsets(top: offsetY, left: offsetX, bottom: 0, right: 0)
        }

        @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            if scrollView.zoomScale > 1.0 {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let scrollSize = scrollView.frame.size
                let size = CGSize(width: scrollSize.width / 3.0, height: scrollSize.height / 3.0)
                let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
                scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
            }
        }
    }

#elseif os(macOS)
    struct ZoomableImageView: NSViewRepresentable {
        let image: NSImage

        func makeNSView(context: Context) -> NSScrollView {
            let scrollView = NSScrollView()
            scrollView.allowsMagnification = true
            scrollView.minMagnification = 1.0
            scrollView.maxMagnification = 5.0
            scrollView.hasHorizontalScroller = true
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = true
            scrollView.backgroundColor = .clear
            scrollView.drawsBackground = false
            
            // Enable frame change notifications for layout updates
            scrollView.postsFrameChangedNotifications = true
            scrollView.postsBoundsChangedNotifications = true
            
            let clipView = CenteredClipView()
            scrollView.contentView = clipView

            let imageView = NSImageView()
            imageView.image = image
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.animates = false
            
            // Set initial frame to image size so it's not 0
            imageView.frame = CGRect(origin: .zero, size: image.size)
            
            scrollView.documentView = imageView
            
            // Listen for frame changes to update layout (fit to screen)
            NotificationCenter.default.addObserver(
                context.coordinator,
                selector: #selector(Coordinator.handleResize),
                name: NSView.frameDidChangeNotification,
                object: scrollView
            )
            
            // Initial layout attempt
            DispatchQueue.main.async {
                context.coordinator.updateLayout(scrollView: scrollView)
            }
            
            return scrollView
        }

        static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
            NotificationCenter.default.removeObserver(coordinator)
        }

        func updateNSView(_ scrollView: NSScrollView, context: Context) {
            if let imageView = scrollView.documentView as? NSImageView {
                if imageView.image != image {
                    imageView.image = image
                    // Reset zoom
                    scrollView.magnification = 1.0
                    context.coordinator.updateLayout(scrollView: scrollView)
                }
            }
        }
        
        func makeCoordinator() -> Coordinator {
            Coordinator()
        }
        
        class Coordinator: NSObject {
            @objc func handleResize(_ notification: Notification) {
                guard let scrollView = notification.object as? NSScrollView else { return }
                updateLayout(scrollView: scrollView)
            }
            
            func updateLayout(scrollView: NSScrollView) {
                guard let imageView = scrollView.documentView as? NSImageView,
                      let image = imageView.image else { return }
                
                let containerSize = scrollView.frame.size
                guard containerSize.width > 0, containerSize.height > 0 else { return }
                
                // Only update frame if we are at min magnification (1.0) to refit
                if scrollView.magnification == 1.0 {
                     let widthRatio = containerSize.width / image.size.width
                    let heightRatio = containerSize.height / image.size.height
                    let scale = min(widthRatio, heightRatio)
                    
                    let scaledWidth = image.size.width * scale
                    let scaledHeight = image.size.height * scale
                    
                    imageView.frame = CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight)
                }
            }
        }
    }

    // Custom ClipView to keep content centered when smaller than the scroll view
    class CenteredClipView: NSClipView {
        override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
            var rect = super.constrainBoundsRect(proposedBounds)
            guard let documentView = self.documentView else { return rect }

            // Use rect.width/height which corresponds to the visible bounds in document coordinates
            // This correctly accounts for magnification (zoom)
            
            if documentView.frame.width < rect.width {
                rect.origin.x = (documentView.frame.width - rect.width) / 2.0
            }

            if documentView.frame.height < rect.height {
                rect.origin.y = (documentView.frame.height - rect.height) / 2.0
            }

            return rect
        }
    }
#endif
