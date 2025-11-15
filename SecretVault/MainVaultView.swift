import SwiftUI
import AVKit
#if os(macOS)
import AppKit
#endif

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
    @AppStorage("vaultPrivacyModeEnabled") private var privacyModeEnabled: Bool = true
    @AppStorage("undoTimeoutSeconds") private var undoTimeoutSeconds: Double = 5.0
#if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
#endif
    
    private var actionIconFontSize: CGFloat {
#if os(iOS)
        return verticalSizeClass == .regular ? 18 : 22
#else
        return 22
#endif
    }
    
    private var actionButtonDimension: CGFloat {
#if os(iOS)
    #warning("Action button sizes reduced for a more compact toolbar")
        return verticalSizeClass == .regular ? 36 : 44
#else
        return 44
#endif
    }
    
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
    
    @State private var headerHeight: CGFloat = 0
    
    struct HeaderHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
    
    func setupKeyboardShortcuts() {
#if os(macOS)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // If the Photos picker sheet is shown, let it receive Cmd+A instead of handling it globally
            if showingPhotosLibrary {
                return event
            }
            
            if event.modifierFlags.contains(.command) {
                if event.charactersIgnoringModifiers == "a" {
                    selectAll()
                    return nil
                }
            }
            
            return event
        }
#endif
    }
    
    func toggleSelection(_ id: UUID) {
        if selectedPhotos.contains(id) {
            selectedPhotos.remove(id)
        } else {
            selectedPhotos.insert(id)
        }
    }
    
    func selectAll() {
        selectedPhotos = Set(filteredPhotos.map { $0.id })
    }
    
    func exportSelectedPhotos() {
#if os(macOS)
        vaultManager.touchActivity()
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose a folder to export items to"
        panel.canSelectHiddenExtension = true
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                exportPhotos(to: url)
            }
        }
