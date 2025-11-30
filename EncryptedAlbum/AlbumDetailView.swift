import SwiftUI

/// Album detail view (placeholder)
///
/// This file previously contained an accidental duplicate `CryptoService` definition.
/// Replace the contents with a lightweight, safe SwiftUI album detail view so the
/// project compiles and UI code can continue without exposing duplicate crypto symbols.

struct AlbumDetailView: View {
    // Keep the view minimal here — the full UI is implemented elsewhere, but tests
    // and the app need this file to be a valid SwiftUI view.
    var body: some View {
        VStack(spacing: 12) {
            // Header: title on the left, small app icon on the right
            HStack(alignment: .center, spacing: 8) {
                Text("Album")
                    .font(.title)
                    .bold()

                Spacer()

                appIconSmallView()
            }

            Text("Details are shown here in the real app.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .accessibilityIdentifier("AlbumDetailView")
    }
}

#if DEBUG
struct AlbumDetailView_Previews: PreviewProvider {
    static var previews: some View {
        AlbumDetailView()
    }
}
#endif

/// Minimal stub for the Photos library picker used by `MainAlbumView`.
/// The real picker implementation may live in a platform-specific file; this
/// lightweight placeholder keeps the build green for unit tests.
struct PhotosLibraryPicker: View {
    var body: some View { EmptyView() }
}

// Small app icon helper used by a few lightweight preview/header locations.
fileprivate enum AppIconVariant {
    /// Slightly larger (28x28) rounded rect — previously used.
    case small
    /// Very subtle, tiny square (20x20) with low opacity and no shadow.
    case tiny
    /// Tiny circular icon for an even lighter footprint.
    case tinyCircle
}

fileprivate func appIconSmallView(_ style: AppIconVariant = .tiny) -> AnyView {
    // helper to wrap the image in the selected style
    func wrapImage(_ image: Image, size: CGFloat, cornerRadius: CGFloat?, opacity: Double, circular: Bool) -> AnyView {
        let view = image
        let shaped = view
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)

        if circular {
            return AnyView(shaped
                .clipShape(Circle())
                .opacity(opacity))
        }

        return AnyView(shaped
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? (size * 0.2)))
            .opacity(opacity))
    }

    #if os(macOS)
    if let nsimg = NSImage(named: "AppIcon") {
        let img = Image(nsImage: nsimg)
        switch style {
        case .small:
            return wrapImage(img, size: 28, cornerRadius: 6, opacity: 1.0, circular: false)
        case .tiny:
            return wrapImage(img, size: 20, cornerRadius: 4, opacity: 0.8, circular: false)
        case .tinyCircle:
            return wrapImage(img, size: 18, cornerRadius: nil, opacity: 0.8, circular: true)
        }
    }
    return AnyView(EmptyView())
    #else
    // Try a few runtime names commonly used in the app (see UnlockView)
    let attemptNames = ["AppIconMarketingRuntime", "AppIcon", "app-icon~ios-marketing"]
    let uiImg = attemptNames.compactMap { UIImage(named: $0) }.first

    if let uiImg = uiImg {
        let img = Image(uiImage: uiImg)
        switch style {
        case .small:
            return wrapImage(img, size: 28, cornerRadius: 6, opacity: 1.0, circular: false)
        case .tiny:
            return wrapImage(img, size: 20, cornerRadius: 4, opacity: 0.8, circular: false)
        case .tinyCircle:
            return wrapImage(img, size: 18, cornerRadius: nil, opacity: 0.8, circular: true)
        }
    }

    // No app icon available at runtime; leave empty so header doesn't break layout.
    return AnyView(EmptyView())
    #endif
}
