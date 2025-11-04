import SwiftUI
import UniformTypeIdentifiers
import Photos

struct VaultDetailView: View {
    let vault: Vault
    @EnvironmentObject var vaultManager: VaultManager
    @State private var photos: [SecurePhoto] = []
    @State private var showingImportPicker = false
    @State private var showingPhotosLibrary = false
    @State private var selectedPhoto: SecurePhoto?
    @State private var showingPhotoViewer = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(vault.colorValue.gradient)
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vault.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("\(photos.count) photos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Menu {
                        Button {
                            showingImportPicker = true
                        } label: {
                            Label("From Files", systemImage: "folder")
                        }
                        
                        Button {
                            showingPhotosLibrary = true
                        } label: {
                            Label("From Photos Library", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button {
                        vaultManager.lockVault(vault.id)
                    } label: {
                        Label("Lock", systemImage: "lock.fill")
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Photo grid or empty state
            if photos.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    
                    Text("No Photos Yet")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Import photos from your library or files")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        Button {
                            showingImportPicker = true
                        } label: {
                            Label("Import from Files", systemImage: "folder")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        
                        Button {
                            showingPhotosLibrary = true
                        } label: {
                            Label("Import from Photos", systemImage: "photo.on.rectangle")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)], spacing: 16) {
                        ForEach(photos) { photo in
                            PhotoThumbnailView(photo: photo)
                                .onTapGesture {
                                    selectedPhoto = photo
                                    showingPhotoViewer = true
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            loadPhotos()
        }
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showingPhotoViewer) {
            if let photo = selectedPhoto {
                PhotoViewerSheet(vault: vault, photo: photo)
            }
        }
        .sheet(isPresented: $showingPhotosLibrary) {
            PhotosLibraryPicker(vault: vault, onImport: { loadPhotos() })
        }
    }
    
    private func loadPhotos() {
        photos = vaultManager.getPhotos(for: vault.id)
    }
    
    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            
            if let imageData = try? Data(contentsOf: url) {
                try? vaultManager.addPhoto(
                    to: vault,
                    imageData: imageData,
                    filename: url.lastPathComponent,
                    dateTaken: nil,
                    sourceAlbum: "Imported Files"
                )
            }
        }
        
        loadPhotos()
    }
}

struct PhotoThumbnailView: View {
    let photo: SecurePhoto
    @State private var thumbnailImage: NSImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let image = thumbnailImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 180, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 2)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 180, height: 180)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(photo.filename)
                    .font(.caption)
                    .lineLimit(1)
                
                if let album = photo.sourceAlbum {
                    Text(album)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 180, alignment: .leading)
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: photo.thumbnailPath)),
           let image = NSImage(data: data) {
            thumbnailImage = image
        }
    }
}

struct PhotoViewerSheet: View {
    let vault: Vault
    let photo: SecurePhoto
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var vaultManager: VaultManager
    @State private var fullImage: NSImage?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(photo.filename)
                        .font(.headline)
                    if let album = photo.sourceAlbum {
                        Text("From: \(album)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            // Image
            if let image = fullImage {
                GeometryReader { geometry in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            loadFullImage()
        }
    }
    
    private func loadFullImage() {
        if let decryptedData = try? vaultManager.decryptPhoto(photo, vault: vault),
           let image = NSImage(data: decryptedData) {
            fullImage = image
        }
    }
}

struct PhotosLibraryPicker: View {
    let vault: Vault
    let onImport: () -> Void
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var vaultManager: VaultManager
    
    @State private var albums: [(name: String, collection: PHAssetCollection)] = []
    @State private var selectedAlbum: PHAssetCollection?
    @State private var selectedAssets: Set<String> = []
    @State private var hasAccess = false
    @State private var importing = false
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedAlbum) {
                ForEach(albums, id: \.collection.localIdentifier) { album in
                    HStack {
                        Image(systemName: album.name == "Hidden" ? "eye.slash" : "folder")
                        Text(album.name)
                        Spacer()
                        Text("\(PhotosLibraryService.shared.getAssets(from: album.collection).count)")
                            .foregroundStyle(.secondary)
                    }
                    .tag(album.collection)
                }
            }
            .navigationTitle("Albums")
            .frame(minWidth: 200)
        } detail: {
            if let album = selectedAlbum {
                PhotosGridView(
                    album: album,
                    vault: vault,
                    selectedAssets: $selectedAssets,
                    onImport: {
                        importSelectedPhotos()
                    }
                )
            } else {
                Text("Select an album")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            requestPhotosAccess()
        }
        .overlay {
            if importing {
                ZStack {
                    Color.black.opacity(0.5)
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Importing photos...")
                            .padding(.top)
                    }
                    .padding(30)
                    .background(.ultraThickMaterial)
                    .cornerRadius(12)
                }
            }
        }
    }
    
    private func requestPhotosAccess() {
        PhotosLibraryService.shared.requestAccess { granted in
            hasAccess = granted
            if granted {
                albums = PhotosLibraryService.shared.getAllAlbums()
            }
        }
    }
    
    private func importSelectedPhotos() {
        guard !selectedAssets.isEmpty, let album = selectedAlbum else { return }
        importing = true
        
        let allAssets = PhotosLibraryService.shared.getAssets(from: album)
        let assetsToImport = allAssets.filter { selectedAssets.contains($0.localIdentifier) }
        let albumName = album.localizedTitle ?? "Unknown"
        
        DispatchQueue.global(qos: .userInitiated).async {
            for asset in assetsToImport {
                PhotosLibraryService.shared.getImageData(for: asset) { data, filename, dateTaken in
                    guard let imageData = data else { return }
                    
                    try? vaultManager.addPhoto(
                        to: vault,
                        imageData: imageData,
                        filename: filename,
                        dateTaken: dateTaken,
                        sourceAlbum: albumName
                    )
                }
            }
            
            DispatchQueue.main.async {
                importing = false
                onImport()
                dismiss()
            }
        }
    }
}

struct PhotosGridView: View {
    let album: PHAssetCollection
    let vault: Vault
    @Binding var selectedAssets: Set<String>
    let onImport: () -> Void
    
    @State private var assets: [PHAsset] = []
    @State private var thumbnails: [String: NSImage] = [:]
    
    var body: some View {
        VStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        PhotoAssetView(
                            asset: asset,
                            isSelected: selectedAssets.contains(asset.localIdentifier)
                        )
                        .onTapGesture {
                            toggleSelection(asset.localIdentifier)
                        }
                    }
                }
                .padding()
            }
            
            HStack {
                Text("\(selectedAssets.count) selected")
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button("Cancel") {
                    selectedAssets.removeAll()
                }
                
                Button("Import Selected") {
                    onImport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedAssets.isEmpty)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .onAppear {
            loadAssets()
        }
    }
    
    private func loadAssets() {
        assets = PhotosLibraryService.shared.getAssets(from: album)
    }
    
    private func toggleSelection(_ id: String) {
        if selectedAssets.contains(id) {
            selectedAssets.remove(id)
        } else {
            selectedAssets.insert(id)
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
