import SwiftUI
import AVKit
#if os(macOS)
import AppKit
#endif

struct MainVaultView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @State private var showingPhotosLibrary = false
    @State private var selectedPhoto: SecurePhoto?
    @State private var selectedPhotos: Set<UUID> = []
    @State private var searchText = ""
    @State private var selectedAlbum: String? = nil
    @State private var showingAlbumSheet = false
    @State private var newAlbumName = ""
    @State private var showingRestoreOptions = false
    @State private var photosToRestore: [SecurePhoto] = []
    @State private var showingCamera = false
    @State private var showingFilePicker = false
    @AppStorage("vaultPrivacyModeEnabled") private var privacyModeEnabled: Bool = true
    @AppStorage("undoTimeoutSeconds") private var undoTimeoutSeconds: Double = 5.0
#if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
#endif
    
    private var actionIconFontSize: CGFloat {
#if os(iOS)
        return verticalSizeClass == .regular ? 18 : 22
#else
        return 16  // Reduced from 22 to prevent cropping on macOS
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
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder to export \(selectedPhotos.count) item(s) to"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                exportPhotos(to: url)
            }
        }
#endif
    }
    
    func exportPhotos(to folderURL: URL) {
        let photosToExport = vaultManager.hiddenPhotos.filter { selectedPhotos.contains($0.id) }
        
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                var successCount = 0
                var failureCount = 0
                var lastError: Error?
                
                for photo in photosToExport {
                    do {
                        let decryptedData = try await vaultManager.decryptPhoto(photo)
                        let fileURL = folderURL.appendingPathComponent(photo.filename)
                        try decryptedData.write(to: fileURL)
                        print("✅ Exported: \(photo.filename)")
                        successCount += 1
                    } catch {
                        print("❌ Failed to export \(photo.filename): \(error)")
                        failureCount += 1
                        lastError = error
                    }
                }
                
                await MainActor.run {
                    selectedPhotos.removeAll()
                    
#if os(macOS)
                    // Show result alert
                    let alert = NSAlert()
                    if failureCount == 0 {
                        alert.messageText = "Export Successful"
                        alert.informativeText = "Successfully exported \(successCount) item(s) to \(folderURL.lastPathComponent)"
                        alert.alertStyle = .informational
                    } else if successCount == 0 {
                        alert.messageText = "Export Failed"
                        alert.informativeText = "Failed to export \(failureCount) item(s). \(lastError?.localizedDescription ?? "Unknown error")"
                        alert.alertStyle = .critical
                    } else {
                        alert.messageText = "Partial Export"
                        alert.informativeText = "Exported \(successCount) item(s), but \(failureCount) failed. \(lastError?.localizedDescription ?? "")"
                        alert.alertStyle = .warning
                    }
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
#endif
                }
            }
        }
    }
    
    // Helpers for banner icon and color (moved into MainVaultView scope)
    func iconName(for type: HideNotificationType) -> String {
        switch type {
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "xmark.octagon.fill"
        case .info:
            return "info.circle.fill"
        }
    }
    
    func iconColor(for type: HideNotificationType) -> Color {
        switch type {
        case .success:
            return Color.green
        case .failure:
            return Color.red
        case .info:
            return Color.gray
        }
    }
    
    func restoreSelectedPhotos() {
        photosToRestore = vaultManager.hiddenPhotos.filter { selectedPhotos.contains($0.id) }
        showingRestoreOptions = true
    }
    
    func restoreToOriginalAlbums() async {
        selectedPhotos.removeAll()
        do {
            try await vaultManager.batchRestorePhotos(photosToRestore, restoreToSourceAlbum: true)
        } catch {
            print("Failed to restore photos: \(error)")
        }
    }
    
    func restoreToNewAlbum() async {
#if os(macOS)
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
                do {
                    try await vaultManager.batchRestorePhotos(photosToRestore, toNewAlbum: albumName)
                } catch {
                    print("Failed to restore photos: \(error)")
                }
            }
        }
