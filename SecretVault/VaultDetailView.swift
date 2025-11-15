import SwiftUI
import UniformTypeIdentifiers
import Photos
#if os(macOS)
import AppKit
#endif

struct PhotosLibraryPicker: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var vaultManager: VaultManager
    
    @State private var albums: [(name: String, collection: PHAssetCollection)] = []
    @State private var allPhotos: [(album: String, asset: PHAsset)] = []
    @State private var selectedAssets: Set<String> = []
    @State private var hasAccess = false
    @State private var importing = false
    @State private var selectedLibrary: LibraryType = .personal
    @State private var isLoading = false
    @State private var selectedAlbumFilter: String? = nil
    // Fallback: Force treat all albums as Shared Library when PhotoKit can't distinguish
    @State private var forceSharedLibrary = false
    
    var filteredPhotos: [(album: String, asset: PHAsset)] {
        if let filter = selectedAlbumFilter {
            return allPhotos.filter { $0.album == filter }
        }
        return allPhotos
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar with albums
            VStack(alignment: .leading, spacing: 0) {
                Text("Albums")
                    .font(.headline)
                    .padding()
                
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        // "All Items" option
                        Button {
                            selectedAlbumFilter = nil
                        } label: {
                            HStack {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .frame(width: 20)
                                Text("All Items")
                                Spacer()
                                Text("\(uniqueAllPhotosCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selectedAlbumFilter == nil ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        // Album list
                        ForEach(uniqueAlbums.sorted(), id: \.self) { album in
                            Button {
                                selectedAlbumFilter = album
                            } label: {
                                HStack {
                                    Image(systemName: albumIcon(for: album))
                                        .frame(width: 20)
                                    Text(album)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(albumPhotoCount(album))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedAlbumFilter == album ? Color.accentColor.opacity(0.2) : Color.clear)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
            }
            #if os(macOS)
            .frame(width: 220)
            #endif
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Main content area
        VStack(spacing: 0) {
            // Header with library selector
            #if os(iOS)
            VStack(alignment: .leading, spacing: 12) {
                // Title and main buttons
                HStack(spacing: 8) {
                    Text("Select Items to Hide")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    
                    Spacer()
                    
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.small)
                    .font(.subheadline)
                    
                    Button("Hide (\(selectedAssets.count))") {
                        hideSelectedPhotos()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .font(.subheadline)
                    .disabled(selectedAssets.isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
                
                // Library selector and options
                HStack(spacing: 12) {
                    // Compact library selector with icons
                    Picker("", selection: $selectedLibrary) {
                        Label("Personal", systemImage: "person.fill").tag(LibraryType.personal)
                        Label("Shared", systemImage: "person.2.fill").tag(LibraryType.shared)
                        Label("All", systemImage: "square.grid.2x2.fill").tag(LibraryType.both)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)
                    .onChange(of: selectedLibrary) { _ in
                        loadPhotos()
                    }
                    
                    // Manual fallback toggle only relevant when user selects Shared
                    if selectedLibrary == .shared {
                        Toggle("Force Shared", isOn: $forceSharedLibrary)
                            .toggleStyle(.switch)
                            .help("If your Shared Library photos are not detected (PhotoKit sourceType always = personal), enable this to treat all albums as shared.")
                            .onChange(of: forceSharedLibrary) { _ in
                                loadPhotos()
                            }
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            #else
            HStack {
                Text("Select Items to Hide")
                    .font(.headline)
                
                Spacer()
                
                // Compact library selector with icons
                Picker("", selection: $selectedLibrary) {
                    Label("Personal", systemImage: "person.fill").tag(LibraryType.personal)
                    Label("Shared", systemImage: "person.2.fill").tag(LibraryType.shared)
                    Label("All", systemImage: "square.grid.2x2.fill").tag(LibraryType.both)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                .onChange(of: selectedLibrary) { _ in
                    loadPhotos()
                }
                // Manual fallback toggle only relevant when user selects Shared
                Toggle("Force Shared", isOn: $forceSharedLibrary)
                    .toggleStyle(.switch)
                    .help("If your Shared Library photos are not detected (PhotoKit sourceType always = personal), enable this to treat all albums as shared.")
                    .onChange(of: forceSharedLibrary) { _ in
                        if selectedLibrary == .shared { loadPhotos() }
                    }
                    .padding(.leading, 8)
                    .frame(maxWidth: 130)
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Hide Selected (\(selectedAssets.count))") {
                    hideSelectedPhotos()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedAssets.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.ultraThinMaterial)
            #endif
            
            Divider()
            
            // Photos grid
            if isLoading {
                VStack {
                    ProgressView()
                    Text("Loading items...")
                        .foregroundStyle(.secondary)
                        .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if allPhotos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No items found")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                        ForEach(groupedPhotos, id: \.album) { group in
                            Section {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                                    ForEach(group.photos, id: \.asset.localIdentifier) { photo in
                                        PhotoAssetView(
                                            asset: photo.asset,
                                            isSelected: selectedAssets.contains(photo.asset.localIdentifier)
                                        )
                                        .onTapGesture {
                                            toggleSelection(photo.asset.localIdentifier)
                                        }
                                    }
                                }
                            } header: {
                                HStack {
                                    Text(group.album)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(group.photos.count) items")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    Button(action: {
                                        toggleAlbumSelection(group.photos.map { $0.asset.localIdentifier })
                                    }) {
                                        Text(isAlbumSelected(group.photos.map { $0.asset.localIdentifier }) ? "Deselect All" : "Select All")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 700)
        #endif
        .onAppear {
            requestPhotosAccess()
        }
        .onAppear {
            #if os(macOS)
            // Install a local key monitor so Cmd+A selects all items when this picker is focused.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
                   event.charactersIgnoringModifiers?.lowercased() == "a" {
                    // If a specific album is selected in the sidebar, only select assets from that album.
                    if let album = selectedAlbumFilter {
                        selectedAssets = Set(allPhotos.filter { $0.album == album }.map { $0.asset.localIdentifier })
                    } else {
                        // 'All Items' is selected — select the currently visible/filtered set.
                        selectedAssets = Set(filteredPhotos.map { $0.asset.localIdentifier })
                    }
                    return nil
                }
                return event
            }
            #endif
        }
        .onDisappear {
            #if os(macOS)
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
            #endif
        }
        // Notify main view and dismiss when hiding completes instead of showing an alert here.
        .overlay {
            if importing {
                ZStack {
                    Color.black.opacity(0.5)
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.3)
                        Text("Hiding \(selectedAssets.count) items...")
                            .font(.subheadline)
                        Text("Please wait...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(28)
                    .background(.ultraThickMaterial)
                    .cornerRadius(12)
                }
            }
        }
    }
    
    private var uniqueAlbums: [String] {
        Array(Set(allPhotos.map { $0.album }))
    }

    // Number of unique assets across all albums (counts each PHAsset once)
    private var uniqueAllPhotosCount: Int {
        Set(allPhotos.map { $0.asset.localIdentifier }).count
    }
    
    private func albumPhotoCount(_ album: String) -> Int {
        allPhotos.filter { $0.album == album }.count
    }
    
    private func albumIcon(for album: String) -> String {
        // Special icons for known albums
        if album.contains("Hidden") {
            return "eye.slash.fill"
        } else if album.contains("Favorites") || album.contains("❤️") {
            return "heart.fill"
        } else if album.contains("Recent") {
            return "clock.fill"
        } else if album.contains("Screenshot") {
            return "camera.viewfinder"
        } else if album.contains("Selfie") {
            return "person.crop.circle.fill"
        } else if album.contains("Video") {
            return "video.fill"
        } else if album.contains("Portrait") {
            return "person.fill"
        } else if album.contains("Live Photo") {
            return "livephoto"
        } else if album.contains("Panorama") {
            return "pano.fill"
        } else if album.contains("Burst") {
            return "square.stack.3d.up.fill"
        } else if album.contains("📤") {
            return "person.2.fill"
        } else if album.contains("👤") {
            return "person.fill"
        } else {
            return "photo.on.rectangle"
        }
    }
    
    private var groupedPhotos: [(album: String, photos: [(album: String, asset: PHAsset)])] {
        Dictionary(grouping: filteredPhotos) { $0.album }
            .map { (album: $0.key, photos: $0.value) }
            .sorted { $0.album < $1.album }
    }
    
    private func toggleSelection(_ id: String) {
        if selectedAssets.contains(id) {
            selectedAssets.remove(id)
        } else {
            selectedAssets.insert(id)
        }
    }
    
    private func toggleAlbumSelection(_ assetIds: [String]) {
        let allSelected = assetIds.allSatisfy { selectedAssets.contains($0) }
        if allSelected {
            assetIds.forEach { selectedAssets.remove($0) }
        } else {
            assetIds.forEach { selectedAssets.insert($0) }
        }
    }
    
    private func isAlbumSelected(_ assetIds: [String]) -> Bool {
        assetIds.allSatisfy { selectedAssets.contains($0) }
    }
    
    private func requestPhotosAccess() {
        PhotosLibraryService.shared.requestAccess { granted in
            hasAccess = granted
            if granted {
                loadPhotos()
            }
        }
    }
    
    private func loadPhotos() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            var albums = PhotosLibraryService.shared.getAllAlbums(libraryType: selectedLibrary)
            // Fallback: if user forces shared and requested Shared library, but result is empty, re-fetch all and mark as shared
            if selectedLibrary == .shared {
                let hasAny = !albums.isEmpty
                if forceSharedLibrary && (albums.isEmpty || hasAny) {
                    // Fetch all personal albums and relabel as shared
                    let all = PhotosLibraryService.shared.getAllAlbums(libraryType: .personal)
                    albums = all.map { (name: $0.name, collection: $0.collection) }
                }
            }
            var photos: [(String, PHAsset)] = []

            // Track seen asset IDs per album name. Some PhotoKit collections may share the same
            // album name (e.g. multiple 'Recents' collections), which previously allowed the same
            // PHAsset to be appended multiple times under the same displayed album name. That
            // produced duplicate localIdentifiers inside groupedSections and caused ForEach
            // duplicate-ID warnings. We dedupe by album name here so the UI shows each asset
            // once per displayed album.
            var seenPerAlbum: [String: Set<String>] = [:]

            for album in albums {
                let assets = PhotosLibraryService.shared.getAssets(from: album.collection)
                let albumKey = album.name
                if seenPerAlbum[albumKey] == nil {
                    seenPerAlbum[albumKey] = Set<String>()
                }

                for asset in assets {
                    let id = asset.localIdentifier
                    if seenPerAlbum[albumKey]!.contains(id) { continue }
                    seenPerAlbum[albumKey]!.insert(id)
                    photos.append((albumKey, asset))
                }
            }

            // (diagnostic prints removed)

            DispatchQueue.main.async {
                self.allPhotos = photos
                self.isLoading = false
            }
        }
    }
    
    private func hideSelectedPhotos() {
        guard !selectedAssets.isEmpty else { return }
        importing = true
        
        let assetsToHide = allPhotos.filter { selectedAssets.contains($0.asset.localIdentifier) }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Limit concurrent media fetch & processing to avoid loading many large files into memory at once.
            let semaphore = DispatchSemaphore(value: 2) // allow 2 concurrent operations
            let group = DispatchGroup()
            var successfulAssets: [PHAsset] = []
            let lock = NSLock() // For thread-safe access to successfulAssets

            for photoData in assetsToHide {
                semaphore.wait()
                group.enter()
                PhotosLibraryService.shared.getMediaData(for: photoData.asset) { data, filename, dateTaken, mediaType, duration, location, isFavorite in
                    defer {
                        group.leave()
                        semaphore.signal()
                    }

                    guard let mediaData = data else {
                        print("Failed to get media data for asset: \(photoData.asset.localIdentifier)")
                        return
                    }

                    // Add to vault. Use autoreleasepool to encourage early temporary object cleanup
                    // Perform vault operations on background thread to avoid blocking main thread
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            try autoreleasepool {
                                try vaultManager.hidePhoto(
                                    imageData: mediaData,
                                    filename: filename,
                                    dateTaken: dateTaken,
                                    sourceAlbum: photoData.album,
                                    assetIdentifier: photoData.asset.localIdentifier,
                                    mediaType: mediaType,
                                    duration: duration,
                                    location: location,
                                    isFavorite: isFavorite
                                )
                            }
                            // Use a lock to safely append to the shared array
                            lock.lock()
                            successfulAssets.append(photoData.asset)
                            lock.unlock()
                            print("\(mediaType == .video ? "Video" : "Photo") added to vault: \(filename)")
                        } catch {
                            print("Failed to add media to vault: \(filename) - \(error.localizedDescription)")
                            // Don't add to successfulAssets if it failed
                        }
                    }
                }
            }

            // Wait for all limited tasks to finish
            group.wait()
            
            // Batch delete all successfully vaulted photos at once
            if !successfulAssets.isEmpty {
                PhotosLibraryService.shared.batchDeleteAssets(successfulAssets) { success in
                    if success {
                        print("Successfully deleted \(successfulAssets.count) photos from library")
                    } else {
                        print("Failed to delete some photos from library")
                    }
                    
                    DispatchQueue.main.async {
                        importing = false
                        // Find the SecurePhoto records that correspond to the successfully processed PHAssets
                        let ids = Set(successfulAssets.map { $0.localIdentifier })
                        let newlyHidden = vaultManager.hiddenPhotos.filter { photo in
                            if let original = photo.originalAssetIdentifier {
                                return ids.contains(original)
                            }
                            return false
                        }

                        // Notify main UI with undo-capable notification and dismiss the picker
                        vaultManager.hideNotification = HideNotification(
                            message: "Hidden \(successfulAssets.count) item(s). Moved to Recently Deleted.",
                            type: .success,
                            photos: newlyHidden
                        )
                        dismiss()
                    }
                }
            } else {
                DispatchQueue.main.async {
                    importing = false
                    dismiss()
                }
            }
        }
    }

    @State private var keyMonitor: Any? = nil
}

struct PhotoAssetView: View {
    let asset: PHAsset
    let isSelected: Bool
    @State private var thumbnail: Image?
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = thumbnail {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                    )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 100, height: 100)
            }
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white)
                    .background(Circle().fill(Color.accentColor).padding(2))
                    .padding(4)
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 200, height: 200),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                if let image = image {
                    #if os(macOS)
                    thumbnail = Image(nsImage: image)
                    #else
                    thumbnail = Image(uiImage: image)
                    #endif
                } else {
                    // Thumbnail unavailable for this asset; ignore silently
                }
            }
        }
    }
}