#endif
    }
    
    func exportPhotos(to folderURL: URL) {
        vaultManager.touchActivity()
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
    
    // Helpers for banner icon and color (moved into MainVaultView scope)
    func iconName(for type: HideNotificationType) -> String {
        switch type {
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.octagon.fill"
        case .info: "info.circle.fill"
        }
    }
    
    func iconColor(for type: HideNotificationType) -> Color {
        switch type {
        case .success: Color.green
        case .failure: Color.red
        case .info: Color.gray
        }
    }
    
    func restoreSelectedPhotos() {
        vaultManager.touchActivity()
        photosToRestore = vaultManager.hiddenPhotos.filter { selectedPhotos.contains($0.id) }
        showingRestoreOptions = true
    }
    
    func restoreToOriginalAlbums() {
        vaultManager.touchActivity()
        selectedPhotos.removeAll()
        vaultManager.batchRestorePhotos(photosToRestore, restoreToSourceAlbum: true)
    }
    
    func restoreToNewAlbum() {
#if os(macOS)
        vaultManager.touchActivity()
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
#endif
    }
    
    func restoreToLibrary() {
        vaultManager.touchActivity()
        selectedPhotos.removeAll()
        vaultManager.batchRestorePhotos(photosToRestore, restoreToSourceAlbum: false)
    }
    
    func deleteSelectedPhotos() {
        vaultManager.touchActivity()
        let photosToDelete = vaultManager.hiddenPhotos.filter { selectedPhotos.contains($0.id) }
        for photo in photosToDelete {
            vaultManager.deletePhoto(photo)
        }
        selectedPhotos.removeAll()
    }
    
    func chooseVaultLocation() {
#if os(macOS)
        // Step-up authentication before allowing vault location change
        vaultManager.requireStepUpAuthentication { success in
            guard success else { return }
            
            vaultManager.touchActivity()
            
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Choose"
            panel.message = "Select the folder where SecretVault should store its encrypted vault."
            
            panel.begin { response in
                guard response == .OK, let baseURL = panel.url else { return }
                
                // Ask for explicit confirmation and explain implications
                let confirmAlert = NSAlert()
                confirmAlert.messageText = "Change Vault Location?"
                confirmAlert.informativeText = "SecretVault will copy your existing encrypted vault to a new 'SecretVault' folder inside the selected location. If the folder is in iCloud Drive or another synced location, the encrypted vault files (including encrypted thumbnails and metadata) will be synced there. The old vault folder will be left in place so you can clean it up manually."
                confirmAlert.alertStyle = .warning
                confirmAlert.addButton(withTitle: "Move Vault")
                confirmAlert.addButton(withTitle: "Cancel")
                
                let response = confirmAlert.runModal()
                guard response == .alertFirstButtonReturn else { return }
                
                DispatchQueue.global(qos: .userInitiated).async {
                    let fileManager = FileManager.default
                    let oldBase = vaultManager.vaultBaseURL
                    let newBase = baseURL.appendingPathComponent("SecretVault", isDirectory: true)
                    let migrationMarker = newBase.appendingPathComponent("migration-in-progress", isDirectory: false)
                    
                    do {
                        try fileManager.createDirectory(at: newBase, withIntermediateDirectories: true)
                        try "".data(using: .utf8)?.write(to: migrationMarker)
                        
                        // Copy photos directory
                        let oldPhotosURL = oldBase.appendingPathComponent("photos", isDirectory: true)
                        let newPhotosURL = newBase.appendingPathComponent("photos", isDirectory: true)
                        if fileManager.fileExists(atPath: oldPhotosURL.path) {
                            try fileManager.createDirectory(at: newPhotosURL, withIntermediateDirectories: true)
                            let items = try fileManager.contentsOfDirectory(atPath: oldPhotosURL.path)
                            for item in items {
                                let src = oldPhotosURL.appendingPathComponent(item)
                                let dst = newPhotosURL.appendingPathComponent(item)
                                if fileManager.fileExists(atPath: dst.path) {
                                    try fileManager.removeItem(at: dst)
                                }
                                try fileManager.copyItem(at: src, to: dst)
                            }
                        }
                        
                        // Copy metadata files (except settings, which will be regenerated)
                        let oldPhotosFile = oldBase.appendingPathComponent("hidden_photos.json")
                        let newPhotosFile = newBase.appendingPathComponent("hidden_photos.json")
                        if fileManager.fileExists(atPath: oldPhotosFile.path) {
                            if fileManager.fileExists(atPath: newPhotosFile.path) {
                                try fileManager.removeItem(at: newPhotosFile)
                            }
                            try fileManager.copyItem(at: oldPhotosFile, to: newPhotosFile)
                        }
                        
                        DispatchQueue.main.async {
                            vaultManager.vaultBaseURL = newBase
                        }
                        
                        // Remove marker once migration completes
                        try? fileManager.removeItem(at: migrationMarker)
                    } catch {
                        try? fileManager.removeItem(at: migrationMarker)
                        DispatchQueue.main.async {
                            let errorAlert = NSAlert()
                            errorAlert.messageText = "Failed to Move Vault"
                            errorAlert.informativeText = "SecretVault could not copy your vault to the new location. Your existing vault remains at its previous location. Error: \(error.localizedDescription)"
                            errorAlert.alertStyle = .critical
                            errorAlert.addButton(withTitle: "OK")
                            errorAlert.runModal()
                        }
                    }
                }
            }
        }
#endif
    }
    
#if DEBUG
    func resetVaultForDevelopment() {
#if os(macOS)
        let alert = NSAlert()
        alert.messageText = "Reset Vault? (Development)"
        alert.informativeText = "This will delete all vault data, the password, and return to setup. This action cannot be undone."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Reset Vault")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            // Delete all vault files
            let fileManager = FileManager.default
            let vaultDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("SecretVault")
            
            if let vaultDirectory = vaultDirectory {
                try? fileManager.removeItem(at: vaultDirectory)
            }
            
            // Delete password hash
            UserDefaults.standard.removeObject(forKey: "passwordHash")
            
            // Delete Keychain entry
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.secretvault.password"
            ]
            SecItemDelete(query as CFDictionary)
            
            // Lock the vault which will trigger setup
            vaultManager.lock()
        }
#endif
    }
