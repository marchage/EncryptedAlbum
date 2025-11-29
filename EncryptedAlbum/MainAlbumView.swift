import AVFoundation
import AVKit
import SwiftUI

#if os(macOS)
    import AppKit
#endif
#if os(iOS)
    import UIKit
    import Photos
#endif

struct MainAlbumView: View {
    @EnvironmentObject var albumManager: AlbumManager
    @ObservedObject var directImportProgress: DirectImportProgress

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
    @State private var showDeleteConfirmation = false
    @State private var showLargeDeleteConfirmation = false
    @State private var pendingDeletionContainsLargeFiles = false
    private var pendingLargeItemsSummary: String {
        // Build a compact summary of filenames and sizes for the alert (limit to first 6 items)
        let items = pendingDeletionPhotos
        guard !items.isEmpty else { return "" }

        var lines: [String] = []
        let maxShow = 6
        for (index, photo) in items.enumerated() {
            if index >= maxShow { break }
            let url = albumManager.urlForStoredPath(photo.encryptedDataPath)
            var sizeStr = "(missing)"
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path), let size = attrs[FileAttributeKey.size] as? Int64 {
                sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
            lines.append("• \(photo.filename) — \(sizeStr)")
        }

        if items.count > maxShow {
            lines.append("… and \(items.count - maxShow) more item(s)")
        }

        return lines.joined(separator: "\n")
    }
    @State private var pendingDeletionPhotos: [SecurePhoto] = []
    @State private var restorationTask: Task<Void, Never>? = nil
    @State private var didForcePrivacyModeThisSession = false
    @AppStorage("albumPrivacyModeEnabled") private var privacyModeEnabled: Bool = true
    @AppStorage("requireForegroundReauthentication") private var requireForegroundReauthentication: Bool = true
    @AppStorage("undoTimeoutSeconds") private var undoTimeoutSeconds: Double = 5.0
    @State private var isSearchActive = false
    @State private var isAppActive = true
    @State private var showingPreferences = false
    @State private var showLockdownTooltip: Bool = false
    @State private var animateLockdownPulse: Bool = false
    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #else
        @State private var pendingForegroundLockTask: Task<Void, Never>? = nil
    #endif
    @Environment(\.scenePhase) private var scenePhase

    private var actionIconFontSize: CGFloat {
        #if os(iOS)
            return verticalSizeClass == .regular ? 18 : 22
        #else
            return 16  // Reduced from 22 to prevent cropping on macOS
        #endif
    }

    private var actionButtonDimension: CGFloat {
        #if os(iOS)
            return verticalSizeClass == .regular ? 36 : 44
        #else
            return 44
        #endif
    }

    private var gridSpacing: CGFloat {
        #if os(iOS)
            return 1
        #else
            return 16
        #endif
    }

    private var gridMinimumItemWidth: CGFloat {
        #if os(iOS)
            return 80
        #else
            return 140
        #endif
    }

    var filteredPhotos: [SecurePhoto] {
        var photos = albumManager.hiddenPhotos

        // Filter by album
        if let album = selectedAlbum {
            photos = photos.filter { $0.albumAlbum == album }
        }

        // Filter by search
        if !searchText.isEmpty {
            photos = photos.filter { photo in
                photo.filename.localizedCaseInsensitiveContains(searchText)
                    || photo.sourceAlbum?.localizedCaseInsensitiveContains(searchText) == true
                    || photo.albumAlbum?.localizedCaseInsensitiveContains(searchText) == true
            }
        }

        return photos
    }

