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
        // Track if we're processing imports (show progress UI instead of black screen)
        @State private var isProcessing: Bool = false
        @State private var processedCount: Int = 0
        @State private var totalCount: Int = 0

        var body: some View {
            // The PHPickerViewController will be presented immediately by the
            // UIKit wrapper below. Keep a slim SwiftUI backing so we can show a
            // helpful message if the picker cannot be shown for any reason.
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()
                if showPicker && !isProcessing {
                    PHPickerWrapper { results in
                        Task { @MainActor in
                            await handle(results: results)
                        }
                    }
                    .ignoresSafeArea()
                } else if isProcessing {
                    // Show progress UI while processing imports
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Importing photos…")
                            .font(.headline)
                        if totalCount > 0 {
                            Text("\(processedCount) of \(totalCount)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
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

            // Show progress UI while processing
            isProcessing = true
            totalCount = results.count
            processedCount = 0

            // Iterate through results and import each item. Use sequential
            // processing to keep resource usage predictable and maintain ordering.
            for result in results {
                // Prefer file representation (works for video and image files)
                let provider = result.itemProvider

                // Determine suggested filename if the provider gives a suggested name
                var suggestedFilename: String? = nil
                if let id = result.assetIdentifier,
                    let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
                {
                    // Try to extract a reasonable filename from the creation date and identifier
                    let ts = Int(asset.creationDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970)
                    suggestedFilename = "photo_\(ts).jpg"
                }

                // Try file representation first
                if let typeIdentifier = provider.registeredTypeIdentifiers.first {
                    do {
                        let tmpURL = try await withCheckedThrowingContinuation {
                            (cont: CheckedContinuation<URL, Error>) in
                            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                                if let url = url {
                                    cont.resume(returning: url)
                                } else if let error = error {
                                    cont.resume(throwing: error)
                                } else {
                                    cont.resume(throwing: NSError(domain: "Picker", code: -1, userInfo: nil))
                                }
                            }
                        }

                        // Copy to a temp location we control — the provider URL's lifetime is uncertain
                        let fm = FileManager.default
                        let dest = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
                            UUID().uuidString
                        ).appendingPathExtension(tmpURL.pathExtension)
                        try fm.copyItem(at: tmpURL, to: dest)

                        // Map UTType to media type
                        let mediaType: MediaType = (typeIdentifier.contains("video")) ? .video : .photo
                        let filename = suggestedFilename ?? dest.lastPathComponent

                        try await albumManager.hidePhotoSource(
                            mediaSource: .fileURL(dest), filename: filename, assetIdentifier: nil, mediaType: mediaType)
                        // Clean up temporary file after hidePhotoSource completes (AlbumManager may copy into place)
                        try? fm.removeItem(at: dest)
                    } catch {
                        AppLog.error(
                            "PhotosLibraryPicker: failed to import file representation: \(error.localizedDescription)")
                        // Try fallback below
                        await tryLoadImageFallback(provider: provider)
                    }
                } else {
                    await tryLoadImageFallback(provider: provider)
                }

                processedCount += 1
            }

            dismiss()
        }

        private func tryLoadImageFallback(provider: NSItemProvider) async {
            if provider.canLoadObject(ofClass: UIImage.self) {
                do {
                    let image = try await withCheckedThrowingContinuation {
                        (cont: CheckedContinuation<UIImage, Error>) in
                        provider.loadObject(ofClass: UIImage.self) { obj, error in
                            if let img = obj as? UIImage {
                                cont.resume(returning: img)
                            } else if let err = error {
                                cont.resume(throwing: err)
                            } else {
                                cont.resume(throwing: NSError(domain: "Picker", code: -1, userInfo: nil))
                            }
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
                config.selectionLimit = 0  // allow multiple
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
    // macOS implementation: Show albums from Photos library and let user select items
    import AppKit
    import PhotosUI
    
    struct PhotosLibraryPicker: View {
        @EnvironmentObject var albumManager: AlbumManager
        @Environment(\.dismiss) private var dismiss
        
        @State private var albums: [(name: String, collection: PHAssetCollection)] = []
        @State private var selectedAlbum: PHAssetCollection?
        @State private var assets: [PHAsset] = []
        @State private var selectedAssets: Set<String> = []
        @State private var isLoading = false
        @State private var isImporting = false
        @State private var importProgress: Int = 0
        @State private var importTotal: Int = 0
        @State private var accessGranted = false
        @State private var thumbnails: [String: NSImage] = [:]
        
        private let photosService = PhotosLibraryService.shared
        
        var body: some View {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Import from Photos Library")
                        .font(.headline)
                    Spacer()
                    
                    if !selectedAssets.isEmpty {
                        Text("\(selectedAssets.count) selected")
                            .foregroundStyle(.secondary)
                    }
                    
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Import \(selectedAssets.count > 0 ? "(\(selectedAssets.count))" : "")") {
                        Task { await importSelectedAssets() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedAssets.isEmpty || isImporting)
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
                
                Divider()
                
                if !accessGranted {
                    // Request access view
                    VStack(spacing: 16) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Photos Access Required")
                            .font(.headline)
                        Text("Grant access to import photos from your library.")
                            .foregroundStyle(.secondary)
                        Button("Grant Access") {
                            requestAccess()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isImporting {
                    // Import progress view
                    VStack(spacing: 16) {
                        ProgressView(value: Double(importProgress), total: Double(importTotal))
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                        Text("Importing \(importProgress) of \(importTotal)...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HSplitView {
                        // Albums list
                        List(albums, id: \.collection.localIdentifier, selection: Binding(
                            get: { selectedAlbum?.localIdentifier },
                            set: { newId in
                                selectedAlbum = albums.first { $0.collection.localIdentifier == newId }?.collection
                                if let album = selectedAlbum {
                                    loadAssets(from: album)
                                }
                            }
                        )) { album in
                            HStack {
                                Image(systemName: albumIcon(for: album.collection))
                                    .foregroundStyle(.secondary)
                                Text(album.name)
                                Spacer()
                            }
                            .tag(album.collection.localIdentifier)
                        }
                        .listStyle(.sidebar)
                        .frame(minWidth: 180, maxWidth: 250)
                        
                        // Assets grid
                        if isLoading {
                            ProgressView("Loading...")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if assets.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "photo.stack")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.secondary)
                                Text(selectedAlbum == nil ? "Select an album" : "No photos in this album")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 8)], spacing: 8) {
                                    ForEach(assets, id: \.localIdentifier) { asset in
                                        assetThumbnail(asset)
                                            .onTapGesture {
                                                toggleSelection(asset)
                                            }
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 700, minHeight: 500)
            .onAppear {
                requestAccess()
            }
        }
        
        private func albumIcon(for collection: PHAssetCollection) -> String {
            switch collection.assetCollectionSubtype {
            case .smartAlbumAllHidden:
                return "eye.slash"
            case .smartAlbumFavorites:
                return "heart.fill"
            case .smartAlbumVideos:
                return "video"
            case .smartAlbumScreenshots:
                return "camera.viewfinder"
            case .smartAlbumSelfPortraits:
                return "person.crop.square"
            case .smartAlbumRecentlyAdded:
                return "clock"
            case .albumCloudShared:
                return "person.2"
            default:
                return "photo.on.rectangle"
            }
        }
        
        @ViewBuilder
        private func assetThumbnail(_ asset: PHAsset) -> some View {
            let isSelected = selectedAssets.contains(asset.localIdentifier)
            
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let thumbnail = thumbnails[asset.localIdentifier] {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay {
                                ProgressView()
                                    .scaleEffect(0.5)
                            }
                            .onAppear {
                                loadThumbnail(for: asset)
                            }
                    }
                }
                .frame(width: 100, height: 100)
                .clipped()
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                )
                
                // Selection checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, Color.accentColor)
                        .font(.system(size: 20))
                        .padding(4)
                }
                
                // Video duration badge
                if asset.mediaType == .video {
                    HStack(spacing: 2) {
                        Image(systemName: "video.fill")
                            .font(.caption2)
                        Text(formatDuration(asset.duration))
                            .font(.caption2)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial)
                    .cornerRadius(4)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        
        private func formatDuration(_ duration: TimeInterval) -> String {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
        
        private func toggleSelection(_ asset: PHAsset) {
            if selectedAssets.contains(asset.localIdentifier) {
                selectedAssets.remove(asset.localIdentifier)
            } else {
                selectedAssets.insert(asset.localIdentifier)
            }
        }
        
        private func requestAccess() {
            photosService.requestAccess { granted in
                accessGranted = granted
                if granted {
                    loadAlbums()
                }
            }
        }
        
        private func loadAlbums() {
            albums = photosService.getAllAlbums(libraryType: .both)
            
            // Auto-select first album
            if let first = albums.first {
                selectedAlbum = first.collection
                loadAssets(from: first.collection)
            }
        }
        
        private func loadAssets(from collection: PHAssetCollection) {
            isLoading = true
            selectedAssets.removeAll()
            thumbnails.removeAll()
            
            DispatchQueue.global(qos: .userInitiated).async {
                let fetchedAssets = photosService.getAssets(from: collection)
                DispatchQueue.main.async {
                    assets = fetchedAssets
                    isLoading = false
                }
            }
        }
        
        private func loadThumbnail(for asset: PHAsset) {
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 200, height: 200),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                if let image = image {
                    DispatchQueue.main.async {
                        thumbnails[asset.localIdentifier] = image
                    }
                }
            }
        }
        
        private func importSelectedAssets() async {
            let assetsToImport = assets.filter { selectedAssets.contains($0.localIdentifier) }
            guard !assetsToImport.isEmpty else { return }
            
            isImporting = true
            importTotal = assetsToImport.count
            importProgress = 0
            
            for asset in assetsToImport {
                do {
                    if let result = await photosService.getMediaDataAsync(for: asset) {
                        if let fileURL = result.fileURL {
                            // File-based import
                            try await albumManager.hidePhotoSource(
                                mediaSource: .fileURL(fileURL),
                                filename: result.filename,
                                assetIdentifier: asset.localIdentifier,
                                mediaType: result.mediaType
                            )
                            // Clean up temp file
                            if result.shouldDeleteFileWhenFinished {
                                try? FileManager.default.removeItem(at: fileURL)
                            }
                        } else if let data = result.data {
                            // Data-based import
                            try await albumManager.hidePhotoData(data, filename: result.filename)
                        }
                    }
                } catch {
                    AppLog.error("Failed to import asset \(asset.localIdentifier): \(error.localizedDescription)")
                }
                
                importProgress += 1
            }
            
            dismiss()
        }
    }
#endif

// Small app icon helper used by a few lightweight preview/header locations.
// small app icon helper removed (tiny icons are no longer shown in headers/toolbars)