#endif
    }
    
    func restoreToLibrary() async {
        selectedPhotos.removeAll()
        try? await vaultManager.batchRestorePhotos(photosToRestore, restoreToSourceAlbum: false)
    }
    
    func deleteSelectedPhotos() {
        selectedPhotos.removeAll()
        let photosToDelete = vaultManager.hiddenPhotos.filter { selectedPhotos.contains($0.id) }
        for photo in photosToDelete {
            vaultManager.deletePhoto(photo)
        }
        selectedPhotos.removeAll()
    }
    
    func importFilesToVault() {
#if os(macOS)
        // vaultManager.touchActivity() - removed
        
        let warningAlert = NSAlert()
        warningAlert.messageText = "Capture Directly to Vault"
        warningAlert.informativeText = "Photos/videos imported this way are stored ONLY in the encrypted vault. They will NOT be in your Photos Library or iCloud Photos. Make sure your vault is backed up!"
        warningAlert.alertStyle = .warning
        warningAlert.addButton(withTitle: "Continue")
        warningAlert.addButton(withTitle: "Cancel")
        
        guard warningAlert.runModal() == .alertFirstButtonReturn else {
            showingFilePicker = false
            return
        }
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .movie, .video]
        panel.prompt = "Import"
        panel.message = "Choose photos or videos to import directly to vault"
        
        panel.begin { response in
            showingFilePicker = false
            
            guard response == .OK else { return }
            
            let urls = panel.urls
            DispatchQueue.global(qos: .userInitiated).async {
                var successCount = 0
                var failureCount = 0
                
                for url in urls {
                    do {
                        let data = try Data(contentsOf: url)
                        let filename = url.lastPathComponent
                        
                        let isVideo = url.pathExtension.lowercased() == "mov" ||
                                     url.pathExtension.lowercased() == "mp4" ||
                                     url.pathExtension.lowercased() == "m4v"
                        
                        Task {
                            try await vaultManager.hidePhoto(
                                imageData: data,
                                filename: filename,
                                sourceAlbum: "Captured to Vault",
                                mediaType: isVideo ? .video : .photo,
                                duration: nil
                            )
                        }
                        
                        print("✅ Imported to vault: \(filename)")
                        successCount += 1
                    } catch {
                        print("❌ Failed to import \(url.lastPathComponent): \(error)")
                        failureCount += 1
                    }
                }
                
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    if failureCount == 0 {
                        alert.messageText = "Import Successful"
                        alert.informativeText = "Imported \(successCount) item(s) directly to encrypted vault."
                        alert.alertStyle = .informational
                    } else if successCount == 0 {
                        alert.messageText = "Import Failed"
                        alert.informativeText = "Failed to import \(failureCount) item(s)."
                        alert.alertStyle = .critical
                    } else {
                        alert.messageText = "Partial Import"
                        alert.informativeText = "Imported \(successCount) item(s), but \(failureCount) failed."
                        alert.alertStyle = .warning
                    }
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
#endif
    }
    
    func chooseVaultLocation() {
#if os(macOS)
        // Step-up authentication before allowing vault location change
        vaultManager.requireStepUpAuthentication { success in
            guard success else { return }
            
            // vaultManager.touchActivity() - removed
            
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
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !selectedPhotos.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("\(selectedPhotos.count) selected")
                                .font(.headline)
                            HStack(spacing: 12) {
                                Button {
                                    restoreSelectedPhotos()
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
#if os(macOS)
                                Button {
                                    exportSelectedPhotos()
                                } label: {
                                    Label("Export", systemImage: "square.and.arrow.up")
                                }
#endif
                                Button(role: .destructive) {
                                    deleteSelectedPhotos()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 12) {
                            Label(privacyModeEnabled ? "Privacy Mode On" : "Privacy Mode Off",
                                  systemImage: privacyModeEnabled ? "eye.slash.fill" : "eye.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Toggle("", isOn: $privacyModeEnabled)
                                .labelsHidden()
                        }

                        HStack(spacing: 12) {
                            Button {
                                showingPhotosLibrary = true
                            } label: {
                                Label("Import", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)

#if os(iOS)
                            Button {
                                showingCamera = true
                            } label: {
                                Label("Capture", systemImage: "camera.fill")
                            }
                            .buttonStyle(.bordered)
#else
                            Button {
                                showingFilePicker = true
                            } label: {
                                Label("Capture", systemImage: "camera.fill")
                            }
                            .buttonStyle(.bordered)
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
                                Label("More", systemImage: "ellipsis")
                            }
                            .buttonStyle(.bordered)
                        }
                        .controlSize(.small)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    if let note = vaultManager.hideNotification {
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
                                        Task {
                                            for photo in validPhotos {
                                                try? await vaultManager.restorePhotoToLibrary(photo)
                                            }
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
                                    if note.type == .success {
                                        Color.green.opacity(0.14)
                                    } else if note.type == .failure {
                                        Color.red.opacity(0.14)
                                    } else {
                                        Color.gray.opacity(0.12)
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
                        .background(.blue.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

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
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: actionIconFontSize))
                                    .foregroundColor(.white)
                                    .frame(width: actionButtonDimension, height: actionButtonDimension)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue))
                                Text("Import from Photos")
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
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)], spacing: 16) {
                            ForEach(filteredPhotos) { photo in
                                Button {
                                    print("[DEBUG] Thumbnail single-click: id=\(photo.id)")
                                    toggleSelection(photo.id)
                                } label: {
                                    PhotoThumbnailView(photo: photo, isSelected: selectedPhotos.contains(photo.id), privacyModeEnabled: privacyModeEnabled)
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                                .highPriorityGesture(TapGesture(count: 2).onEnded {
                                    print("[DEBUG] Thumbnail double-click: id=\(photo.id)")
                                    selectedPhoto = photo
                                })
                                .contextMenu {
                                    Button {
                                        Task {
                                            try? await vaultManager.restorePhotoToLibrary(photo)
                                        }
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
                        .padding(.horizontal, 4)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Hidden Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showingPhotosLibrary = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }

#if os(iOS)
                    Button {
                        showingCamera = true
                    } label: {
                        Image(systemName: "camera.fill")
                    }
#else
                    Button {
                        showingFilePicker = true
                    } label: {
                        Image(systemName: "camera.fill")
                    }
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
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search hidden items")
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            print("DEBUG MainVaultView.onAppear: hiddenPhotos.count = \(vaultManager.hiddenPhotos.count)")
            print("DEBUG MainVaultView.onAppear: isUnlocked = \(vaultManager.isUnlocked)")
            print("DEBUG MainVaultView.onAppear: filteredPhotos.count = \(filteredPhotos.count)")
            selectedPhotos.removeAll()
            setupKeyboardShortcuts()
            // vaultManager.touchActivity() - removed
        }
        .alert("Restore Items", isPresented: $showingRestoreOptions) {
            Button("Restore to Original Albums") {
                Task { await restoreToOriginalAlbums() }
            }
            Button("Restore to New Album") {
                Task { await restoreToNewAlbum() }
            }
            Button("Just Add to Library") {
                Task { await restoreToLibrary() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("How would you like to restore \(photosToRestore.count) item(s)?")
        }
        .sheet(item: $selectedPhoto) { photo in
            PhotoViewerSheet(photo: photo)
        }
        .sheet(isPresented: $showingPhotosLibrary) {
            PhotosLibraryPicker()
        }
#if os(iOS)
        .sheet(isPresented: $showingCamera) {
            CameraCaptureView()
                .ignoresSafeArea()
        }
#endif
        .onChange(of: showingFilePicker) { newValue in
            if newValue {
                importFilesToVault()
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
    @State private var failedToLoad: Bool = false
    
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
                } else if failedToLoad {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: thumbnailSize, height: thumbnailSize)
                        .overlay {
                            Image(systemName: photo.mediaType == .video ? "video.slash" : "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                        )
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
        .onChange(of: privacyModeEnabled) { newValue in
            if !newValue && thumbnailImage == nil {
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
                let data = try await vaultManager.decryptThumbnail(for: photo)
                
                if data.isEmpty {
                    print("Thumbnail data empty for photo id=\(photo.id), thumbnailPath=\(photo.thumbnailPath), encryptedThumb=\(photo.encryptedThumbnailPath ?? "nil")")
                    await MainActor.run {
                        failedToLoad = true
                    }
                    return
                }
                
                await MainActor.run {
#if os(macOS)
                    if let nsImage = NSImage(data: data) {
                        thumbnailImage = Image(nsImage: nsImage)
                    } else {
                        print("Failed to create NSImage from decrypted data for photo id=\(photo.id)")
                        failedToLoad = true
                    }
#else
                    if let uiImage = UIImage(data: data) {
                        thumbnailImage = Image(uiImage: uiImage)
                    } else {
                        print("Failed to create UIImage from decrypted data for photo id=\(photo.id), size=\(data.count) bytes")
                        failedToLoad = true
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
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            print("[DEBUG] PhotoViewerSheet onAppear for photo id=\(photo.id)")
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
        Task {
            do {
                let decryptedData = try await vaultManager.decryptPhoto(photo)
#if os(macOS)
                if let image = NSImage(data: decryptedData) {
                    await MainActor.run {
                        fullImage = Image(nsImage: image)
                    }
                }
#else
                if let image = UIImage(data: decryptedData) {
                    await MainActor.run {
                        fullImage = Image(uiImage: image)
                    }
                }
#endif
            } catch {
                print("Failed to decrypt photo: \(error)")
            }
        }
    }
    
    private func loadVideo() {
        Task {
            do {
                let decryptedData = try await vaultManager.decryptPhoto(photo)
                // Write decrypted video to temp file
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(photo.id.uuidString + ".mov")
                try decryptedData.write(to: tempURL)
                await MainActor.run {
                    self.videoURL = tempURL
                }
            } catch {
                print("Failed to decrypt video: \(error)")
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