    var albumAlbums: [String] {
        let albums = Set(albumManager.hiddenPhotos.compactMap { $0.albumAlbum })
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

    // Small helper to apply the 'Winamp' theme when selected. This is intentionally
    // lightweight: it just picks a high-contrast accent color and a retro background.
    // The function previously returned `some ViewModifier` but used different concrete
    // modifier types in the branches which caused a compile-time mismatch. Create a
    // small type-erasing modifier and return that consistently.
    private struct AnyModifier: ViewModifier {
        private let _body: (Content) -> AnyView
        init<M: ViewModifier>(_ m: M) {
            self._body = { content in AnyView(content.modifier(m)) }
        }

        func body(content: Content) -> some View { _body(content) }
    }

    private func applyWinampThemeIfNeeded() -> AnyModifier {
        struct WinampModifier: ViewModifier {
            func body(content: Content) -> some View {
                content
                    .accentColor(Color(red: 0.85, green: 0.9, blue: 0.15))
            }
        }

        if albumManager.appTheme == "winamp" {
            return AnyModifier(WinampModifier())
        }
        return AnyModifier(IdentityModifier())
    }

    private struct IdentityModifier: ViewModifier {
        func body(content: Content) -> some View { content }
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

    func clearSelection() {
        selectedPhotos.removeAll()
    }

    func exportSelectedPhotos() {
        #if os(macOS)
            guard !albumManager.exportProgress.isExporting else {
                let alert = NSAlert()
                alert.messageText = "Export Already Running"
                alert.informativeText =
                    "Please wait for the current export to finish or cancel it before starting another."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }
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
        let photosToExport = albumManager.hiddenPhotos.filter { selectedPhotos.contains($0.id) }
        guard !photosToExport.isEmpty else { return }

        albumManager.startExport(photos: photosToExport, to: folderURL) { result in
            #if os(macOS)
                presentExportSummary(
                    successCount: result.successCount,
                    failureCount: result.failureCount,
                    canceled: result.wasCancelled,
                    destinationFolderName: folderURL.lastPathComponent,
                    error: result.error
                )
            #endif
            selectedPhotos.removeAll()
        }
    }

    // Helpers for banner icon and color (moved into MainAlbumView scope)
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

    private func hideNotificationAccessibilityLabel(note: HideNotification, hasUndo: Bool) -> String {
        var parts: [String] = []

        switch note.type {
        case .success:
            parts.append("Success notification")
        case .failure:
            parts.append("Failure notification")
        case .info:
            parts.append("Info notification")
        }

        parts.append(note.message)

        if hasUndo {
            parts.append("Undo available")
        }

        parts.append("Open Photos App button")

        return parts.joined(separator: ", ")
    }

    func restoreSelectedPhotos() {
        photosToRestore = albumManager.hiddenPhotos.filter { selectedPhotos.contains($0.id) }
        showingRestoreOptions = true
    }

    func restoreToOriginalAlbums() async {
        defer {
            Task { @MainActor in restorationTask = nil }
        }
        selectedPhotos.removeAll()
        do {
            try await albumManager.batchRestorePhotos(photosToRestore, restoreToSourceAlbum: true)
        } catch is CancellationError {
            AppLog.debugPublic("Restore canceled before completion")
        } catch {
            AppLog.error("Failed to restore photos: \(error.localizedDescription)")
        }
    }

    func restoreToNewAlbum() async {
        defer {
            Task { @MainActor in restorationTask = nil }
        }
        #if os(macOS)
            // Prompt for album name
            let alert = NSAlert()
            alert.messageText = "Create New Album"
            alert.informativeText = "Enter a name for the new album:"
            alert.alertStyle = .informational

            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            textField.placeholderString = "Album Name"
            // Use adaptive text color / appearance so the accessory field remains readable
            // on dark privacy backgrounds (e.g. Rainbow). Also disable the default background
            // to avoid an opaque white field on dark themes.
            textField.textColor = NSColor.labelColor
            textField.backgroundColor = .clear
            alert.accessoryView = textField

            alert.addButton(withTitle: "Create")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                let albumName = textField.stringValue
                if !albumName.isEmpty {
                    selectedPhotos.removeAll()
                    do {
                        try await albumManager.batchRestorePhotos(photosToRestore, toNewAlbum: albumName)
                    } catch is CancellationError {
                        AppLog.debugPublic("Restore canceled before completion")
                    } catch {
                        AppLog.error("Failed to restore photos: \(error.localizedDescription)")
                    }
                }
            }
        #endif
    }

    func restoreToLibrary() async {
        defer {
            Task { @MainActor in restorationTask = nil }
        }
        selectedPhotos.removeAll()
        do {
            try await albumManager.batchRestorePhotos(photosToRestore, restoreToSourceAlbum: false)
        } catch is CancellationError {
            AppLog.debugPublic("Restore canceled before completion")
        } catch {
            AppLog.error("Failed to restore photos: \(error.localizedDescription)")
        }
    }

    private func restoreSinglePhoto(_ photo: SecurePhoto) async {
        await restorePhotos([photo], toSourceAlbums: true)
    }

    private func restorePhotos(_ photos: [SecurePhoto], toSourceAlbums: Bool) async {
        guard !photos.isEmpty else { return }
        do {
            try await albumManager.batchRestorePhotos(photos, restoreToSourceAlbum: toSourceAlbums)
        } catch is CancellationError {
            AppLog.debugPublic("Restore canceled before completion")
        } catch {
            AppLog.error("Failed to restore photos: \(error.localizedDescription)")
        }
    }

    func deleteSelectedPhotos() {
        let photosToDelete: [SecurePhoto]
        if !pendingDeletionPhotos.isEmpty {
            photosToDelete = pendingDeletionPhotos
        } else {
            photosToDelete = albumManager.hiddenPhotos.filter { selectedPhotos.contains($0.id) }
        }

        guard !photosToDelete.isEmpty else { return }

        for photo in photosToDelete {
            albumManager.deletePhoto(photo)
        }

        let deletedIds = Set(photosToDelete.map { $0.id })
        selectedPhotos.subtract(deletedIds)
        pendingDeletionPhotos.removeAll()
    }

    private func requestDeletion(for photos: [SecurePhoto]) {
        guard !photos.isEmpty else { return }
        pendingDeletionPhotos = photos

        // Check the selected photos for large files that exceed secure delete cap.
        var foundLarge = false
            for photo in photos {
            let url = albumManager.urlForStoredPath(photo.encryptedDataPath)
            if FileManager.default.fileExists(atPath: url.path) {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                    let size = attrs[FileAttributeKey.size] as? Int64,
                    size > CryptoConstants.maxSecureDeleteSize
                {
                    foundLarge = true
                    break
                }
            }
        }

        pendingDeletionContainsLargeFiles = foundLarge
        if foundLarge {
            // Use a separate alert for large-file deletions so users are warned about the 100MB cap.
            showLargeDeleteConfirmation = true
        } else {
            showDeleteConfirmation = true
        }
    }

    func importFilesToAlbum() {
        #if os(macOS)
            guard !directImportProgress.isImporting else {
                showingFilePicker = false
                let alert = NSAlert()
                alert.messageText = "Import Already Running"
                alert.informativeText =
                    "Please wait for the current import to finish or cancel it before starting another."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }

            // Verify album is unlocked before starting import
            guard albumManager.isUnlocked else {
                showingFilePicker = false
                let alert = NSAlert()
                alert.messageText = "Album Not Unlocked"
                alert.informativeText = "Please unlock the album before importing files."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }

            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = true
            panel.allowedContentTypes = [.image, .movie, .video]
            panel.prompt = "Import"
            panel.message = "Choose photos or videos to import directly to album"

            panel.begin { response in
                showingFilePicker = false

                guard response == .OK else { return }

                let urls = panel.urls
                guard !urls.isEmpty else { return }
                albumManager.startDirectImport(urls: urls)
            }
        #endif
    }

    @discardableResult
    private func startRestorationTask(_ operation: @escaping () async -> Void) -> Bool {
        guard !albumManager.restorationProgress.isRestoring else {
            #if os(macOS)
                let alert = NSAlert()
                alert.messageText = "Restore Already Running"
                alert.informativeText =
                    "Please wait for the current restore to finish or cancel it before starting another."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            #else
                AppLog.debugPublic("Restore already in progress; ignoring additional request.")
            #endif
            return false
        }

        restorationTask?.cancel()
        restorationTask = Task(priority: .userInitiated) {
            await operation()
        }
        return true
    }

    #if os(macOS)
        @MainActor
        private func presentExportSummary(
            successCount: Int, failureCount: Int, canceled: Bool, destinationFolderName: String, error: Error?
        ) {
            let alert = NSAlert()
            if canceled {
                alert.messageText = "Export Canceled"
                alert.informativeText = "Exported \(successCount) item(s) before canceling."
                alert.alertStyle = .warning
            } else if failureCount == 0 {
                alert.messageText = "Export Successful"
                alert.informativeText = "Successfully exported \(successCount) item(s) to \(destinationFolderName)."
                alert.alertStyle = .informational
            } else if successCount == 0 {
                alert.messageText = "Export Failed"
                alert.informativeText =
                    "Failed to export \(failureCount) item(s). \(error?.localizedDescription ?? "Unknown error")"
                alert.alertStyle = .critical
            } else {
                alert.messageText = "Partial Export"
                var message = "Exported \(successCount) item(s), but \(failureCount) failed."
                if let description = error?.localizedDescription, !description.isEmpty {
                    message += "\n\(description)"
                }
                alert.informativeText = message
                alert.alertStyle = .warning
            }
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    #endif

    private func detailText(for index: Int, total: Int, sizeDescription: String?) -> String {
        var parts: [String] = ["Item \(index) of \(total)"]
        if let sizeDescription = sizeDescription {
            parts.append(sizeDescription)
        }
        return parts.joined(separator: " • ")
    }

    @ViewBuilder
    private var cameraSheet: some View {
        #if os(iOS)
            CameraCaptureView()
                .ignoresSafeArea()
                .onDisappear {
                    UltraPrivacyCoordinator.shared.endTrustedModal()
                }
        #else
            SecureWrapper {
                CameraCaptureView()
            }
        #endif
    }

    private var privacyCardVerticalPadding: CGFloat {
        #if os(iOS)
            return 6
        #else
            return 16
        #endif
    }

    @ViewBuilder
    private var toolbarActions: some View {
        // Visual indicator for Lockdown Mode — shown prominently to remind the user
        if albumManager.lockdownModeEnabled {
            // Present a tappable / clickable chip with clearer, high-contrast styling
            Button(action: {
                // Open preferences so users can see why Lockdown is active and change it
                showingPreferences = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.red))

                    Text("LOCKDOWN")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.red.opacity(0.6), lineWidth: 0.5)
                )
            }
            .accessibilityIdentifier("lockdownChipButton")
            .onChange(of: albumManager.lockdownModeEnabled) { newValue in
                // When lockdown is enabled for the first time, show a short popover/tooltip
                if newValue {
                    let seen = UserDefaults.standard.bool(forKey: "lockdownTooltipShown")
                    if !seen {
                        UserDefaults.standard.set(true, forKey: "lockdownTooltipShown")
                        // animate pulse and show tooltip briefly
                        animateLockdownPulse = true
                        showLockdownTooltip = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            animateLockdownPulse = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                            showLockdownTooltip = false
                        }
                    }
                }
            }
            .scaleEffect(animateLockdownPulse ? 1.06 : 1.0)
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Lockdown Mode enabled — tap to open Preferences")
            .accessibilityHint("Imports, exports and iCloud sync are disabled while Lockdown is active")
            #if os(macOS)
            .help("Lockdown Mode active — imports, exports and cloud operations are disabled. Click to open Preferences.")
            #endif
            // transient tooltip overlay (for iOS & macOS) shown once when Lockdown first enabled
            if showLockdownTooltip {
                Text("Lockdown Mode active — imports, exports and iCloud sync are disabled.")
                    .font(.caption2)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                    .offset(y: 40)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        // Indicator for when the app is preventing system sleep (e.g., during imports or
        // when user opts to keep screen awake while unlocked). Visible only on platforms
        // where system sleep is controllable (iOS).
        if albumManager.isSystemSleepPrevented {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.yellow.opacity(0.15)))

