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

/// Abstraction over platform icon application so tests can simulate failures/successes
public protocol IconApplier: AnyObject {
    /// Request the platform to apply the given alternate icon name.
    /// The completion must be called with nil on success or an Error on failure.
    func apply(iconName: String?, completion: @escaping (Error?) -> Void)
}

#if os(iOS)
/// Default production applier for iOS that calls UIApplication.setAlternateIconName
/// Ensure this is invoked on the main thread: UIApplication APIs expect main-thread usage
final class DefaultIconApplier: IconApplier {
    func apply(iconName: String?, completion: @escaping (Error?) -> Void) {
        if Thread.isMainThread {
            UIApplication.shared.setAlternateIconName(iconName, completionHandler: completion)
        } else {
            DispatchQueue.main.async {
                UIApplication.shared.setAlternateIconName(iconName, completionHandler: completion)
            }
        }
    }
}
#else
/// Default applier stub for non-iOS platforms (macOS) — performs local behavior synchronously.
final class DefaultIconApplier: IconApplier {
    func apply(iconName: String?, completion: @escaping (Error?) -> Void) {
        // macOS runtime path manages the Dock icon directly; treat as success here.
        completion(nil)
    }
}
#endif

/// Manages runtime switching of the app icon (best-effort) and exposes available icon names
final class AppIconService: ObservableObject {
    static let shared = AppIconService()

    /// Known icon asset names discovered in the asset catalog.
    /// Trimmed down to the canonical runtime candidates. The special name
    /// "AppIconMarketingRuntime" maps to a dedicated 512@2x rounded asset
    /// (preferred) so previews and marketing renderings are consistent.
    // Available icon names — computed at runtime from Info.plist and the asset catalog.
    // This avoids offering an icon name the OS cannot actually apply which would
    // otherwise fail silently (or return a transient error).
    var availableIcons: [String] {
        #if os(iOS)
        // Gather keys declared in Info.plist under CFBundleIcons->CFBundleAlternateIcons
        var names = [String]()
        if let plist = Bundle.main.infoDictionary,
           let bundleIcons = plist["CFBundleIcons"] as? [String: Any],
           let alternates = bundleIcons["CFBundleAlternateIcons"] as? [String: Any] {
            // alternates keys are the names used with UIApplication.setAlternateIconName
            names.append(contentsOf: alternates.keys)
        }

        // Always include the default primary name "AppIcon"
        names.append("AppIcon")

        // Deduplicate and keep a stable ordering (prefer declared order then default)
        var unique: [String] = []
        for n in names where !unique.contains(n) { unique.append(n) }

        // Filter to only those that we can reasonably render at runtime
        return unique.filter { Self.isIconUsable(iconName: $0) }
        #else
        // On macOS keep the same known list for previews
        return [
            "AppIcon", // default
            "AppIcon 1",
            "AppIcon 2",
            "AppIcon 3",
            "AppIcon 4",
            "AppIcon 5",
            "AppIcon 6",
            "AppIcon 7",
            "AppIcon 8",
            "AppIcon 9",
            "AppIcon 10",
            "AppIcon 11",
            "AppIcon 12",
            "AppIcon 13",
            "AppIcon 14",
            "AppIcon 15"
        ]
        #endif
    }

    // AppStorage does not support optional types directly, so store as a non-optional
    // string and treat the empty string as "no selection".
    @AppStorage("selectedAppIconName") public var selectedIconName: String = "" {
        didSet { applySelectedIcon() }
    }

    // Generated marketing icon (1024x1024) derived from the selected icon set for runtime previews
    @Published public private(set) var runtimeMarketingImage: PlatformImage? = nil

    private let iconApplier: IconApplier