#endif
    
    var body: some View {
        return ZStack(alignment: .top) {
            // Update headerHeight from preference changes
            Color.clear
                .onPreferenceChange(HeaderHeightKey.self) { value in
                    headerHeight = value
                }
            #if DEBUG
            // Debug overlay to show measured header height for tuning
            VStack {
                HStack {
                    Text("headerHeight: \(Int(headerHeight))")
                        .font(.caption2)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        .padding(.leading, 8)
                    Spacer()
                }
                Spacer()
            }
            #endif
            VStack(spacing: 0) {
                // Responsive Toolbar
                let isLandscape: Bool = {
#if os(iOS)
                    return UIScreen.main.bounds.width > UIScreen.main.bounds.height
#else
                    return false
#endif
                }()
                HStack(alignment: .center, spacing: isLandscape ? 24 : 8) {
                    // App Icon and Title
                    HStack(spacing: isLandscape ? 20 : 8) {
#if os(macOS)
                        if let appIcon = NSImage(named: "AppIcon") {
                            Image(nsImage: appIcon)
                                .resizable()
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
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
                        }
#else
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
#endif
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hidden Items")
                                .font(isLandscape ? .title : .title2)
                                .fontWeight(.bold)
                            Text("\(vaultManager.hiddenPhotos.count) items hidden")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    // Controls
                    HStack(spacing: isLandscape ? 16 : 4) {
                        if !selectedPhotos.isEmpty {
                        Text("\(selectedPhotos.count) selected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            
                            Button {
                                restoreSelectedPhotos()
                            } label: {
                                Label("Restore Selected", systemImage: "arrow.uturn.backward")
                            }
                            .buttonStyle(.bordered)
#if os(iOS)
                            .controlSize(.mini)
#else
                            .controlSize(.regular)
#endif
                            .disabled(vaultManager.restorationProgress.isRestoring)
                            
                            Button {
                                exportSelectedPhotos()
                            } label: {
                                Label("Export Selected", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
#if os(iOS)
                            .controlSize(.mini)
#else
                            .controlSize(.regular)
#endif
                            
                            Button(role: .destructive) {
                                deleteSelectedPhotos()
                            } label: {
                                Label("Delete Selected", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
#if os(iOS)
                            .controlSize(.mini)
#else
                            .controlSize(.regular)
#endif
                            
                            Divider()
                                .frame(height: 20)
                        }
                        
                        TextField("Search...", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 120)
                        
                        Toggle(isOn: $privacyModeEnabled) {
                            Image(systemName: privacyModeEnabled ? "eye.slash.fill" : "eye.fill")
                        }
                        .toggleStyle(.switch)
                        .help(privacyModeEnabled ? "Thumbnails are hidden (privacy mode)" : "Thumbnails are visible")
                        
                        Button {
                            showingPhotosLibrary = true
                        } label: {
                            Image(systemName: "lock.fill")
                                .font(.system(size: actionIconFontSize))
                                .foregroundColor(.white)
                                .frame(width: actionButtonDimension, height: actionButtonDimension)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue))
                                .shadow(radius: 2)
                        }
                        .buttonStyle(.plain)
#if os(iOS)
                        .controlSize(.mini)
#else
                        .controlSize(.large)
#endif
                        
                        Menu {
#if os(macOS)
                            Button {
                                chooseVaultLocation()
                            } label: {
                                Label("Choose Vault Folder…", systemImage: "folder")
                            }
                            
                            Divider()
#endif
                            
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
                            
#if DEBUG
                            Divider()
                            
                            Button(role: .destructive) {
                                resetVaultForDevelopment()
                            } label: {
                                Label("🔧 Reset Vault (Dev)", systemImage: "trash.circle")
                            }
#endif
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: actionIconFontSize))
                                .foregroundColor(.white)
                                .frame(width: actionButtonDimension, height: actionButtonDimension)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue))
                                .shadow(radius: 2)
                        }
                        .menuStyle(.borderlessButton)
#if os(iOS)
                        .controlSize(.mini)
#else
                        .controlSize(.large)
#endif
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: HeaderHeightKey.self, value: proxy.size.height)
                })
                
                Divider()
                
                // Notification banner placed below the header so it doesn't overlap toolbar controls
                if let note = vaultManager.hideNotification {
                    // Compute valid photos for Undo: ensure photos still exist in the vault
                    let validPhotos = note.photos?.filter { returned in
                        vaultManager.hiddenPhotos.contains(where: { $0.id == returned.id })
                    } ?? []
                    
                    VStack {
                        HStack(spacing: 12) {
                            Image(systemName: iconName(for: note.type))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(Circle().fill(iconColor(for: note.type)))
                            
                            Text(note.message)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            if !validPhotos.isEmpty {
                                Button("Undo") {
                                    for photo in validPhotos {
                                        vaultManager.restorePhotoToLibrary(photo)
                                    }
                                    withAnimation {
                                        vaultManager.hideNotification = nil
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            
                            Button("Open Photos App") {
#if os(macOS)
                                NSWorkspace.shared.open(URL(string: "photos://")!)
#endif
                                withAnimation {
                                    vaultManager.hideNotification = nil
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            Group {
                                switch note.type {
                                case .success: Color.green.opacity(0.14)
                                case .failure: Color.red.opacity(0.14)
                                case .info: Color.gray.opacity(0.12)
                                }
                            }
                        )
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + undoTimeoutSeconds) {
                            withAnimation {
                                vaultManager.hideNotification = nil
                            }
                        }
                    }
                }
                
                // Restoration progress banner
                if vaultManager.restorationProgress.isRestoring {
                    VStack(spacing: 8) {
                        HStack {
                            ProgressView(value: vaultManager.restorationProgress.progress)
                                .progressViewStyle(.linear)
                            
                            Text("\(vaultManager.restorationProgress.processedItems)/\(vaultManager.restorationProgress.totalItems)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 60)
                        }
                        
                        HStack {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .foregroundStyle(.blue)
                            Text("Restoring items to Photos library...")
                                .font(.subheadline)
                            Spacer()
                            if vaultManager.restorationProgress.failedItems > 0 {
                                Text("\(vaultManager.restorationProgress.failedItems) failed")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding()
                    .background(.blue.opacity(0.1))
                    
                    Divider()
                }
                
                // Photo grid or empty state
                if vaultManager.hiddenPhotos.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        
                        Text("No Hidden Items")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Hide photos and videos from your Photos Library")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        
                        Button {
                            showingPhotosLibrary = true
                        } label: {
                            Image(systemName: "lock.fill")
                                .font(.system(size: actionIconFontSize))
                                .foregroundColor(.white)
                                .frame(width: actionButtonDimension, height: actionButtonDimension)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue))
                                .shadow(radius: 2)
                            Text("Hide Items from Library")
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
#if os(iOS)
                        .controlSize(.mini)
#else
                        .controlSize(.large)
#endif
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, max(headerHeight + 36, 56))
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: max(headerHeight + 36, 56))
                            GeometryReader { geometry in
                                let minSize: CGFloat = geometry.size.width < 420 ? 90 : 150
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: minSize, maximum: 200), spacing: 16)], spacing: 16) {
                                    ForEach(filteredPhotos) { photo in
                                        PhotoThumbnailView(photo: photo, isSelected: selectedPhotos.contains(photo.id), privacyModeEnabled: privacyModeEnabled)
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
                                                    Label("Restore to Library", systemImage: "arrow.uturn.backward")
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
                                .padding([.leading, .trailing, .bottom])
                            }
                        }
                    }
                }
                // Banner was moved into the VStack above so it doesn't overlap header controls
            }
            .onAppear {
                selectedPhotos.removeAll()
                setupKeyboardShortcuts()
                vaultManager.touchActivity()
            }
            .alert("Restore Items", isPresented: $showingRestoreOptions) {
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
                Text("How would you like to restore \(photosToRestore.count) item(s)?")
            }
            .sheet(isPresented: $showingPhotoViewer) {
                Group {
                    if let photo = selectedPhoto {
                        PhotoViewerSheet(photo: photo)
                    }
                }
            }
            .sheet(isPresented: $showingPhotosLibrary) {
                PhotosLibraryPicker()
            }
        }
    }
}
struct PhotoThumbnailView: View {
    let photo: SecurePhoto
    let isSelected: Bool
    let privacyModeEnabled: Bool
    @EnvironmentObject var vaultManager: VaultManager
    @State private var thumbnailImage: Image?
    @State private var loadTask: Task<Void, Never>?
    