                if let label = albumManager.sleepPreventionReasonLabel {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Awake")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("sleepPreventionChip")
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            #if os(iOS)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .systemBackground).opacity(0.0001)))
            .accessibilityLabel("Preventing system sleep")
            #else
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: NSColor.windowBackgroundColor).opacity(0.0001)))
            .accessibilityLabel("Preventing system sleep")
            .help("Device will remain awake")
            #endif
        }
        Button {
            #if os(iOS)
                startPhotoLibraryFlow()
            #else
                showingPhotosLibrary = true
            #endif
        } label: {
            Image(systemName: "photo.fill.on.rectangle.fill")
        }
        .accessibilityLabel("Add Photos from Library")
        .accessibilityIdentifier("addPhotosButton")

        Button {
            #if os(iOS)
                startCameraCaptureFlow()
            #else
                showingCamera = true
            #endif
        } label: {
            Image(systemName: "camera.fill")
        }
        .accessibilityLabel("Capture Photo or Video")

        #if os(macOS)
            Button {
                showingFilePicker = true
            } label: {
                Label("Import Files", systemImage: "doc.badge.plus")
            }
            .disabled(directImportProgress.isImporting || albumManager.exportProgress.isExporting)
        #endif

        Menu {
            Button {
                albumManager.removeDuplicates()
            } label: {
                Label("Remove Duplicates", systemImage: "trash.slash")
            }

            Divider()

            Button {
                albumManager.lock(userInitiated: true)
            } label: {
                Label("Lock Album", systemImage: "lock.fill")
            }

            Button(action: {
                showingPreferences = true
            }) {
                Label("Settings", systemImage: "gear")
            }

            #if DEBUG
                Divider()
                Button(role: .destructive) {
                    resetAlbumForDevelopment()
                } label: {
                    Label("🔧 Reset Album (Dev)", systemImage: "trash.circle")
                }
            #endif
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More Options")
    }

    /// Compact cross-platform toolbar chip used to show short progress messages and a tiny
    /// activity indicator. Uses semantic colors and a translucent background so it remains
    /// readable on different title bar / toolbar backgrounds.
    @ViewBuilder
    private func toolbarProgressChip(isActive: Bool, message: String) -> some View {
        if isActive {
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .shadow(radius: 2)
        }
    }

    @ViewBuilder
    private var selectionToolbarControls: some View {
        Button {
            selectAll()
        } label: {
            Label {
                Text("All")
            } icon: {
                Image(systemName: "square.grid.2x2.fill")
            }
        }
        .disabled(filteredPhotos.isEmpty || selectedPhotos.count == filteredPhotos.count)
        .accessibilityLabel("Select all encrypted items")

        Button {
            clearSelection()
        } label: {
            Label {
                Text("None")
            } icon: {
                Image(systemName: "square.grid.2x2")
            }
        }
        .disabled(selectedPhotos.isEmpty)
        .accessibilityLabel("Deselect all encrypted items")
    }

    private var captureProgressOverlay: some View {
        ProgressOverlayView(
            title: "Encrypting items…",
            statusMessage: directImportProgress.statusMessage,
            detailMessage: directImportProgress.detailMessage,
            itemsProcessed: directImportProgress.itemsProcessed,
            totalItems: directImportProgress.itemsTotal,
            bytesProcessed: directImportProgress.bytesProcessed,
            totalBytes: directImportProgress.bytesTotal,
            cancelRequested: directImportProgress.cancelRequested,
            onCancel: {
                #if os(macOS)
                    albumManager.cancelDirectImport()
                #endif
            },
            isAppActive: isAppActive
        )
    }

    private var exportProgressOverlay: some View {
        ProgressOverlayView(
            title: "Exporting items…",
            statusMessage: albumManager.exportProgress.statusMessage,
            detailMessage: albumManager.exportProgress.detailMessage,
            itemsProcessed: albumManager.exportProgress.itemsProcessed,
            totalItems: albumManager.exportProgress.itemsTotal,
            bytesProcessed: albumManager.exportProgress.bytesProcessed,
            totalBytes: albumManager.exportProgress.bytesTotal,
            cancelRequested: albumManager.exportProgress.cancelRequested,
            onCancel: {
                albumManager.cancelExport()
            },
            isAppActive: isAppActive
        )
    }

    private var restorationProgressOverlay: some View {
        ProgressOverlayView(
            title: "Restoring items…",
            statusMessage: albumManager.restorationProgress.statusMessage,
            detailMessage: albumManager.restorationProgress.detailMessage,
            itemsProcessed: albumManager.restorationProgress.processedItems,
            totalItems: albumManager.restorationProgress.totalItems,
            bytesProcessed: albumManager.restorationProgress.currentBytesProcessed,
            totalBytes: albumManager.restorationProgress.currentBytesTotal,
            cancelRequested: albumManager.restorationProgress.cancelRequested,
            onCancel: {
                Task { @MainActor in
                    guard !albumManager.restorationProgress.cancelRequested else { return }
                    albumManager.restorationProgress.cancelRequested = true
                    let status = albumManager.restorationProgress.statusMessage
                    if status.isEmpty || !status.lowercased().contains("cancel") {
                        albumManager.restorationProgress.statusMessage = "Canceling restore…"
                    }
                    if albumManager.restorationProgress.detailMessage.isEmpty {
                        albumManager.restorationProgress.detailMessage = "Finishing current item"
                    }
                    restorationTask?.cancel()
                }
            },
            successCount: albumManager.restorationProgress.successItems,
            failureCount: albumManager.restorationProgress.failedItems,
            isAppActive: isAppActive
        )
    }

    #if DEBUG
        func resetAlbumForDevelopment() {
            #if os(macOS)
                let alert = NSAlert()
                alert.messageText = "Reset Album? (Development)"
                alert.informativeText =
                    "This will delete all album data, the password, and return to setup. This action cannot be undone."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "Reset Album")
                alert.addButton(withTitle: "Cancel")

                if alert.runModal() == .alertFirstButtonReturn {
                    // Delete all album files
                    let fileManager = FileManager.default
                    let albumDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                        .appendingPathComponent("EncryptedAlbum")

                    if let albumDirectory = albumDirectory {
                        try? fileManager.removeItem(at: albumDirectory)
                    }

                    // Delete password hash
                    UserDefaults.standard.removeObject(forKey: "passwordHash")

                    // Delete Keychain entry
                    let query: [String: Any] = [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrService as String: "biz.front-end.encryptedalbum.password",
                    ]
                    SecItemDelete(query as CFDictionary)

                    // Lock the album which will trigger setup. Treat as user-initiated to
                    // avoid auto-biometric prompting on the unlock screen immediately.
                    albumManager.lock(userInitiated: true)
                }
            #endif
        }
    #endif

    var body: some View {
        let navigationContent = ZStack {
            PrivacyOverlayBackground(asBackground: true)
            mainContent
                .scrollContentBackground(.hidden)
                .background(Color.clear)
        }
        .background(Color.clear)
        .navigationTitle("Encrypted Album")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    selectionToolbarControls
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Progress chip (import / decrypt / restore) — shown when any long operation is active
                    toolbarProgressChip(
                        isActive: albumManager.viewerProgress.isDecrypting || directImportProgress.isImporting || albumManager.exportProgress.isExporting || albumManager.restorationProgress.isRestoring,
                        message: albumManager.viewerProgress.isDecrypting ? (albumManager.viewerProgress.statusMessage.isEmpty ? (albumManager.viewerProgress.bytesTotal > 0 ? String(format: "Decrypting… %d%%", Int(albumManager.viewerProgress.percentComplete * 100)) : "Decrypting…") : (albumManager.viewerProgress.bytesTotal > 0 ? String(format: "%@ — %d%%", albumManager.viewerProgress.statusMessage, Int(albumManager.viewerProgress.percentComplete * 100)) : albumManager.viewerProgress.statusMessage)) : (directImportProgress.isImporting ? (directImportProgress.statusMessage.isEmpty ? "Importing…" : directImportProgress.statusMessage) : (albumManager.exportProgress.isExporting ? (albumManager.exportProgress.statusMessage.isEmpty ? "Decrypting…" : albumManager.exportProgress.statusMessage) : (albumManager.restorationProgress.isRestoring ? (albumManager.restorationProgress.statusMessage.isEmpty ? "Restoring…" : albumManager.restorationProgress.statusMessage) : "")))
                    )
                    toolbarActions
                }
            }
            .searchable(
                text: $searchText, isPresented: $isSearchActive,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Search encrypted items"
            )
            .onChange(of: isSearchActive) { newValue in
                if !newValue {
                    dismissKeyboard()
                }
            }
        #else
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    selectionToolbarControls
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    toolbarProgressChip(
                        isActive: albumManager.viewerProgress.isDecrypting || directImportProgress.isImporting || albumManager.exportProgress.isExporting || albumManager.restorationProgress.isRestoring,
                        message: albumManager.viewerProgress.isDecrypting ? (albumManager.viewerProgress.statusMessage.isEmpty ? (albumManager.viewerProgress.bytesTotal > 0 ? String(format: "Decrypting… %d%%", Int(albumManager.viewerProgress.percentComplete * 100)) : "Decrypting…") : (albumManager.viewerProgress.bytesTotal > 0 ? String(format: "%@ — %d%%", albumManager.viewerProgress.statusMessage, Int(albumManager.viewerProgress.percentComplete * 100)) : albumManager.viewerProgress.statusMessage)) : (directImportProgress.isImporting ? (directImportProgress.statusMessage.isEmpty ? "Importing…" : directImportProgress.statusMessage) : (albumManager.exportProgress.isExporting ? (albumManager.exportProgress.statusMessage.isEmpty ? "Decrypting…" : albumManager.exportProgress.statusMessage) : (albumManager.restorationProgress.isRestoring ? (albumManager.restorationProgress.statusMessage.isEmpty ? "Restoring…" : albumManager.restorationProgress.statusMessage) : "")))
                    )
                    toolbarActions
                }
            }
            .searchable(text: $searchText, prompt: "Search encrypted items")
        #endif
        .scrollDismissesKeyboard(.interactively)

        let baseView = NavigationStack {
            navigationContent
        }
        .background(Color.clear)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        // Apply Winamp theme modifier if selected — small accent tweak
        .modifier(applyWinampThemeIfNeeded())

        let viewWithInitialModifiers = baseView
            .onAppear {
                if !didForcePrivacyModeThisSession {
                    // Ensure privacy mode starts enabled on each fresh app launch.
                    privacyModeEnabled = true
                    didForcePrivacyModeThisSession = true
                }
                // Album view appeared
                selectedPhotos.removeAll()
                setupKeyboardShortcuts()
                // albumManager.touchActivity() - removed
            }
            .alert("Restore Items", isPresented: $showingRestoreOptions) {
                Button("Restore to Original Albums") {
                    startRestorationTask {
                        await restoreToOriginalAlbums()
                    }
                }
                Button("Restore to New Album") {
                    startRestorationTask {
                        await restoreToNewAlbum()
                    }
                }
                Button("Just Add to Library") {
                    startRestorationTask {
                        await restoreToLibrary()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("How would you like to restore \(photosToRestore.count) item(s)?")
            }
            .sheet(item: $selectedPhoto) { photo in
                PhotoViewerSheet(photo: photo)
            }
            #if os(iOS)
                .fullScreenCover(isPresented: $showingPreferences) {
                    ZStack(alignment: .top) {
                        PreferencesView()
                            .environmentObject(albumManager)
                        NotificationBannerView().environmentObject(albumManager)
                    }
                }
            #else
                .sheet(isPresented: $showingPreferences) {
                    ZStack(alignment: .top) {
                        PreferencesView(isPresented: $showingPreferences)
                            .environmentObject(albumManager)
                        NotificationBannerView().environmentObject(albumManager)
                    }
                }
            #endif
            #if os(iOS)
                .fullScreenCover(isPresented: $showingPhotosLibrary) {
                    ZStack(alignment: .top) {
                        PhotosLibraryPicker()
                            .environmentObject(albumManager)
                        NotificationBannerView().environmentObject(albumManager)
                    }
                }
            #else
                .sheet(isPresented: $showingPhotosLibrary) {
                    ZStack(alignment: .top) {
                        PhotosLibraryPicker()
                            .environmentObject(albumManager)
                        NotificationBannerView().environmentObject(albumManager)
                    }
                }
            #endif
            #if os(iOS)
                .fullScreenCover(isPresented: $showingCamera) {
                    ZStack(alignment: .top) {
                        CameraCaptureView()
                        NotificationBannerView().environmentObject(albumManager)
                    }
                }
            #else
                .sheet(isPresented: $showingCamera) {
                    ZStack(alignment: .top) {
                        CameraCaptureView()
                        NotificationBannerView().environmentObject(albumManager)
                    }
                }
            #endif
            .confirmationDialog(
                "Delete selected items?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(
                    "Delete \(pendingDeletionPhotos.count) item\(pendingDeletionPhotos.count == 1 ? "" : "s")",
                    role: .destructive
                ) {
                    deleteSelectedPhotos()
                }
                Button("Cancel", role: .cancel) {
                    pendingDeletionPhotos.removeAll()
                }
            } message: {
                Text("This action permanently removes the selected content from Encrypted Album.")
            }

            // Large-delete confirmation: show file names & sizes + explain the secure-delete cap and require explicit confirmation
            .alert("Delete large items?", isPresented: $showLargeDeleteConfirmation) {
                Button("Delete Anyway", role: .destructive) {
                    // Proceed with deletion even when files are large
                    deleteSelectedPhotos()
                }
                Button("Cancel", role: .cancel) {
                    pendingDeletionPhotos.removeAll()
                    pendingDeletionContainsLargeFiles = false
                }
            } message: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("One or more selected items are larger than \(ByteCountFormatter.string(fromByteCount: CryptoConstants.maxSecureDeleteSize, countStyle: .file)). Secure deletion will only overwrite the first \(ByteCountFormatter.string(fromByteCount: CryptoConstants.maxSecureDeleteSize, countStyle: .file)) (3 passes). On modern APFS/SSD devices this may not physically erase the file — confirm you want to permanently delete these items.")
                    if !pendingLargeItemsSummary.isEmpty {
                        Divider()
                        Text(pendingLargeItemsSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .onChange(of: showDeleteConfirmation) { presented in
                if presented {
                    albumManager.suspendIdleTimer(reason: .prompt)
                } else {
                    albumManager.resumeIdleTimer(reason: .prompt)
                }
            }
            .onChange(of: showingFilePicker) { newValue in
                if newValue {
                    importFilesToAlbum()
                }
            }
            #if os(iOS)
                .onChange(of: showingCamera) { isPresented in
                    if !isPresented {
                        UltraPrivacyCoordinator.shared.endTrustedModal()
                    }
                }
                .onChange(of: showingPhotosLibrary) { isPresented in
                    if !isPresented {
                        UltraPrivacyCoordinator.shared.endTrustedModal()
                    }
                }
            #endif
            .onDrop(of: ["public.file-url", "public.image"], isTargeted: nil) { providers in
                Task {
                    await handleDrop(providers: providers)
                }
                return true
            }
        let showDirectImportProgress = directImportProgress.isImporting && (directImportProgress.itemsTotal > 0 || directImportProgress.bytesProcessed > 0 || directImportProgress.bytesTotal > 0 || directImportProgress.cancelRequested)
        let viewWithOverlays = viewWithInitialModifiers
            .overlay {
                if showDirectImportProgress {
                    captureProgressOverlay
                }
            }
            .overlay {
                if albumManager.exportProgress.isExporting {
                    exportProgressOverlay
                }
            }
            .overlay {
                if albumManager.restorationProgress.isRestoring {
                    restorationProgressOverlay
                }
            }
            .overlay {
                // When the search UI is active, allow taps on the content area to dismiss it.
                #if os(iOS)
                if isSearchActive {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation {
                                isSearchActive = false
                                dismissKeyboard()
                            }
                        }
                }
                #endif
            }
        #if os(macOS)
        return viewWithOverlays
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                guard requireForegroundReauthentication else { return }
                guard !shouldSuppressForegroundLock else {
                    cancelScheduledForegroundLock()
                    return
                }
                scheduleForegroundAutoLock()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                cancelScheduledForegroundLock()
            }
            .onDisappear {
                cancelScheduledForegroundLock()
            }
            .onChange(of: showingPhotosLibrary) { isPresented in
                if isPresented {
                    cancelScheduledForegroundLock()
                }
            }
            .onChange(of: showingFilePicker) { isPresented in
                if isPresented {
                    cancelScheduledForegroundLock()
                }
            }
            .onChange(of: showingCamera) { isPresented in
                if isPresented {
                    cancelScheduledForegroundLock()
                }
            }
            .onChange(of: albumManager.importProgress.isImporting) { importing in
                if importing {
                    cancelScheduledForegroundLock()
                }
            }
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
        return viewWithOverlays
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    isAppActive = true
                } else if newPhase == .background {
                    isAppActive = false
                    if requireForegroundReauthentication {
                        let shouldSuppress =
                            showingPhotosLibrary || showingCamera || albumManager.importProgress.isImporting
                            || directImportProgress.isImporting || albumManager.exportProgress.isExporting
                        if !shouldSuppress {
                            albumManager.lock()
                        }
                    }
                } else if newPhase == .inactive {
                    isAppActive = false
                }
            }
        #endif
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                selectionBar
                privacySection
                NotificationBannerView().environmentObject(albumManager)
                if albumManager.hiddenPhotos.isEmpty {
                    emptyState
                } else {
                    PhotoGridView(
                        photos: filteredPhotos,
                        selectedPhotos: $selectedPhotos,
                        privacyModeEnabled: privacyModeEnabled,
                        gridMinimumItemWidth: gridMinimumItemWidth,
                        gridSpacing: gridSpacing,
                        onSelect: toggleSelection,
                        onDoubleTap: { selectedPhoto = $0 },
                        onRestore: { photo in startRestorationTask { await restoreSinglePhoto(photo) } },
                        onDelete: { requestDeletion(for: [$0]) }
                    )
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }

    private var selectionBar: some View {
        Group {
            if !selectedPhotos.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text("\(selectedPhotos.count) selected")
                            .font(.headline)
                            .lineLimit(1)
                            .layoutPriority(1)
                        Spacer(minLength: 8)
                        HStack(spacing: 8) {
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
                                .disabled(albumManager.exportProgress.isExporting)
                            #endif
                            Button(role: .destructive) {
                                let photosToDelete: [SecurePhoto] = albumManager.hiddenPhotos.filter {
                                    selectedPhotos.contains($0.id)
                                }
                                requestDeletion(for: photosToDelete)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .lineLimit(1)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding()
                .privacyCardStyle()
            }
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Label(
                    privacyModeEnabled ? "Privacy Mode On" : "Privacy Mode Off",
                    systemImage: privacyModeEnabled ? "eye.slash.fill" : "eye.fill"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: $privacyModeEnabled)
                    .labelsHidden()
            }

            #if os(macOS)
                HStack(spacing: 12) {
                    Button {
                        showingPhotosLibrary = true
                    } label: {
                        Label("Photos", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showingFilePicker = true
                    } label: {
                        Label("Files", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        directImportProgress.isImporting || albumManager.exportProgress.isExporting)

                    Button {
                        showingCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera.fill")
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.small)
            #endif
        }
        .padding(.horizontal)
        .padding(.vertical, privacyCardVerticalPadding)
        .privacyCardStyle()
    }

    // Notification banner moved into the reusable `NotificationBannerView` component.

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Encrypted Items")
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
    }

    // Helper view to reduce type-checking complexity in MainAlbumView
    struct PhotoGridView: View {
        let photos: [SecurePhoto]
        @Binding var selectedPhotos: Set<UUID>
        let privacyModeEnabled: Bool
        let gridMinimumItemWidth: CGFloat
        let gridSpacing: CGFloat
        let onSelect: (UUID) -> Void
        let onDoubleTap: (SecurePhoto) -> Void
        let onRestore: (SecurePhoto) -> Void
        let onDelete: (SecurePhoto) -> Void

        var body: some View {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: gridMinimumItemWidth, maximum: 200), spacing: gridSpacing)
                ], spacing: gridSpacing
            ) {
                ForEach(photos) { photo in
                    Button {
                        onSelect(photo.id)
                    } label: {
                        PhotoThumbnailView(
                            photo: photo, isSelected: selectedPhotos.contains(photo.id),
                            privacyModeEnabled: privacyModeEnabled)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .highPriorityGesture(
                        TapGesture(count: 2).onEnded {
                            onDoubleTap(photo)
                        }
                    )
                    .contextMenu {
                        Button {
                            onRestore(photo)
                        } label: {
                            Label("Restore to Library", systemImage: "arrow.uturn.backward")
                        }

                        Divider()

                        Button(role: .destructive) {
                            onDelete(photo)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, gridSpacing)
        }
    }
}

// The real shared `NotificationBannerView` lives in
// `NotificationBannerView.swift`. Remove the fallback duplicate here to avoid
// redeclaration when the shared view is included in the build.
#if os(iOS)
    extension MainAlbumView {
        private func startCameraCaptureFlow() {
            Task { @MainActor in
                await presentCameraCaptureFlow()
            }
        }

        private func startPhotoLibraryFlow() {
            Task { @MainActor in
                await presentPhotoLibraryFlow()
            }
        }

        @MainActor
        private func presentCameraCaptureFlow() async {
            let coordinator = UltraPrivacyCoordinator.shared
            coordinator.beginTrustedModal()

            let cameraGranted = await MediaPermissionHelper.ensureCameraAccess()
            guard cameraGranted else {
                coordinator.endTrustedModal()
                showPermissionDenied(
                    "Camera access is required to capture new photos or videos.")
                return
            }

            let microphoneGranted = await MediaPermissionHelper.ensureMicrophoneAccess()
            guard microphoneGranted else {
                coordinator.endTrustedModal()
                showPermissionDenied(
                    "Microphone access is required to record audio when capturing album videos.")
                return
            }

            showingCamera = true
        }

        @MainActor
        private func presentPhotoLibraryFlow() async {
            let granted = await MediaPermissionHelper.ensurePhotoLibraryAccess()
            guard granted else {
                showPermissionDenied(
                    "Photos access is required to import from your library.")
                return
            }

            showingPhotosLibrary = true
        }

        @MainActor
        private func showPermissionDenied(_ message: String) {
            albumManager.hideNotification = HideNotification(message: message, type: .failure, photos: nil)
        }
    }

    private enum MediaPermissionHelper {
        static func ensureCameraAccess() async -> Bool {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                return true
            case .denied, .restricted:
                return false
            case .notDetermined:
                return await withCheckedContinuation { continuation in
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        continuation.resume(returning: granted)
                    }
                }
            @unknown default:
                return false
            }
        }

        static func ensureMicrophoneAccess() async -> Bool {
            let session = AVAudioSession.sharedInstance()
            switch session.recordPermission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                return await withCheckedContinuation { continuation in
                    session.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            @unknown default:
                return false
            }
        }

        static func ensurePhotoLibraryAccess() async -> Bool {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            switch status {
            case .authorized, .limited:
                return true
            case .denied, .restricted:
                return false
            case .notDetermined:
                return await withCheckedContinuation { continuation in
                    PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                        continuation.resume(returning: newStatus == .authorized || newStatus == .limited)
                    }
                }
            @unknown default:
                return false
            }
        }
    }
