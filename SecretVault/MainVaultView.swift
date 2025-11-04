import SwiftUI

struct MainVaultView: View {
    @EnvironmentObject var vaultManager: VaultManager
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
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hidden Photos")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("\(vaultManager.hiddenPhotos.count) photos hidden")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button {
                        showingPhotosLibrary = true
                    } label: {
                        Label("Hide Photos", systemImage: "eye.slash")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Menu {
                        Button {
                            vaultManager.removeDuplicates()
                        } label: {
                            Label("Remove Duplicates", systemImage: "trash.slash")
                        }
                        
                        Divider()
                        
                        Button {
                            vaultManager.lock()
                        } label: {
                            Label("Lock Vault", systemImage: "lock.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Photo grid or empty state
            if vaultManager.hiddenPhotos.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    
                    Text("No Hidden Photos")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Hide photos from your Photos Library")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        showingPhotosLibrary = true
                    } label: {
                        Label("Hide Photos from Library", systemImage: "eye.slash")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)], spacing: 16) {
                        ForEach(vaultManager.hiddenPhotos) { photo in
                            PhotoThumbnailView(photo: photo)
                                .onTapGesture {
                                    selectedPhoto = photo
                                    showingPhotoViewer = true
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        vaultManager.deletePhoto(photo)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingPhotoViewer) {
            if let photo = selectedPhoto {
                PhotoViewerSheet(photo: photo)
            }
        }
        .sheet(isPresented: $showingPhotosLibrary) {
            PhotosLibraryPicker()
        }
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
        if let decryptedData = try? vaultManager.decryptPhoto(photo),
           let image = NSImage(data: decryptedData) {
            fullImage = image
        }
    }
}