    /// Designated initializer — production use will default to DefaultIconApplier.
    // Bump default attempts to make transient platform errors less visible to users —
    // retries are cheap and reduce the likelihood of the UI showing "Resource temporarily unavailable".
    init(iconApplier: IconApplier = DefaultIconApplier()) {
        self.iconApplier = iconApplier
        // Try to sync persisted value with the current system state at startup.
        // Important: don't blindly re-apply the stored value — that could reset a
        // user-chosen alternate icon set from a previous run. Instead, if there is
        // a system-set alternate icon (UIApplication.alternateIconName) and our
        // stored `selectedIconName` is empty, adopt the system value so the UI
        // shows the icon that is actually active. Otherwise, apply the stored value.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
#if os(iOS)
            if UIApplication.shared.supportsAlternateIcons {
                // If system currently has an alternate icon set and our persisted value
                // is empty, sync to system without re-applying (avoid a reset).
                if let current = UIApplication.shared.alternateIconName, !current.isEmpty {
                    if self.selectedIconName.isEmpty {
                        // Adopt the system's alternate icon into our AppStorage so UI reflects reality.
                        self.selectedIconName = current
                        self.runtimeMarketingImage = Self.generateMarketingImage(from: current)
                        return
                    }
                }
            }
#endif
            self.applySelectedIcon()
        }
    }

    /// Convenience initializer used by tests to inject a test applier and custom retry/backoff parameters.
    convenience init(testApplier: IconApplier) {
        self.init(iconApplier: testApplier)
    }

    func applySelectedIcon() {
        let name = selectedIconName
        // If nothing was chosen by the UI, prefer the system state (e.g. alternate icon
        // set by the OS or a previous run). If the system has an alternate name and
        // we don't have a persisted one, don't overwrite it — instead reflect it.
#if os(iOS)
        if name.isEmpty {
            if UIApplication.shared.supportsAlternateIcons,
               let current = UIApplication.shared.alternateIconName,
               !current.isEmpty {
                // System already uses an alternate; sync runtime image and avoid calling setAlternateIconName
                runtimeMarketingImage = Self.generateMarketingImage(from: current)
                return
            } else {
                // No selection and no system alternate -> ensure primary icon shown
                setSystemIcon(nil)
                return
            }
        }
#else
        if name.isEmpty {
            setSystemIcon(nil)
            return
        }
#endif
        // Validate the requested icon against the allowed set so we never pass arbitrary
        // strings to the platform API (defense-in-depth).
        if name.isEmpty == false {
            let candidate = name
            if !availableIcons.contains(candidate) {
                AppLog.debugPrivate("AppIconService: prevented attempt to set unknown icon name \(candidate)")
                DispatchQueue.main.async { self.lastIconApplyError = "Unknown icon: \(candidate)" }
                return
            }
        }

        // Generate a runtime 1024 image and store it for preview purposes
        runtimeMarketingImage = Self.generateMarketingImage(from: name)
        setSystemIcon(name)
    }

    /// Last error seen when attempting to apply an alternate icon. Useful for
    /// surfacing UI feedback when the OS reports a failure.
    @Published public private(set) var lastIconApplyError: String? = nil

    /// Clear any last reported icon apply error. Public so UI code can reset the alert.
    public func clearLastIconApplyError() { lastIconApplyError = nil }


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

        // Directly invoke the applier once (no retry/backoff).
        iconApplier.apply(iconName: iconNameToSet) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                AppLog.debugPrivate("AppIconService: failed to set alternate icon \(iconNameToSet ?? "<primary>"): \(error.localizedDescription)")
                DispatchQueue.main.async { self.lastIconApplyError = error.localizedDescription }
            } else {
                AppLog.debugPrivate("AppIconService: set alternate icon \(iconNameToSet ?? "<primary>")")
                DispatchQueue.main.async { self.lastIconApplyError = nil }
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

#if os(iOS)
    // No retry/backoff; single-shot apply path. Tests can inject an IconApplier to
    // simulate platform success/failure.
#endif

    /// Returns whether we can reasonably render / find an icon for preview/apply
    static func isIconUsable(iconName: String?) -> Bool {
#if os(iOS)
        let nameToTest = (iconName == nil || iconName == "AppIcon") ? "AppIcon" : iconName!

        // Try common methods: UIImage(named:) and our marketing renderer
        if UIImage(named: nameToTest) != nil { return true }
        if generateMarketingImage(from: nameToTest) != nil { return true }
        return false
#else
        // On macOS prefer to check NSImage(named:)
        let nameToTest = (iconName == nil || iconName == "AppIcon") ? "AppIcon" : iconName!
        return NSImage(named: NSImage.Name(nameToTest)) != nil
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
