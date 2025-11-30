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

// Minimal stub for the Photos library picker used by `MainAlbumView`.
/// The real picker implementation may live in a platform-specific file; this
/// lightweight placeholder keeps the build green for unit tests.

#if os(iOS)
import PhotosUI

/// Lightweight Photos picker — on iOS we use the system PHPicker to present a
/// safe, familiar selection UI and forward picked items to `AlbumManager` for
/// import/hiding. On other platforms the existing placeholder remains.
struct PhotosLibraryPicker: View {
    @EnvironmentObject var albumManager: AlbumManager
    @Environment(\.dismiss) private var dismiss

    // Keep picker presented immediately when this view appears
    @State private var showPicker: Bool = true

    var body: some View {
        // The PHPickerViewController will be presented immediately by the
        // UIKit wrapper below. Keep a slim SwiftUI backing so we can show a
        // helpful message if the picker cannot be shown for any reason.
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            if showPicker {
                PHPickerWrapper { results in
                    Task { @MainActor in
                        await handle(results: results)
                    }
                }
                .ignoresSafeArea()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No picker available")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { showPicker = true }
    }

    /// Process PHPicker results: for each result, attempt to import a file
    /// representation or UIImage and hand it to AlbumManager for hiding.
    private func handle(results: [PHPickerResult]) async {
        guard !results.isEmpty else {
            dismiss()
            return
        }

        // Iterate through results and import each item. Use sequential
        // processing to keep resource usage predictable and maintain ordering.
        for result in results {
            // Prefer file representation (works for video and image files)
            let provider = result.itemProvider

            // Determine suggested filename if the provider gives a suggested name
            var suggestedFilename: String? = nil
            if let id = result.assetIdentifier, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject {
                // Try to extract a reasonable filename from the creation date and identifier
                let ts = Int(asset.creationDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970)
                suggestedFilename = "photo_\(ts).jpg"
            }

            // Try file representation first
            if let typeIdentifier = provider.registeredTypeIdentifiers.first {
                do {
                    let tmpURL = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                            if let url = url { cont.resume(returning: url) }
                            else if let error = error { cont.resume(throwing: error) }
                            else { cont.resume(throwing: NSError(domain: "Picker", code: -1, userInfo: nil)) }
                        }
                    }

                    // Copy to a temp location we control — the provider URL's lifetime is uncertain
                    let fm = FileManager.default
                    let dest = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension(tmpURL.pathExtension)
                    try fm.copyItem(at: tmpURL, to: dest)

                    // Map UTType to media type
                    let mediaType: MediaType = (typeIdentifier.contains("video")) ? .video : .photo
                    let filename = suggestedFilename ?? dest.lastPathComponent

                    try await albumManager.hidePhotoSource(mediaSource: .fileURL(dest), filename: filename, assetIdentifier: nil, mediaType: mediaType)
                    // Clean up temporary file after hidePhotoSource completes (AlbumManager may copy into place)
                    try? fm.removeItem(at: dest)
                } catch {
                    AppLog.error("PhotosLibraryPicker: failed to import file representation: \(error.localizedDescription)")
                    // Try fallback below
                    await tryLoadImageFallback(provider: provider)
                }
            } else {
                await tryLoadImageFallback(provider: provider)
            }
        }

        dismiss()
    }

    private func tryLoadImageFallback(provider: NSItemProvider) async {
        if provider.canLoadObject(ofClass: UIImage.self) {
            do {
                let image = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UIImage, Error>) in
                    provider.loadObject(ofClass: UIImage.self) { obj, error in
                        if let img = obj as? UIImage { cont.resume(returning: img) }
                        else if let err = error { cont.resume(throwing: err) }
                        else { cont.resume(throwing: NSError(domain: "Picker", code: -1, userInfo: nil)) }
                    }
                }

                // Convert to JPEG and hand off to album manager
                if let jpegData = image.jpegData(compressionQuality: 0.9) {
                    let filename = "photo_\(Int(Date().timeIntervalSince1970)).jpg"
                    try await albumManager.hidePhotoData(jpegData, filename: filename)
                }
            } catch {
                AppLog.error("PhotosLibraryPicker: image fallback failed: \(error.localizedDescription)")
            }
        }
    }
}

// UIKit wrapper for PHPickerViewController — present the picker modally from a
// simple container view controller. Embedding PHPicker directly as the
// representable's root controller sometimes produces layout/presentation
// surprises when nested inside SwiftUI fullScreenCover; presenting it
// modally from a small container keeps platform expectations consistent.
private struct PHPickerWrapper: UIViewControllerRepresentable {
    var onFinish: ([PHPickerResult]) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let container = ContainerViewController()
        container.configure(onFinish: onFinish, coordinator: context.coordinator)
        return container
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // No dynamic updates required
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    // Small container that will present PHPicker modally as soon as it appears.
    private class ContainerViewController: UIViewController {
        private var hasPresented = false
        private var onFinish: (([PHPickerResult]) -> Void)?
        private weak var coordinator: Coordinator?

        func configure(onFinish: @escaping ([PHPickerResult]) -> Void, coordinator: Coordinator) {
            self.onFinish = onFinish
            self.coordinator = coordinator
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = UIColor.systemBackground
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // Present once
            guard !hasPresented else { return }
            hasPresented = true

            var config = PHPickerConfiguration(photoLibrary: PHPhotoLibrary.shared())
            config.selectionLimit = 0 // allow multiple
            config.filter = .any(of: [.images, .videos])

            let picker = PHPickerViewController(configuration: config)
            picker.delegate = coordinator
            picker.modalPresentationStyle = .automatic

            // Brief debug trace to help diagnose black/blank presentations
            AppLog.debugPrivate("PHPickerWrapper: presenting PHPicker (modal)")

            present(picker, animated: true)
        }
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onFinish: ([PHPickerResult]) -> Void

        init(onFinish: @escaping ([PHPickerResult]) -> Void) { self.onFinish = onFinish }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Dismiss the presented picker and call the finish callback.
            picker.dismiss(animated: true) {
                self.onFinish(results)
            }
        }
    }
}
#else
// macOS fallback: keep an informative placeholder so the app doesn't present a blank/black screen
struct PhotosLibraryPicker: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Photo library import is available on iOS only in this build.")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
    }
}
#endif

// Small app icon helper used by a few lightweight preview/header locations.
// small app icon helper removed (tiny icons are no longer shown in headers/toolbars)
