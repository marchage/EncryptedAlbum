import SwiftUI

struct MainVaultView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @State private var showingPhotosLibrary = false
    @State private var selectedPhoto: SecurePhoto?
    @State private var showingPhotoViewer = false
    @State private var selectedPhotos: Set<UUID> = []
    @State private var searchText = ""
    @State private var selectedAlbum: String? = nil
    @State private var showingAlbumSheet = false
    @State private var newAlbumName = ""
    @State private var showingRestoreOptions = false
    @State private var photosToRestore: [SecurePhoto] = []
    
    var filteredPhotos: [SecurePhoto] {
        var photos = vaultManager.hiddenPhotos
        
        // Filter by album
        if let album = selectedAlbum {
            photos = photos.filter { $0.vaultAlbum == album }
        }
        
        // Filter by search
        if !searchText.isEmpty {
            photos = photos.filter { photo in
                photo.filename.localizedCaseInsensitiveContains(searchText) ||
                photo.sourceAlbum?.localizedCaseInsensitiveContains(searchText) == true ||
                photo.vaultAlbum?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        
        return photos
    }
    
    var vaultAlbums: [String] {
        let albums = Set(vaultManager.hiddenPhotos.compactMap { $0.vaultAlbum })
        return albums.sorted()
    }
    
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
                    if !selectedPhotos.isEmpty {
                        Text("\(selectedPhotos.count) selected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Button {
                            restoreSelectedPhotos()
                        } label: {
                            Label("Restore Selected", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                        
                        Button {
                            exportSelectedPhotos()
                        } label: {
                            Label("Export Selected", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        
                        Button(role: .destructive) {
                            deleteSelectedPhotos()
                        } label: {
                            Label("Delete Selected", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        
                        Divider()
                            .frame(height: 20)
                    }
                    
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                    
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
                        ForEach(filteredPhotos) { photo in
                            PhotoThumbnailView(photo: photo, isSelected: selectedPhotos.contains(photo.id))
                                .onTapGesture(count: 2) {
                                    selectedPhoto = photo
                                    showingPhotoViewer = true
                                }
                                .onTapGesture {
                                    toggleSelection(photo.id)
                                }
                                .contextMenu {
                                    Button {
                                        vaultManager.restorePhotoToLibrary(photo)
                                    } label: {
                                        Label("Restore to Photos", systemImage: "arrow.uturn.backward")
                                    }
                                    
                                    Divider()
                                    
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
        .onAppear {
            selectedPhotos.removeAll()
            setupKeyboardShortcuts()
        }
        .alert("Restore Photos", isPresented: $showingRestoreOptions) {
            Button("Restore to Original Albums") {
                restoreToOriginalAlbums()
            }
            Button("Restore to New Album") {
                restoreToNewAlbum()
            }
            Button("Just Add to Library") {
                restoreToLibrary()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("How would you like to restore \(photosToRestore.count) photo(s)?")
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
    
    private func setupKeyboardShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) {
                if event.charactersIgnoringModifiers == "a" {
                    selectAll()
                    return nil
                }
            }
            return event
        }
    }
    
    private func toggleSelection(_ id: UUID) {
        if selectedPhotos.contains(id) {
            selectedPhotos.remove(id)
        } else {
            selectedPhotos.insert(id)
        }
    }
    
    private func selectAll() {
        selectedPhotos = Set(filteredPhotos.map { $0.id })
    }
    
    private func exportSelectedPhotos() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose a folder to export photos to"
        panel.canSelectHiddenExtension = true
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                exportPhotos(to: url)
            }
        }
    }
    
    private func exportPhotos(to folderURL: URL) {
        let photosToExport = vaultManager.hiddenPhotos.filter { selectedPhotos.contains($0.id) }
        
        DispatchQueue.global(qos: .userInitiated).async {
            for photo in photosToExport {
                do {
                    let decryptedData = try vaultManager.decryptPhoto(photo)
                    let fileURL = folderURL.appendingPathComponent(photo.filename)
                    try decryptedData.write(to: fileURL)
                    print("Exported: \(photo.filename)")
                } catch {
                    print("Failed to export \(photo.filename): \(error)")
                }
            }
            
            DispatchQueue.main.async {
                selectedPhotos.removeAll()
                // Could show a success message here
            }
        }
    }
    
    private func restoreSelectedPhotos() {
        photosToRestore = vaultManager.hiddenPhotos.filter { selectedPhotos.contains($0.id) }
        showingRestoreOptions = true
    }
    
    private func restoreToOriginalAlbums() {
        selectedPhotos.removeAll()
        vaultManager.batchRestorePhotos(photosToRestore, restoreToSourceAlbum: true)
    }
    
    private func restoreToNewAlbum() {
        // Prompt for album name
        let alert = NSAlert()
        alert.messageText = "Create New Album"
        alert.informativeText = "Enter a name for the new album:"
        alert.alertStyle = .informational
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.placeholderString = "Album Name"
        alert.accessoryView = textField
        
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            let albumName = textField.stringValue
            if !albumName.isEmpty {
                selectedPhotos.removeAll()
                vaultManager.batchRestorePhotos(photosToRestore, toNewAlbum: albumName)
            }
        }
    }
    
    private func restoreToLibrary() {
        selectedPhotos.removeAll()
        vaultManager.batchRestorePhotos(photosToRestore, restoreToSourceAlbum: false)
    }
    
    private func deleteSelectedPhotos() {
        let photosToDelete = vaultManager.hiddenPhotos.filter { selectedPhotos.contains($0.id) }
        for photo in photosToDelete {
            vaultManager.deletePhoto(photo)
        }
        selectedPhotos.removeAll()
    }
}

struct PhotoThumbnailView: View {
    let photo: SecurePhoto
    let isSelected: Bool
    @State private var thumbnailImage: NSImage?
    @State private var loadTask: Task<Void, Never>?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if let image = thumbnailImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 180, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 180, height: 180)
                        .overlay {
                            ProgressView()
                                .controlSize(.small)
                        }
                }
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .background(Circle().fill(Color.accentColor).padding(3))
                        .padding(6)
                }
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
        .onDisappear {
            loadTask?.cancel()
        }
    }
    
    private func loadThumbnail() {
        loadTask = Task {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: photo.thumbnailPath)) else {
                return
            }
            
            await MainActor.run {
                thumbnailImage = NSImage(data: data)
            }
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
        DispatchQueue.global(qos: .userInitiated).async {
            if let decryptedData = try? vaultManager.decryptPhoto(photo),
               let image = NSImage(data: decryptedData) {
                DispatchQueue.main.async {
                    fullImage = image
                }
            }
        }
    }
}
