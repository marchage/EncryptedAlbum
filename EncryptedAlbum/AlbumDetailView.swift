import Photos
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
    import AppKit
#endif
#if os(iOS)
    import UIKit
#endif

struct AlbumDetailView: View {
    @EnvironmentObject var albumManager: AlbumManager
    @State private var showingPhotoPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Album")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Spacer()

                Button(action: {
                    showingPhotoPicker = true
                }) {
                    Label("Add Photos", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            // Content
            if albumManager.hiddenPhotos.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)

                    Text("No hidden photos yet")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    Text("Click 'Add Photos' to hide some photos from your library.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Add Photos") {
                        showingPhotoPicker = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                        ForEach(albumManager.hiddenPhotos) { photo in
                            AlbumPhotoView(photo: photo)
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingPhotoPicker) {
            PhotosLibraryPicker()
        }
    }
}

struct AlbumPhotoView: View {
    let photo: SecurePhoto
    @State private var thumbnail: Image?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = thumbnail {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 120)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(photo.filename)
                    .font(.caption)
                    .lineLimit(1)

                Text(photo.dateAdded, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        Task {
            do {
                let thumbnailData = try await AlbumManager.shared.decryptThumbnail(for: photo)
                if !thumbnailData.isEmpty {
                    #if os(macOS)
                        await MainActor.run {
                            if let nsImage = NSImage(data: thumbnailData),
                                let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
                            {
                                thumbnail = Image(decorative: cgImage, scale: 1, orientation: .up)
                            }
                        }
                    #else
                        if let uiImage = UIImage(data: thumbnailData) {
                            await MainActor.run {
                                thumbnail = Image(uiImage: uiImage)
                            }
                        }
                    #endif
                }
            } catch {
                // Thumbnail decryption failed, keep placeholder
                #if DEBUG
                    print("Failed to load thumbnail for \(photo.filename): \(error)")
                #endif
            }
        }
    }
}
struct PhotosLibraryPicker: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var albumManager: AlbumManager
    @Environment(\.scenePhase) var scenePhase
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    @State private var albums: [(name: String, collection: PHAssetCollection)] = []
    @State private var allPhotos: [(album: String, asset: PHAsset)] = []
    @State private var selectedAssets: Set<String> = []
    @State private var hasAccess = false
    // Import state is now managed by AlbumManager
    @State private var selectedLibrary: LibraryType = .personal
    @State private var isLoading = false
    @State private var selectedAlbumFilter: String? = nil
    // Fallback: Force treat all albums as Shared Library when PhotoKit can't distinguish
    @State private var forceSharedLibrary = false
    @State private var keyMonitor: Any? = nil
    @State private var isAppActive = true
    private typealias IndexedAsset = (index: Int, album: String, asset: PHAsset)

    var filteredPhotos: [(album: String, asset: PHAsset)] {
        if let filter = selectedAlbumFilter {
            return allPhotos.filter { $0.album == filter }
        }
        return allPhotos
    }

