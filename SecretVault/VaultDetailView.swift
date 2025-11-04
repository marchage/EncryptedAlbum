import SwiftUI
import UniformTypeIdentifiers
import Photos

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
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with library selector
            HStack {
                Text("Select Photos to Hide")
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
            
            Divider()
            
            // Photos grid
            if isLoading {
                VStack {
                    ProgressView()
                    Text("Loading photos...")
                        .foregroundStyle(.secondary)
                        .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if allPhotos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No photos found")
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
                                    Text("\(group.photos.count) photos")
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
        .frame(minWidth: 900, minHeight: 700)
        .onAppear {
            requestPhotosAccess()
        }
        .overlay {
            if importing {
                ZStack {
                    Color.black.opacity(0.5)
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Hiding \(selectedAssets.count) photos...")
                            .font(.headline)
                        Text("Please wait...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(40)
                    .background(.ultraThickMaterial)
                    .cornerRadius(16)
                }
            }
        }
    }
    
    private var groupedPhotos: [(album: String, photos: [(album: String, asset: PHAsset)])] {
        Dictionary(grouping: allPhotos) { $0.album }
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
            let albums = PhotosLibraryService.shared.getAllAlbums(libraryType: selectedLibrary)
            var photos: [(String, PHAsset)] = []
            
            for album in albums {
                let assets = PhotosLibraryService.shared.getAssets(from: album.collection)
                for asset in assets {
                    photos.append((album.name, asset))
                }
            }
            
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
            let group = DispatchGroup()
            
            for photoData in assetsToHide {
                group.enter()
                PhotosLibraryService.shared.getImageData(for: photoData.asset) { data, filename, dateTaken in
                    defer { group.leave() }
                    guard let imageData = data else { return }
                    
                    try? vaultManager.hidePhoto(
                        imageData: imageData,
                        filename: filename,
                        dateTaken: dateTaken,
                        sourceAlbum: photoData.album,
                        assetIdentifier: photoData.asset.localIdentifier
                    )
                }
            }
            
            group.wait()
            
            DispatchQueue.main.async {
                importing = false
                dismiss()
            }
        }
    }
}

struct PhotoAssetView: View {
    let asset: PHAsset
    let isSelected: Bool
    @State private var thumbnail: NSImage?
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = thumbnail {
                Image(nsImage: image)
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
                    self.thumbnail = image
                }
            }
        }
    }
}