#endif
#if os(macOS)
    extension MainAlbumView {
        /// Schedule a short-delay auto lock so quick Command-Tabs don't immediately force re-auth.
        private func scheduleForegroundAutoLock() {
            guard !shouldSuppressForegroundLock else { return }
            cancelScheduledForegroundLock()
            pendingForegroundLockTask = Task {
                let grace: TimeInterval = 1.5
                try? await Task.sleep(nanoseconds: UInt64(grace * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard requireForegroundReauthentication, !shouldSuppressForegroundLock else { return }
                    if albumManager.isUnlocked {
                        albumManager.lock()
                    }
                }
            }
        }

        private func cancelScheduledForegroundLock() {
            pendingForegroundLockTask?.cancel()
            pendingForegroundLockTask = nil
        }

        private var shouldSuppressForegroundLock: Bool {
            showingPhotosLibrary
                || showingFilePicker
                || showingCamera
                || albumManager.importProgress.isImporting
                || directImportProgress.isImporting
                || albumManager.exportProgress.isExporting
        }
    }
#endif

// PhotoThumbnailView moved to PhotoThumbnailView.swift

// PhotoViewerSheet moved to PhotoViewerSheet.swift

// decryptingPlaceholder moved to PhotoViewerSheet.swift

// CustomVideoPlayer moved to CustomVideoPlayer.swift

#if os(iOS)
    extension View {
        func dismissKeyboard() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

            // Force end editing on all windows to ensure keyboard dismissal
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .forEach { $0.endEditing(true) }
        }
    }