    var body: some View {
        SecureWrapper {
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
                                        Image(systemName: album.albumIcon)
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
                                    .background(
                                        selectedAlbumFilter == album ? Color.accentColor.opacity(0.2) : Color.clear
                                    )
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
                #else
                    // On iOS (especially portrait) constrain the sidebar so it doesn't take
                    // an excessive portion of the screen. Keep it flexible but bounded.
                    .frame(minWidth: 80, idealWidth: 110, maxWidth: 140)
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

                                headerSelectionControls

                                headerCancelButton

                                headerHideButton
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
                                .onChange(of: selectedLibrary) { _, _ in
                                    loadPhotos()
                                }

                                // Manual fallback toggle only relevant when user selects Shared
                                if selectedLibrary == .shared {
                                    Toggle("Force Shared", isOn: $forceSharedLibrary)
                                        .toggleStyle(.switch)
                                        .help(
                                            "If your Shared Library photos are not detected (PhotoKit sourceType always = personal), enable this to treat all albums as shared."
                                        )
                                        .onChange(of: forceSharedLibrary) { _, _ in
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
                            .onChange(of: selectedLibrary) { _, _ in
                                loadPhotos()
                            }
                            // Manual fallback toggle only relevant when user selects Shared
                            Toggle("Force Shared", isOn: $forceSharedLibrary)
                                .toggleStyle(.switch)
                                .help(
                                    "If your Shared Library photos are not detected (PhotoKit sourceType always = personal), enable this to treat all albums as shared."
                                )
                                .onChange(of: forceSharedLibrary) { _, _ in
                                    if selectedLibrary == .shared { loadPhotos() }
                                }
                                .padding(.leading, 8)
                                .frame(maxWidth: 130)

                            Button("Cancel") {
                                dismiss()
                            }
                            .accessibilityIdentifier("photosPickerCancelButton")
                            .keyboardShortcut(.cancelAction)

                            Button("Hide Selected (\(selectedAssets.count))") {
                                Task {
                                    await hideSelectedPhotos()
                                }
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
                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8)
                                        {
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
                                                Text(
                                                    isAlbumSelected(group.photos.map { $0.asset.localIdentifier })
                                                        ? "Deselect All" : "Select All"
                                                )
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
        }
        #if os(macOS)
            .frame(minWidth: 900, minHeight: 700)
        #endif
        .onAppear {
            #if os(iOS)
                UltraPrivacyCoordinator.shared.beginTrustedModal()
            #endif
            requestPhotosAccess()
        }
        .onAppear {
            #if os(macOS)
                // Install a local key monitor so Cmd+A selects all items when this picker is focused.
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
                        event.charactersIgnoringModifiers?.lowercased() == "a"
                    {
                        // If a specific album is selected in the sidebar, only select assets from that album.
                        if let album = selectedAlbumFilter {
                            selectedAssets = Set(
                                allPhotos.filter { $0.album == album }.map { $0.asset.localIdentifier })
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
            #if os(iOS)
                UltraPrivacyCoordinator.shared.endTrustedModal()
            #endif
            #if os(macOS)
                if let monitor = keyMonitor {
                    NSEvent.removeMonitor(monitor)
                    keyMonitor = nil
                }
            #endif
        }
        // Notify main view and dismiss when hiding completes instead of showing an alert here.
        .overlay {
            if albumManager.importProgress.isImporting {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        if albumManager.importProgress.totalItems > 0 {
                            let totalItems = max(albumManager.importProgress.totalItems, 1)
                            let processedItems = min(albumManager.importProgress.processedItems, totalItems)
                            ProgressView(
                                value: Double(processedItems),
                                total: Double(totalItems)
                            )
                            .progressViewStyle(.linear)
                            .frame(maxWidth: UIConstants.progressCardWidth)
                        } else {
                            ProgressView()
                                .progressViewStyle(.linear)
                                .frame(maxWidth: UIConstants.progressCardWidth)
                        }

                        if albumManager.importProgress.currentBytesTotal > 0 {
                            ProgressView(
                                value: Double(
                                    min(
                                        albumManager.importProgress.currentBytesProcessed,
                                        albumManager.importProgress.currentBytesTotal)),
                                total: Double(max(albumManager.importProgress.currentBytesTotal, 1))
                            )
                            .progressViewStyle(.linear)
                            .frame(maxWidth: UIConstants.progressCardWidth)

                            if isAppActive {
                                Text(
                                    "\(formattedBytes(albumManager.importProgress.currentBytesProcessed)) of \(formattedBytes(albumManager.importProgress.currentBytesTotal))"
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            } else {
                                let percent =
                                    Double(albumManager.importProgress.currentBytesProcessed)
                                    / Double(max(albumManager.importProgress.currentBytesTotal, 1))
                                Text(String(format: "%.0f%%", percent * 100))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ProgressView()
                                .progressViewStyle(.linear)
                                .frame(maxWidth: UIConstants.progressCardWidth)
                            Text(
                                albumManager.importProgress.currentBytesProcessed > 0
                                    ? "\(formattedBytes(albumManager.importProgress.currentBytesProcessed)) processed…"
                                    : "Preparing file size…"
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }

                        Text(
                            isAppActive
                                ? (albumManager.importProgress.statusMessage.isEmpty
                                    ? "Encrypting items…" : albumManager.importProgress.statusMessage)
                                : "Encrypting items…"
                        )
                        .font(.headline)

                        if albumManager.importProgress.totalItems > 0 {
                            Text(
                                "\(albumManager.importProgress.processedItems) of \(albumManager.importProgress.totalItems)"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        if !albumManager.importProgress.detailMessage.isEmpty && isAppActive {
                            Text(albumManager.importProgress.detailMessage)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: UIConstants.progressCardWidth)
                    .background(.ultraThickMaterial)
                    .cornerRadius(16)
                    .shadow(radius: 18)
                }
            }
        }
        #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                isAppActive = false
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                isAppActive = true
            }
            .onAppear {
                isAppActive = NSApplication.shared.isActive
            }
        #else
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    isAppActive = true
                } else if newPhase == .background || newPhase == .inactive {
                    isAppActive = false
                }
            }
        #endif
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

    private var groupedPhotos: [(album: String, photos: [(album: String, asset: PHAsset)])] {
        Dictionary(grouping: filteredPhotos) { $0.album }
            .map { (album: $0.key, photos: $0.value) }
            .sorted { $0.album < $1.album }
    }

    private var visibleAssetIdentifiers: [String] {
        filteredPhotos.map { $0.asset.localIdentifier }
    }

    private var allVisibleAssetsSelected: Bool {
        guard !visibleAssetIdentifiers.isEmpty else { return false }
        return visibleAssetIdentifiers.allSatisfy { selectedAssets.contains($0) }
    }

    private var anyVisibleAssetsSelected: Bool {
        visibleAssetIdentifiers.contains { selectedAssets.contains($0) }
    }

    private func toggleSelection(_ id: String) {
        if selectedAssets.contains(id) {
            selectedAssets.remove(id)
        } else {
            selectedAssets.insert(id)
        }
    }

    private func selectAllVisibleAssets() {
        visibleAssetIdentifiers.forEach { selectedAssets.insert($0) }
    }

    private func deselectAllVisibleAssets() {
        visibleAssetIdentifiers.forEach { selectedAssets.remove($0) }
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

    private func hideSelectedPhotos() async {
        guard !selectedAssets.isEmpty else { return }

        var seenIds = Set<String>()
        let assetsToHide: [PHAsset] = allPhotos.compactMap { entry in
            let identifier = entry.asset.localIdentifier
            guard selectedAssets.contains(identifier), !seenIds.contains(identifier) else { return nil }
            seenIds.insert(identifier)
            return entry.asset
        }

        guard !assetsToHide.isEmpty else { return }

        await albumManager.importAssets(assetsToHide)
        dismiss()
    }

    private func formattedBytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(value, 0))
    }
}

#if os(iOS)
    extension PhotosLibraryPicker {
        private var isCompactHeader: Bool {
            guard let horizontalSizeClass else { return false }
            if horizontalSizeClass == .compact {
                if let verticalSizeClass, verticalSizeClass == .compact {
                    return false
                }
                return true
            }
            return false
        }

        @ViewBuilder
        private var headerSelectionControls: some View {
            if !visibleAssetIdentifiers.isEmpty {
                HStack(spacing: isCompactHeader ? 4 : 8) {
                    Button(action: selectAllVisibleAssets) {
                        Group {
                            if isCompactHeader {
                                compactSelectAllIcon
                            } else {
                                Label {
                                    Text("All")
                                } icon: {
                                    Image(systemName: "square.grid.2x2.fill")
                                }
                                .font(.subheadline)
                            }
                        }
                        .padding(isCompactHeader ? 0 : 0)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(allVisibleAssetsSelected)
                    .accessibilityLabel("Select all visible items")

                    Button(action: deselectAllVisibleAssets) {
                        Group {
                            if isCompactHeader {
                                compactDeselectAllIcon
                            } else {
                                Label {
                                    Text("None")
                                } icon: {
                                    Image(systemName: "square.grid.2x2")
                                }
                                .font(.subheadline)
                            }
                        }
                        .padding(isCompactHeader ? 0 : 0)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!anyVisibleAssetsSelected)
                    .accessibilityLabel("Deselect all visible items")
                }
            }
        }

        private var compactSelectAllIcon: some View {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }

        private var compactDeselectAllIcon: some View {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.secondary)
        }

        private var headerCancelButton: some View {
            Button(action: { dismiss() }) {
                Group {
                    if isCompactHeader {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                    } else {
                        Label {
                            Text("Canc")
                                .font(.subheadline)
                        } icon: {
                            Image(systemName: "xmark.circle.fill")
                        }
                    }
                }
                .padding(isCompactHeader ? 6 : 0)
            }
            .accessibilityIdentifier("photosPickerCancelButton")
            .keyboardShortcut(.cancelAction)
            .controlSize(.small)
            .accessibilityLabel("Cancel selection")
        }

        private var headerHideButton: some View {
            Button(action: {
                Task {
                    await hideSelectedPhotos()
                }
            }) {
                Group {
                    if isCompactHeader {
                        compactHideIcon
                    } else {
                        Label {
                            Text("Hide (\(selectedAssets.count))")
                                .font(.subheadline)
                        } icon: {
                            Image(systemName: "lock.fill")
                        }
                    }
                }
                .frame(minWidth: isCompactHeader ? 36 : nil, minHeight: isCompactHeader ? 36 : nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(selectedAssets.isEmpty)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("Hide \(selectedAssets.count) items")
        }

        private var compactHideIcon: some View {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(selectedAssets.isEmpty ? Color.secondary.opacity(0.18) : Color.accentColor)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "lock.fill")
                            .font(.callout)
                            .foregroundStyle(selectedAssets.isEmpty ? Color.secondary : Color.white)
                    )

                if selectedAssets.count > 0 {
                    Text(selectionBadgeText)
                        .font(.caption.bold())
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)
                        )
                        .offset(x: 8, y: -8)
                }
            }
        }

        private var selectionBadgeText: String {
            if selectedAssets.count > 99 { return "99+" }
            return "\(selectedAssets.count)"
        }
    }

#endif

struct PhotoAssetView: View {
    let asset: PHAsset
    let isSelected: Bool
    @State private var thumbnail: Image?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = thumbnail {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Circle().fill(Color.accentColor))
                    .padding(6)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
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

// MARK: - Helper Extensions

extension String {
    /// Returns an appropriate SF Symbol icon name for an album.
    var albumIcon: String {
        if contains("Hidden") {
            return "eye.slash.fill"
        } else if contains("Favorites") || contains("❤️") {
            return "heart.fill"
        } else if contains("Recent") {
            return "clock.fill"
        } else if contains("Screenshot") {
            return "camera.viewfinder"
        } else if contains("Selfie") {
            return "person.crop.circle.fill"
        } else if contains("Video") {
            return "video.fill"
        } else if contains("Portrait") {
            return "person.fill"
        } else if contains("Live Photo") {
            return "livephoto"
        } else if contains("Panorama") {
            return "pano.fill"
        } else if contains("Burst") {
            return "square.stack.3d.up.fill"
        } else if contains("📤") {
            return "person.2.fill"
        } else if contains("👤") {
            return "person.fill"
        } else {
            return "photo.on.rectangle"
        }
    }
}
