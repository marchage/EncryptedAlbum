import SwiftUI
import AVKit

#if os(macOS)
    import AppKit
#endif
#if os(iOS)
    import UIKit
#endif

// Custom Video Player View
#if os(macOS)
    struct CustomVideoPlayer: NSViewRepresentable {
        let url: URL

        func makeNSView(context: Context) -> AVPlayerView {
            let playerView = AVPlayerView()
            playerView.player = AVPlayer(url: url)
            playerView.controlsStyle = .floating
            playerView.showsFullScreenToggleButton = true
            return playerView
        }

        func updateNSView(_ nsView: AVPlayerView, context: Context) {
            // Update if needed
        }
    }
#else
    struct CustomVideoPlayer: UIViewControllerRepresentable {
        let url: URL

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let playerViewController = AVPlayerViewController()
            playerViewController.player = AVPlayer(url: url)
            return playerViewController
        }

        func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
            // Update if needed
        }
    }
#endif
