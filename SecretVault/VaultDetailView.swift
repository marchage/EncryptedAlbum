import SwiftUI
import UniformTypeIdentifiers
import Photos

struct PhotosLibraryPicker: View {
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
                        Text("Hiding photos...")
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
                    
                    try? vaultManager.hidePhoto(
                        imageData: imageData,
                        filename: filename,
                        dateTaken: dateTaken,
                        sourceAlbum: albumName,
                        assetIdentifier: asset.localIdentifier
                    )
                }
            }
            
            DispatchQueue.main.async {
                importing = false
                dismiss()
            }
        }
    }
}

struct PhotosGridView: View {
    let album: PHAssetCollection
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
                
                Button("Hide Selected") {
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

