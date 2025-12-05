import Foundation

#if os(macOS)
import AppKit

/// Service to show progress in the macOS Dock icon.
/// Shows a progress bar overlay on the app's Dock tile during long-running operations.
@MainActor
class DockProgressService: ObservableObject {
    static let shared = DockProgressService()
    
    private var progressView: DockProgressView?
    private var isShowing = false
    
    private init() {}
    
    /// Show progress bar on the Dock icon
    /// - Parameter progress: Value from 0.0 to 1.0
    func showProgress(_ progress: Double) {
        print("[DockProgress] showProgress called with \(Int(progress * 100))%, isShowing=\(isShowing)")
        guard !isShowing else {
            // Already showing, just update
            progressView?.progress = progress
            NSApp.dockTile.display()
            return
        }
        
        isShowing = true
        
        // Create the progress view
        let view = DockProgressView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        view.progress = progress
        progressView = view
        
        // Set as dock tile content view
        print("[DockProgress] Setting dockTile.contentView")
        NSApp.dockTile.contentView = view
        NSApp.dockTile.display()
    }
    
    /// Update the progress value (0.0 to 1.0)
    func updateProgress(_ progress: Double) {
        guard isShowing else {
            showProgress(progress)
            return
        }
        print("[DockProgress] Updating to \(Int(progress * 100))%")
        progressView?.progress = min(max(progress, 0), 1)
        NSApp.dockTile.display()
    }
    
    /// Hide the progress bar and restore normal Dock icon
    func hideProgress() {
        guard isShowing else { return }
        
        print("[DockProgress] Hiding")
        isShowing = false
        progressView = nil
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.display()
    }
}

/// Custom NSView that draws a progress bar over the app icon
private class DockProgressView: NSView {
    var progress: Double = 0 {
        didSet {
            needsDisplay = true
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw the app icon first
        if let appIcon = NSApp.applicationIconImage {
            appIcon.draw(in: bounds)
        }
        
        // Progress bar dimensions
        let barHeight: CGFloat = 12
        let barInset: CGFloat = 8
        let barY: CGFloat = 10  // Distance from bottom
        let cornerRadius: CGFloat = 4
        
        let barRect = NSRect(
            x: barInset,
            y: barY,
            width: bounds.width - (barInset * 2),
            height: barHeight
        )
        
        // Draw background track (dark with slight transparency)
        let trackPath = NSBezierPath(roundedRect: barRect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.black.withAlphaComponent(0.6).setFill()
        trackPath.fill()
        
        // Draw border
        NSColor.white.withAlphaComponent(0.3).setStroke()
        trackPath.lineWidth = 1
        trackPath.stroke()
        
        // Draw progress fill
        if progress > 0 {
            let fillWidth = (barRect.width - 2) * CGFloat(progress)
            let fillRect = NSRect(
                x: barRect.origin.x + 1,
                y: barRect.origin.y + 1,
                width: max(fillWidth, 0),
                height: barRect.height - 2
            )
            
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: cornerRadius - 1, yRadius: cornerRadius - 1)
            
            // Green gradient for progress
            let gradient = NSGradient(colors: [
                NSColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1.0),
                NSColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 1.0)
            ])
            gradient?.draw(in: fillPath, angle: 90)
        }
    }
}

#else
// iOS stub - no dock on iOS
@MainActor
class DockProgressService: ObservableObject {
    static let shared = DockProgressService()
    private init() {}
    
    func showProgress(_ progress: Double) {}
    func updateProgress(_ progress: Double) {}
    func hideProgress() {}
}
#endif