    private var thumbnailSize: CGFloat {
#if os(iOS)
        return 120
#else
        return 180
#endif
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if privacyModeEnabled {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: thumbnailSize, height: thumbnailSize)
                        .overlay {
                            Image(systemName: photo.mediaType == .video ? "video.slash" : "lock.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                        )
                } else if let image = thumbnailImage {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: thumbnailSize, height: thumbnailSize)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                        )
                        .overlay(alignment: .bottomLeading) {
                            if photo.mediaType == .video {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.fill")
                                        .font(.caption2)
                                    if let duration = photo.duration {
                                        Text(formatDuration(duration))
                                            .font(.caption2)
                                    }
                                }
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(.black.opacity(0.6))
                                .cornerRadius(4)
                                .padding(6)
                            }
                        }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: thumbnailSize, height: thumbnailSize)
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
            .frame(width: thumbnailSize, alignment: .leading)
        }
        .onAppear {
            if !privacyModeEnabled {
                loadThumbnail()
            }
        }
        .onChange(of: privacyModeEnabled) {
            if !$0 && thumbnailImage == nil {
                loadThumbnail()
            }
        }
        .onDisappear {
            loadTask?.cancel()
        }
    }
    
    private func loadThumbnail() {
        loadTask = Task {
            do {
                let data = try vaultManager.decryptThumbnail(for: photo)
                
                if data.isEmpty {
                    print("Thumbnail data empty for photo id=\(photo.id), thumbnailPath=\(photo.thumbnailPath), encryptedThumb=\(photo.encryptedThumbnailPath ?? "nil")")
                    return
                }
                
                await MainActor.run {
#if os(macOS)
                    if let nsImage = NSImage(data: data) {
                        thumbnailImage = Image(nsImage: nsImage)
                    } else {
                        print("Failed to create NSImage from decrypted data for photo id=\(photo.id)")
                    }
#else
                    if let uiImage = UIImage(data: data) {
                        thumbnailImage = Image(uiImage: uiImage)
                    } else {
                        print("Failed to create UIImage from decrypted data for photo id=\(photo.id), size=\(data.count) bytes")
                    }
#endif
                }
            } catch {
                print("Error decrypting thumbnail for photo id=\(photo.id): \(error)")
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
}

struct PhotoViewerSheet: View {
    let photo: SecurePhoto
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var vaultManager: VaultManager
    @State private var fullImage: Image?
    @State private var videoURL: URL?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(photo.filename)
                        .font(.headline)
                    HStack {
                        if let album = photo.sourceAlbum {
                            Text("From: \(album)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if photo.mediaType == .video, let duration = photo.duration {
                            Text("• \(formatDuration(duration))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
            
            // Media content
            if photo.mediaType == .video {
                if let url = videoURL {
                    CustomVideoPlayer(url: url)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                if let image = fullImage {
                    GeometryReader { geometry in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 800, minHeight: 600)
#endif
        .onAppear {
            if photo.mediaType == .video {
                loadVideo()
            } else {
                loadFullImage()
            }
        }
        .onDisappear {
            cleanupVideo()
        }
    }
    
    private func loadFullImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let decryptedData = try? vaultManager.decryptPhoto(photo) {
#if os(macOS)
                if let image = NSImage(data: decryptedData) {
                    DispatchQueue.main.async {
                        fullImage = Image(nsImage: image)
                    }
                }
#else
                if let image = UIImage(data: decryptedData) {
                    DispatchQueue.main.async {
                        fullImage = Image(uiImage: image)
                    }
                }
#endif
            }
        }
    }
    
    private func loadVideo() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let decryptedData = try? vaultManager.decryptPhoto(photo) {
                // Write decrypted video to temp file
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(photo.id.uuidString + ".mov")
                do {
                    try decryptedData.write(to: tempURL)
                    DispatchQueue.main.async {
                        self.videoURL = tempURL
                    }
                } catch {
                    print("Failed to write temp video file: \(error)")
                }
            }
        }
    }
    
    private func cleanupVideo() {
        if let url = videoURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// Custom Video Player View
#if os(macOS)
struct CustomVideoPlayer: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = AVPlayer(url: url)
        playerView.controlsStyle = .floating
        playerView.showsFullScreenToggleButton = true
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Update if needed
    }
}
#else
struct CustomVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let playerViewController = AVPlayerViewController()
        playerViewController.player = AVPlayer(url: url)
        return playerViewController
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Update if needed
    }
}
#endif
