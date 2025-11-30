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

// MARK: - AppIconService

/// Manages runtime switching of the app icon (best-effort) and exposes available icon names
final class AppIconService: ObservableObject {
    static let shared = AppIconService()

    /// Known icon asset names discovered in the asset catalog.
    /// Trimmed down to the canonical runtime candidates. The special name
    /// "AppIconMarketingRuntime" maps to a dedicated 512@2x rounded asset
    /// (preferred) so previews and marketing renderings are consistent.
    let availableIcons: [String] = [
        "AppIcon", // default
        "AppIcon 4",
        "AppIcon 5",
        "AppIcon 6",
        "AppIcon 8",
        "AppIcon 11",
        "AppIcon 12",
        "AppIcon 13",
        "AppIcon 14",
        "AppIconMarketingRuntime"
    ]

    // AppStorage does not support optional types directly, so store as a non-optional
    // string and treat the empty string as "no selection".
    @AppStorage("selectedAppIconName") public var selectedIconName: String = "" {
        didSet { applySelectedIcon() }
    }

    // Generated marketing icon (1024x1024) derived from the selected icon set for runtime previews
    @Published public private(set) var runtimeMarketingImage: PlatformImage? = nil

    private init() {
        // Try to apply persisted value at startup
        DispatchQueue.main.async { [weak self] in self?.applySelectedIcon() }
    }

    func applySelectedIcon() {
        let name = selectedIconName
        guard !name.isEmpty else {
            setSystemIcon(nil)
            return
        }
        // Generate a runtime 1024 image and store it for preview purposes
        runtimeMarketingImage = Self.generateMarketingImage(from: name)
        setSystemIcon(name)
    }

    /// Return easy display names for UI
    func displayName(for iconName: String) -> String {
        if iconName == "AppIcon" { return "Default" }
        return iconName
    }

    // MARK: - Platform runtime icon switch

    private func setSystemIcon(_ name: String?) {
#if os(iOS)
        // UIApplication alternate icons must be declared in Info.plist (CFBundleAlternateIcons).
        // Attempt to set alternate icon if available. If not available (no entry in Info.plist) it will fail silently.
        guard UIApplication.shared.supportsAlternateIcons else { return }

        // The default primary icon is represented by nil
        let iconNameToSet = (name == nil || name == "AppIcon") ? nil : name

        UIApplication.shared.setAlternateIconName(iconNameToSet) { error in
            if let error = error {
                AppLog.debugPrivate("AppIconService: failed to set alternate icon \(iconNameToSet ?? "<primary>"): \(error.localizedDescription)")
            } else {
                AppLog.debugPrivate("AppIconService: set alternate icon \(iconNameToSet ?? "<primary>")")
            }
        }
#elseif os(macOS)
        // On macOS we can update the Dock icon at runtime using NSApplication
        if let name = name, name != "AppIcon" {
            if let image = NSImage(named: NSImage.Name(name)) {
                NSApplication.shared.applicationIconImage = image
            }
        } else {
            // Reset to default image in assets
            if let defaultImage = NSImage(named: NSImage.Name("AppIcon")) {
                NSApplication.shared.applicationIconImage = defaultImage
            }
        }
#endif
    }

    /// Programmatic helper to set icon from UI controls
    public func select(iconName: String?) {
        selectedIconName = iconName ?? ""
    }

    // MARK: - Image generation helpers

    /// Creates a 1024x1024 image for the given icon asset name by rendering the best available representation.
    /// This is used for previews and the macOS dock image — it does not alter the app bundle.
    static func generateMarketingImage(from iconName: String?) -> PlatformImage? {
        #if os(macOS)
        // Prefer the dedicated 512@2x runtime marketing asset when requested.
        let marketingCandidates = [
            "AppIcon-512@2x", "AppIcon512@2x", "AppIcon-512", "AppIcon512",
            "AppIcon_marketing", "AppIconMarketingRuntime", "AppIcon"
        ]

        let nameToLoad: String
        if iconName == nil || iconName == "AppIcon" {
            nameToLoad = "AppIcon"
        } else if iconName == "AppIconMarketingRuntime" {
            nameToLoad = marketingCandidates.first(where: { NSImage(named: NSImage.Name($0)) != nil }) ?? iconName!
        } else {
            nameToLoad = iconName!
        }

        guard let img = NSImage(named: NSImage.Name(nameToLoad)) else { return nil }

        // Render a 1024x1024 representation with rounded corners
        let size = NSSize(width: 1024, height: 1024)
        let target = NSImage(size: size)
        target.lockFocus()
        defer { target.unlockFocus() }

        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            let rect = CGRect(origin: .zero, size: CGSize(width: 1024, height: 1024))
            let corner = CGFloat(0.15 * 1024)
            let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
            ctx.addPath(path)
            ctx.clip()
            img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            ctx.restoreGState()
        } else {
            // Fallback: draw normally
            let rect = NSRect(origin: .zero, size: size)
            img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        return target
        #else
        // Prefer the dedicated 512@2x runtime marketing asset when requested.
        let marketingCandidates = [
            "AppIcon-512@2x", "AppIcon512@2x", "AppIcon-512", "AppIcon512",
            "AppIcon_marketing", "AppIconMarketingRuntime", "AppIcon"
        ]

        // Resolve which asset name to use for rendering.
        let nameToLoad: String
        if iconName == nil || iconName == "AppIcon" {
            nameToLoad = "AppIcon"
        } else if iconName == "AppIconMarketingRuntime" {
            // Try to find the preferred 512@2x candidate first, fall back to the provided icon name
            nameToLoad = marketingCandidates.first(where: { UIImage(named: $0) != nil }) ?? iconName!
        } else {
            nameToLoad = iconName!
        }

        guard let ui = UIImage(named: nameToLoad) ?? UIImage(named: "AppIcon") else { return nil }

        // Always render a 1024x1024 marketing image with rounded corners for a consistent look.
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024))
        let out = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: CGSize(width: 1024, height: 1024))
            // Rounded corners — chosen to match marketing corner radii (approx 15% of size)
            let corner = CGFloat(0.15 * 1024)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: corner)
            path.addClip()
            ui.draw(in: rect)
        }
        return out
        #endif
    }
}