#endif

extension MainAlbumView {
    @MainActor
    private func handleDrop(providers: [NSItemProvider]) async {
        guard albumManager.isUnlocked else {
            #if os(macOS)
                let alert = NSAlert()
                alert.messageText = "Album Locked"
                alert.informativeText = "Please unlock Encrypted Album before importing items."
                alert.runModal()
            #endif
            return
        }

        var urls: [URL] = []

        for provider in providers {
            var handled = false
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                do {
                    let url = try await loadURL(from: provider)
                    if let url = url {
                        urls.append(url)
                        handled = true
                    }
                } catch {
                    AppLog.error("Failed to load dropped URL: \(error.localizedDescription)")
                }
            }

            #if os(macOS)
                if !handled && provider.canLoadObject(ofClass: NSImage.self) {
                    do {
                        let image = try await loadObject(from: provider, ofClass: NSImage.self)
                        if let image = image,
                            let tiffData = image.tiffRepresentation,
                            let bitmap = NSBitmapImageRep(data: tiffData),
                            let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
                        {
                            let filename = "Dropped Image \(Date().timeIntervalSince1970).jpg"
                            try await albumManager.hidePhoto(imageData: jpegData, filename: filename)
                        }
                    } catch {
                        AppLog.error("Failed to load dropped image: \(error.localizedDescription)")
                    }
                }
            #endif
        }

        if !urls.isEmpty {
            albumManager.startDirectImport(urls: urls)
        }
    }

    private func loadURL(from provider: NSItemProvider) async throws -> URL? {
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    #if os(macOS)
        private func loadObject<T: NSItemProviderReading>(from provider: NSItemProvider, ofClass: T.Type) async throws
            -> T?
        {
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadObject(ofClass: ofClass) { object, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: object as? T)
                    }
                }
            }
        }
    #endif
}
