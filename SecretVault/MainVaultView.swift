import AVKit
import SwiftUI

#if os(macOS)
    import AppKit
#endif
#if os(iOS)
    import UIKit
#endif

struct MainVaultView: View {
    @EnvironmentObject var vaultManager: VaultManager

    private struct RestorationProgressOverlayView: View {
        @ObservedObject var progress: RestorationProgress
        let cancelAction: () -> Void

        var body: some View {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    if progress.totalItems > 0 {
                        ProgressView(value: Double(progress.processedItems), total: Double(max(progress.totalItems, 1)))
                            .progressViewStyle(.linear)
                            .frame(maxWidth: UIConstants.progressCardWidth)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .frame(maxWidth: UIConstants.progressCardWidth)
                    }

                    if progress.currentBytesTotal > 0 {
                        ProgressView(
                            value: Double(progress.currentBytesProcessed),
                            total: Double(max(progress.currentBytesTotal, 1))
                        )
                        .progressViewStyle(.linear)
                        .frame(maxWidth: UIConstants.progressCardWidth)
                        Text(
                            "\(formattedBytes(progress.currentBytesProcessed)) of \(formattedBytes(progress.currentBytesTotal))"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    } else if progress.currentBytesProcessed > 0 {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .frame(maxWidth: UIConstants.progressCardWidth)
                        Text("\(formattedBytes(progress.currentBytesProcessed)) processed…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .frame(maxWidth: UIConstants.progressCardWidth)
                        Text("Preparing file size…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(progress.statusMessage.isEmpty ? "Restoring items…" : progress.statusMessage)
                        .font(.headline)

                    if progress.totalItems > 0 {
                        Text("\(progress.processedItems) of \(progress.totalItems)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if progress.successItems > 0 || progress.failedItems > 0 {
                        Text("\(progress.successItems) restored • \(progress.failedItems) failed")
                            .font(.caption2)
                            .foregroundStyle(progress.failedItems > 0 ? Color.orange : .secondary)
                    }

                    if !progress.detailMessage.isEmpty {
                        Text(progress.detailMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if progress.cancelRequested {
                        Text("Cancel requested… finishing current item")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    Button("Cancel Restore") {
                        cancelAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(progress.cancelRequested)
                }
                .padding(24)
                .frame(maxWidth: UIConstants.progressCardWidth)
                .background(.ultraThickMaterial)
                .cornerRadius(16)
                .shadow(radius: 18)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(restorationAccessibilityLabel)
                .accessibilityHint("Restore progress")
                .accessibilityAddTraits(.isModal)
            }
            .transition(.opacity)
        }

        private func formattedBytes(_ value: Int64) -> String {
            guard value > 0 else { return "0 bytes" }
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: value)
        }

        private var restorationAccessibilityLabel: String {
            var parts: [String] = [progress.statusMessage.isEmpty ? "Restoring items" : progress.statusMessage]

            if progress.totalItems > 0 {
                parts.append("\(progress.processedItems) of \(progress.totalItems) items")
            }

            if progress.currentBytesTotal > 0 {
                parts.append(
                    "\(formattedBytes(progress.currentBytesProcessed)) of \(formattedBytes(progress.currentBytesTotal)) processed"
                )
            } else if progress.currentBytesProcessed > 0 {
                parts.append("\(formattedBytes(progress.currentBytesProcessed)) processed")
            }

            if progress.successItems > 0 || progress.failedItems > 0 {
                parts.append("\(progress.successItems) restored, \(progress.failedItems) failed")
            }

            if progress.cancelRequested {
                parts.append("Cancellation requested")
            }

            if !progress.detailMessage.isEmpty {
                parts.append(progress.detailMessage)
            }

            return parts.joined(separator: ", ")
        }
    }
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
    @State private var captureInProgress = false
    @State private var captureStatusMessage = ""
    @State private var captureDetailMessage = ""
    @State private var captureItemsProcessed = 0
    @State private var captureItemsTotal = 0
    @State private var captureTask: Task<Void, Never>? = nil
    @State private var captureCancelRequested = false
    @State private var captureBytesProcessed: Int64 = 0
    @State private var captureBytesTotal: Int64 = 0
    @State private var exportInProgress = false
    @State private var showDeleteConfirmation = false
    @State private var pendingDeletionPhotos: [SecurePhoto] = []
    @State private var exportStatusMessage = ""
    @State private var exportDetailMessage = ""
    @State private var exportItemsProcessed = 0
    @State private var exportItemsTotal = 0
    @State private var exportTask: Task<Void, Never>? = nil
    @State private var exportCancelRequested = false
    @State private var exportBytesProcessed: Int64 = 0
    @State private var exportBytesTotal: Int64 = 0
    @State private var restorationTask: Task<Void, Never>? = nil
    @State private var didForcePrivacyModeThisSession = false
    @AppStorage("vaultPrivacyModeEnabled") private var privacyModeEnabled: Bool = true
    @AppStorage("requireForegroundReauthentication") private var requireForegroundReauthentication: Bool = true
    @AppStorage("undoTimeoutSeconds") private var undoTimeoutSeconds: Double = 5.0
    @State private var isSearchActive = false
    @State private var isAppActive = true
    @State private var isChoosingVaultLocation = false
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

    var filteredPhotos: [SecurePhoto] {
        var photos = vaultManager.hiddenPhotos

        // Filter by album
        if let album = selectedAlbum {
            photos = photos.filter { $0.vaultAlbum == album }
        }

        // Filter by search
        if !searchText.isEmpty {
            photos = photos.filter { photo in
                photo.filename.localizedCaseInsensitiveContains(searchText)
                    || photo.sourceAlbum?.localizedCaseInsensitiveContains(searchText) == true
                    || photo.vaultAlbum?.localizedCaseInsensitiveContains(searchText) == true
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

    func clearSelection() {
        selectedPhotos.removeAll()
    }

    func exportSelectedPhotos() {
        #if os(macOS)
            guard !exportInProgress else {
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
        let photosToExport = vaultManager.hiddenPhotos.filter { selectedPhotos.contains($0.id) }
        guard !photosToExport.isEmpty else { return }
        exportTask?.cancel()
        exportTask = Task(priority: .userInitiated) {
            await runExportOperation(photos: photosToExport, to: folderURL)
        }
    }

    private func runExportOperation(photos: [SecurePhoto], to folderURL: URL) async {
        guard !photos.isEmpty else {
            await MainActor.run { exportTask = nil }
            return
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file

        await MainActor.run {
            exportInProgress = true
            exportItemsTotal = photos.count
            exportItemsProcessed = 0
            exportStatusMessage = "Preparing export…"
            exportDetailMessage = "\(photos.count) item(s)"
            exportBytesProcessed = 0
            exportBytesTotal = 0
            exportCancelRequested = false
        }

        var successCount = 0
        var failureCount = 0
        var firstError: Error?
        var wasCancelled = false
        let fileManager = FileManager.default

        for (index, photo) in photos.enumerated() {
            if Task.isCancelled {
                wasCancelled = true
                break
            }

            let expectedSize = photo.fileSize
            let expectedSizeText = expectedSize > 0 ? formatter.string(fromByteCount: expectedSize) : nil
            await MainActor.run {
                exportStatusMessage = "Decrypting \(photo.filename)…"
                exportDetailMessage = detailText(for: index + 1, total: photos.count, sizeDescription: expectedSizeText)
                exportItemsProcessed = index
                exportBytesProcessed = 0
                exportBytesTotal = expectedSize
            }

            var destinationURL: URL?

            do {
                let tempURL = try await vaultManager.decryptPhotoToTemporaryURL(photo)
                defer { try? fileManager.removeItem(at: tempURL) }

                destinationURL = folderURL.appendingPathComponent(photo.filename)

                if fileManager.fileExists(atPath: destinationURL!.path) {
                    try fileManager.removeItem(at: destinationURL!)
                }

                let fileSizeValue = fileSizeValue(for: tempURL)
                let sizeText = fileSizeValue > 0 ? formatter.string(fromByteCount: fileSizeValue) : nil
                let detail = detailText(for: index + 1, total: photos.count, sizeDescription: sizeText)

                await MainActor.run {
                    exportStatusMessage = "Exporting \(photo.filename)…"
                    exportDetailMessage = detail
                    exportItemsProcessed = index
                    exportBytesTotal = fileSizeValue
                    exportBytesProcessed = 0
                }

                try Task.checkCancellation()
                try await copyFileWithProgress(from: tempURL, to: destinationURL!, fileSize: fileSizeValue)
                successCount += 1
            } catch is CancellationError {
                wasCancelled = true
                if let destinationURL = destinationURL {
                    try? fileManager.removeItem(at: destinationURL)
                }
                break
            } catch {
                if let destinationURL = destinationURL {
                    try? fileManager.removeItem(at: destinationURL)
                }
                failureCount += 1
                if firstError == nil {
                    firstError = error
                }
                await MainActor.run {
                    exportStatusMessage = "Failed \(photo.filename)"
                    exportDetailMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                exportItemsProcessed = index + 1
                exportBytesProcessed = exportBytesTotal
            }
        }

        if Task.isCancelled {
            wasCancelled = true
        }

        await MainActor.run {
            exportInProgress = false
            exportItemsProcessed = 0
            exportItemsTotal = 0
            exportStatusMessage = ""
            exportDetailMessage = ""
            exportBytesProcessed = 0
            exportBytesTotal = 0
            exportCancelRequested = false
            exportTask = nil
            selectedPhotos.removeAll()
        }

        #if os(macOS)
            await MainActor.run {
                presentExportSummary(
                    successCount: successCount,
                    failureCount: failureCount,
                    canceled: wasCancelled,
                    destinationFolderName: folderURL.lastPathComponent,
                    error: firstError
                )
            }
        #endif
    }

    private func fileSizeValue(for url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? NSNumber
        else {
            return 0
        }
        return size.int64Value
    }

    private func copyFileWithProgress(from sourceURL: URL, to destinationURL: URL, fileSize: Int64) async throws {
        let chunkSize = 1_048_576  // 1 MB
        let inputHandle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? inputHandle.close() }

        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: destinationURL)
        defer { try? outputHandle.close() }

        var totalCopied: Int64 = 0

        while true {
            try Task.checkCancellation()
            guard let data = try inputHandle.read(upToCount: chunkSize), !data.isEmpty else {
                break
            }
            try outputHandle.write(contentsOf: data)
            totalCopied += Int64(data.count)
            await MainActor.run {
                exportBytesProcessed = totalCopied
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
        photosToRestore = vaultManager.hiddenPhotos.filter { selectedPhotos.contains($0.id) }
        showingRestoreOptions = true
    }

    func restoreToOriginalAlbums() async {
        defer {
            Task { @MainActor in restorationTask = nil }
        }
        selectedPhotos.removeAll()
        do {
            try await vaultManager.batchRestorePhotos(photosToRestore, restoreToSourceAlbum: true)
        } catch is CancellationError {
            print("Restore canceled before completion")
        } catch {
            print("Failed to restore photos: \(error)")
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
            alert.accessoryView = textField

            alert.addButton(withTitle: "Create")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                let albumName = textField.stringValue
                if !albumName.isEmpty {
                    selectedPhotos.removeAll()
                    do {
                        try await vaultManager.batchRestorePhotos(photosToRestore, toNewAlbum: albumName)
                    } catch is CancellationError {
                        print("Restore canceled before completion")
                    } catch {
                        print("Failed to restore photos: \(error)")
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
            try await vaultManager.batchRestorePhotos(photosToRestore, restoreToSourceAlbum: false)
        } catch is CancellationError {
            print("Restore canceled before completion")
        } catch {
            print("Failed to restore photos: \(error)")
        }
    }

    private func restoreSinglePhoto(_ photo: SecurePhoto) async {
        await restorePhotos([photo], toSourceAlbums: true)
    }

    private func restorePhotos(_ photos: [SecurePhoto], toSourceAlbums: Bool) async {
        guard !photos.isEmpty else { return }
        do {
            try await vaultManager.batchRestorePhotos(photos, restoreToSourceAlbum: toSourceAlbums)
        } catch is CancellationError {
            print("Restore canceled before completion")
        } catch {
            print("Failed to restore photos: \(error)")
        }
    }

    func deleteSelectedPhotos() {
        let photosToDelete: [SecurePhoto]
        if !pendingDeletionPhotos.isEmpty {
            photosToDelete = pendingDeletionPhotos
        } else {
            photosToDelete = vaultManager.hiddenPhotos.filter { selectedPhotos.contains($0.id) }
        }

        guard !photosToDelete.isEmpty else { return }

        for photo in photosToDelete {
            vaultManager.deletePhoto(photo)
        }

        let deletedIds = Set(photosToDelete.map { $0.id })
        selectedPhotos.subtract(deletedIds)
        pendingDeletionPhotos.removeAll()
    }

    private func requestDeletion(for photos: [SecurePhoto]) {
        guard !photos.isEmpty else { return }
        pendingDeletionPhotos = photos
        showDeleteConfirmation = true
    }

    func importFilesToVault() {
        #if os(macOS)
            guard !captureInProgress else {
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
            // vaultManager.touchActivity() - removed

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
                startDirectCaptureImport(with: urls)
            }
        #endif
    }

    private func startDirectCaptureImport(with urls: [URL]) {
        #if os(macOS)
            guard !urls.isEmpty else { return }
            captureTask?.cancel()
            captureTask = Task(priority: .userInitiated) {
                await runDirectCaptureImport(urls: urls)
            }
        #endif
    }

    @discardableResult
    private func startRestorationTask(_ operation: @escaping () async -> Void) -> Bool {
        guard !vaultManager.restorationProgress.isRestoring else {
            #if os(macOS)
                let alert = NSAlert()
                alert.messageText = "Restore Already Running"
                alert.informativeText =
                    "Please wait for the current restore to finish or cancel it before starting another."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            #else
                print("Restore already in progress; ignoring additional request.")
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
        private func runDirectCaptureImport(urls: [URL]) async {
            guard !urls.isEmpty else {
                await MainActor.run {
                    captureTask = nil
                }
                return
            }

            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
            formatter.countStyle = .file

            await MainActor.run {
                captureInProgress = true
                captureItemsTotal = urls.count
                captureItemsProcessed = 0
                captureStatusMessage = "Preparing import…"
                captureDetailMessage = "\(urls.count) item(s)"
                captureCancelRequested = false
                captureBytesProcessed = 0
                captureBytesTotal = 0
            }

            var successCount = 0
            var failureCount = 0
            var firstError: String?
            var wasCancelled = false
            let fileManager = FileManager.default

            for (index, url) in urls.enumerated() {
                if Task.isCancelled {
                    wasCancelled = true
                    break
                }

                let filename = url.lastPathComponent
                let sizeText = fileSizeString(for: url, formatter: formatter)
                let detail = detailText(for: index + 1, total: urls.count, sizeDescription: sizeText)

                var fileSizeValue: Int64 = 0
                if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                    let fileSizeNumber = attributes[.size] as? NSNumber
                {
                    fileSizeValue = fileSizeNumber.int64Value
                }

                if fileSizeValue > CryptoConstants.maxMediaFileSize {
                    failureCount += 1
                    if firstError == nil {
                        let humanSize = formatter.string(fromByteCount: fileSizeValue)
                        let limitString = formatter.string(fromByteCount: CryptoConstants.maxMediaFileSize)
                        firstError = "\(filename) exceeds the \(limitString) limit (\(humanSize))."
                    }
                    await MainActor.run {
                        captureStatusMessage = "Skipping \(filename)…"
                        let limitString = formatter.string(fromByteCount: CryptoConstants.maxMediaFileSize)
                        captureDetailMessage = "File exceeds \(limitString) limit"
                        captureItemsProcessed = index + 1
                        captureBytesTotal = fileSizeValue
                        captureBytesProcessed = fileSizeValue
                    }
                    continue
                }

                await MainActor.run {
                    captureStatusMessage = "Encrypting \(filename)…"
                    captureDetailMessage = detail
                    captureItemsProcessed = index
                    captureBytesTotal = fileSizeValue
                    captureBytesProcessed = 0
                }

                do {
                    try Task.checkCancellation()
                    let mediaType: MediaType = isVideoFile(url) ? .video : .photo
                    try await vaultManager.hidePhoto(
                        mediaSource: .fileURL(url),
                        filename: filename,
                        dateTaken: nil,
                        sourceAlbum: "Captured to Vault",
                        assetIdentifier: nil,
                        mediaType: mediaType,
                        duration: nil,
                        location: nil,
                        isFavorite: nil,
                        progressHandler: { bytesRead in
                            await MainActor.run {
                                captureBytesProcessed = bytesRead
                            }
                        }
                    )
                    successCount += 1
                } catch is CancellationError {
                    wasCancelled = true
                    break
                } catch {
                    failureCount += 1
                    if firstError == nil {
                        firstError = "\(filename): \(error.localizedDescription)"
                    }
                }

                await MainActor.run {
                    captureItemsProcessed = index + 1
                    captureBytesProcessed = captureBytesTotal
                }
            }

            if Task.isCancelled {
                wasCancelled = true
            }

            await MainActor.run {
                captureInProgress = false
                captureDetailMessage = ""
                captureStatusMessage = ""
                captureItemsProcessed = 0
                captureItemsTotal = 0
                captureTask = nil
                captureCancelRequested = false
                captureBytesProcessed = 0
                captureBytesTotal = 0
            }

            await MainActor.run {
                presentCaptureSummary(
                    successCount: successCount,
                    failureCount: failureCount,
                    canceled: wasCancelled,
                    errorMessage: firstError
                )
            }
        }

        @MainActor
        private func presentCaptureSummary(successCount: Int, failureCount: Int, canceled: Bool, errorMessage: String?)
        {
            let alert = NSAlert()
            if canceled {
                alert.messageText = "Import Canceled"
                alert.informativeText = "Encrypted \(successCount) item(s) before canceling."
                alert.alertStyle = .warning
            } else if failureCount == 0 {
                alert.messageText = "Import Complete"
                alert.informativeText = "Encrypted \(successCount) item(s) into the vault."
                alert.alertStyle = .informational
            } else if successCount == 0 {
                alert.messageText = "Import Failed"
                alert.informativeText = errorMessage ?? "Unable to import the selected files."
                alert.alertStyle = .critical
            } else {
                alert.messageText = "Import Completed with Issues"
                var summary = "Imported \(successCount) item(s); \(failureCount) failed."
                if let errorMessage = errorMessage, !errorMessage.isEmpty {
                    summary += "\n\(errorMessage)"
                }
                alert.informativeText = summary
                alert.alertStyle = .warning
            }
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }

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

    private func fileSizeString(for url: URL, formatter: ByteCountFormatter) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? NSNumber
        else {
            return nil
        }
        return formatter.string(fromByteCount: size.int64Value)
    }

    private func detailText(for index: Int, total: Int, sizeDescription: String?) -> String {
        var parts: [String] = ["Item \(index) of \(total)"]
        if let sizeDescription = sizeDescription {
            parts.append(sizeDescription)
        }
        return parts.joined(separator: " • ")
    }

    private func isVideoFile(_ url: URL) -> Bool {
        let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "mpg", "mpeg", "hevc", "webm"]
        return videoExtensions.contains(url.pathExtension.lowercased())
    }

    private func formattedBytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: value)
    }

    private var captureProgressAccessibilityLabel: String {
        var parts: [String] = [captureStatusMessage.isEmpty ? "Encrypting items" : captureStatusMessage]

        if captureItemsTotal > 0 {
            parts.append("\(captureItemsProcessed) of \(captureItemsTotal) items")
        }

        if captureBytesTotal > 0 {
            parts.append(
                "\(formattedBytes(captureBytesProcessed)) of \(formattedBytes(captureBytesTotal)) processed"
            )
        } else if captureBytesProcessed > 0 {
            parts.append("\(formattedBytes(captureBytesProcessed)) processed")
        }

        if !captureDetailMessage.isEmpty {
            parts.append(captureDetailMessage)
        }

        if captureCancelRequested {
            parts.append("Cancellation requested")
        }

        return parts.joined(separator: ", ")
    }

    private var exportProgressAccessibilityLabel: String {
        var parts: [String] = [exportStatusMessage.isEmpty ? "Exporting items" : exportStatusMessage]

        if exportItemsTotal > 0 {
            parts.append("\(exportItemsProcessed) of \(exportItemsTotal) items")
        }

        if exportBytesTotal > 0 {
            parts.append(
                "\(formattedBytes(exportBytesProcessed)) of \(formattedBytes(exportBytesTotal)) processed"
            )
        } else if exportBytesProcessed > 0 {
            parts.append("\(formattedBytes(exportBytesProcessed)) processed")
        }

        if !exportDetailMessage.isEmpty {
            parts.append(exportDetailMessage)
        }

        if exportCancelRequested {
            parts.append("Cancellation requested")
        }

        return parts.joined(separator: ", ")
    }

    func chooseVaultLocation() {
        #if os(macOS)
            isChoosingVaultLocation = true
            // Step-up authentication before allowing vault location change
            vaultManager.requireStepUpAuthentication { success in
                guard success else {
                    isChoosingVaultLocation = false
                    return
                }

                // vaultManager.touchActivity() - removed

                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.prompt = "Choose"
                panel.message = "Select the folder where SecretVault should store its encrypted vault."

                panel.begin { response in
                    guard response == .OK, let baseURL = panel.url else {
                        isChoosingVaultLocation = false
                        return
                    }

                    // Ask for explicit confirmation and explain implications
                    let confirmAlert = NSAlert()
                    confirmAlert.messageText = "Change Vault Location?"
                    confirmAlert.informativeText =
                        "SecretVault will copy your existing encrypted vault to a new 'SecretVault' folder inside the selected location. If the folder is in iCloud Drive or another synced location, the encrypted vault files (including encrypted thumbnails and metadata) will be synced there. The old vault folder will be left in place so you can clean it up manually."
                    confirmAlert.alertStyle = .warning
                    confirmAlert.addButton(withTitle: "Move Vault")
                    confirmAlert.addButton(withTitle: "Cancel")

                    let response = confirmAlert.runModal()
                    guard response == .alertFirstButtonReturn else {
                        isChoosingVaultLocation = false
                        return
                    }

                    vaultManager.moveVault(to: baseURL) { result in
                        isChoosingVaultLocation = false
                        if case .failure(let error) = result {
                            let errorAlert = NSAlert()
                            errorAlert.messageText = "Failed to Move Vault"
                            errorAlert.informativeText =
                                "SecretVault could not copy your vault to the new location. Your existing vault remains at its previous location. Error: \(error.localizedDescription)"
                            errorAlert.alertStyle = .critical
                            errorAlert.addButton(withTitle: "OK")
                            errorAlert.runModal()
                        }
                    }
                }
            }
        #endif
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
        Button {
            showingPhotosLibrary = true
        } label: {
            Image(systemName: "photo.fill.on.rectangle.fill")
        }
        .accessibilityLabel("Add Photos from Library")
        .accessibilityIdentifier("addPhotosButton")

        Button {
            #if os(iOS)
                UltraPrivacyCoordinator.shared.beginTrustedModal()
            #endif
            showingCamera = true
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
            .disabled(captureInProgress || exportInProgress)
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
        .accessibilityLabel("More Options")
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
        .accessibilityLabel("Select all hidden items")

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
        .accessibilityLabel("Deselect all hidden items")
    }

    private var captureProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                if captureItemsTotal > 0 {
                    ProgressView(value: Double(captureItemsProcessed), total: Double(max(captureItemsTotal, 1)))
                        .progressViewStyle(.linear)
                        .frame(maxWidth: UIConstants.progressCardWidth)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(maxWidth: UIConstants.progressCardWidth)
                }

                if captureBytesTotal > 0 {
                    ProgressView(value: Double(captureBytesProcessed), total: Double(max(captureBytesTotal, 1)))
                        .progressViewStyle(.linear)
                        .frame(maxWidth: UIConstants.progressCardWidth)
                    
                    if isAppActive {
                        Text("\(formattedBytes(captureBytesProcessed)) of \(formattedBytes(captureBytesTotal))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        let percent = Double(captureBytesProcessed) / Double(max(captureBytesTotal, 1))
                        Text(String(format: "%.0f%%", percent * 100))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if captureBytesProcessed > 0 {
                    Text("\(formattedBytes(captureBytesProcessed)) processed…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(isAppActive ? (captureStatusMessage.isEmpty ? "Encrypting items…" : captureStatusMessage) : "Encrypting items…")
                    .font(.headline)

                if captureItemsTotal > 0 {
                    Text("\(captureItemsProcessed) of \(captureItemsTotal)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !captureDetailMessage.isEmpty && isAppActive {
                    Text(captureDetailMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if captureCancelRequested {
                    Text("Cancel requested… finishing current file")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Button("Cancel Import") {
                    captureCancelRequested = true
                    captureStatusMessage = "Canceling import…"
                    captureDetailMessage = "Finishing current file"
                    captureTask?.cancel()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(captureCancelRequested)
            }
            .padding(24)
            .frame(maxWidth: UIConstants.progressCardWidth)
            .background(.ultraThickMaterial)
            .cornerRadius(16)
            .shadow(radius: 18)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(captureProgressAccessibilityLabel)
            .accessibilityHint("Import progress")
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
    }

    private var exportProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                if exportItemsTotal > 0 {
                    ProgressView(value: Double(exportItemsProcessed), total: Double(max(exportItemsTotal, 1)))
                        .progressViewStyle(.linear)
                        .frame(maxWidth: UIConstants.progressCardWidth)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(maxWidth: UIConstants.progressCardWidth)
                }

                if exportBytesTotal > 0 {
                    ProgressView(value: Double(exportBytesProcessed), total: Double(max(exportBytesTotal, 1)))
                        .progressViewStyle(.linear)
                        .frame(maxWidth: UIConstants.progressCardWidth)
                    
                    if isAppActive {
                        Text("\(formattedBytes(exportBytesProcessed)) of \(formattedBytes(exportBytesTotal))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        let percent = Double(exportBytesProcessed) / Double(max(exportBytesTotal, 1))
                        Text(String(format: "%.0f%%", percent * 100))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(maxWidth: UIConstants.progressCardWidth)
                    Text(
                        exportBytesProcessed > 0
                            ? "\(formattedBytes(exportBytesProcessed)) processed…" : "Preparing file size…"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Text(exportStatusMessage.isEmpty ? "Exporting items…" : exportStatusMessage)
                    .font(.headline)

                if exportItemsTotal > 0 {
                    Text("\(exportItemsProcessed) of \(exportItemsTotal)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !exportDetailMessage.isEmpty {
                    Text(exportDetailMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if exportCancelRequested {
                    Text("Cancel requested… finishing current file")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Button("Cancel Export") {
                    exportCancelRequested = true
                    exportStatusMessage = "Canceling export…"
                    if exportDetailMessage.isEmpty {
                        exportDetailMessage = "Finishing current file"
                    }
                    exportTask?.cancel()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(exportCancelRequested)
            }
            .padding(24)
            .frame(maxWidth: UIConstants.progressCardWidth)
            .background(.ultraThickMaterial)
            .cornerRadius(16)
            .shadow(radius: 18)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(exportProgressAccessibilityLabel)
            .accessibilityHint("Export progress")
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
    }

    private var restorationProgressOverlay: some View {
        RestorationProgressOverlayView(
            progress: vaultManager.restorationProgress,
            cancelAction: {
                Task { @MainActor in
                    guard !vaultManager.restorationProgress.cancelRequested else { return }
                    vaultManager.restorationProgress.cancelRequested = true
                    let status = vaultManager.restorationProgress.statusMessage
                    if status.isEmpty || !status.lowercased().contains("cancel") {
                        vaultManager.restorationProgress.statusMessage = "Canceling restore…"
                    }
                    if vaultManager.restorationProgress.detailMessage.isEmpty {
                        vaultManager.restorationProgress.detailMessage = "Finishing current item"
                    }
                    restorationTask?.cancel()
                }
            }
        )
    }

    #if DEBUG
        func resetVaultForDevelopment() {
            #if os(macOS)
                let alert = NSAlert()
                alert.messageText = "Reset Vault? (Development)"
                alert.informativeText =
                    "This will delete all vault data, the password, and return to setup. This action cannot be undone."
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
                        kSecAttrService as String: "com.secretvault.password",
                    ]
                    SecItemDelete(query as CFDictionary)

                    // Lock the vault which will trigger setup
                    vaultManager.lock()
                }
            #endif
        }
    #endif

    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 12) {
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
                                            .disabled(exportInProgress)
                                        #endif
                                        Button(role: .destructive) {
                                            let photosToDelete = vaultManager.hiddenPhotos.filter {
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
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

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

                            HStack(alignment: .top, spacing: 12) {
                                Label(
                                    requireForegroundReauthentication
                                        ? "Re-authentication Required" : "Re-authentication Optional",
                                    systemImage: "lock.rotation"
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                Spacer()
                                Toggle("", isOn: $requireForegroundReauthentication)
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
                                    .disabled(captureInProgress || exportInProgress)

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
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        if let note = vaultManager.hideNotification {
                            let validPhotos =
                                note.photos?.filter { returned in
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
                                            if startRestorationTask({
                                                await restorePhotos(validPhotos, toSourceAlbums: true)
                                            }) {
                                                withAnimation {
                                                    vaultManager.hideNotification = nil
                                                }
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
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(
                                    hideNotificationAccessibilityLabel(note: note, hasUndo: !validPhotos.isEmpty)
                                )
                                .accessibilityHint("Hide status banner")
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
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)], spacing: 16
                            ) {
                                ForEach(filteredPhotos) { photo in
                                    Button {
                                        toggleSelection(photo.id)
                                    } label: {
                                        PhotoThumbnailView(
                                            photo: photo, isSelected: selectedPhotos.contains(photo.id),
                                            privacyModeEnabled: privacyModeEnabled)
                                    }
                                    .buttonStyle(.plain)
                                    .focusable(false)
                                    .highPriorityGesture(
                                        TapGesture(count: 2).onEnded {
                                            selectedPhoto = photo
                                        }
                                    )
                                    .contextMenu {
                                        Button {
                                            startRestorationTask {
                                                await restoreSinglePhoto(photo)
                                            }
                                        } label: {
                                            Label("Restore to Library", systemImage: "arrow.uturn.backward")
                                        }

                                        Divider()

                                        Button(role: .destructive) {
                                            requestDeletion(for: [photo])
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
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItemGroup(placement: .navigationBarLeading) {
                            selectionToolbarControls
                        }
                        ToolbarItemGroup(placement: .navigationBarTrailing) {
                            toolbarActions
                        }
                    }
                    .searchable(
                        text: $searchText, isPresented: $isSearchActive, placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: "Search hidden items")
                    .onChange(of: isSearchActive) { _, newValue in
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
                            toolbarActions
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search hidden items")
                #endif
                .scrollDismissesKeyboard(.interactively)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                if !didForcePrivacyModeThisSession {
                    // Ensure privacy mode starts enabled on each fresh app launch.
                    privacyModeEnabled = true
                    didForcePrivacyModeThisSession = true
                }
                // Vault view appeared
                selectedPhotos.removeAll()
                setupKeyboardShortcuts()
                // vaultManager.touchActivity() - removed
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
            .sheet(isPresented: $showingPhotosLibrary) {
                PhotosLibraryPicker()
            }
            .sheet(isPresented: $showingCamera) {
                cameraSheet
            }
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
                Text("This action permanently removes the selected content from Secret Vault.")
            }
            .onChange(of: showingFilePicker) { _, newValue in
                if newValue {
                    importFilesToVault()
                }
            }
            #if os(iOS)
                .onChange(of: showingCamera) { _, isPresented in
                    if !isPresented {
                        UltraPrivacyCoordinator.shared.endTrustedModal()
                    }
                }
            #endif
            if captureInProgress {
                captureProgressOverlay
            }
            if exportInProgress {
                exportProgressOverlay
            }
            if vaultManager.restorationProgress.isRestoring {
                restorationProgressOverlay
            }
        }
        #if os(macOS)
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
            .onChange(of: showingPhotosLibrary) { _, isPresented in
                if isPresented {
                    cancelScheduledForegroundLock()
                }
            }
            .onChange(of: showingFilePicker) { _, isPresented in
                if isPresented {
                    cancelScheduledForegroundLock()
                }
            }
            .onChange(of: showingCamera) { _, isPresented in
                if isPresented {
                    cancelScheduledForegroundLock()
                }
            }
            .onChange(of: vaultManager.importProgress.isImporting) { _, importing in
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
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    isAppActive = true
                } else if newPhase == .background {
                    isAppActive = false
                    if requireForegroundReauthentication {
                        let shouldSuppress = showingPhotosLibrary || showingCamera || vaultManager.importProgress.isImporting || captureInProgress || exportInProgress
                        if !shouldSuppress {
                            vaultManager.lock()
                        }
                    }
                } else if newPhase == .inactive {
                    isAppActive = false
                }
            }
        #endif
    }
}
#if os(macOS)
    extension MainVaultView {
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
                    if vaultManager.isUnlocked {
                        vaultManager.lock()
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
                || vaultManager.importProgress.isImporting
                || captureInProgress
                || exportInProgress
                || isChoosingVaultLocation
        }
    }
#endif
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
                            Image(systemName: "eye.slash.fill")
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
                            Image(
                                systemName: photo.mediaType == .video ? "video.slash" : "exclamationmark.triangle.fill"
                            )
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
                            VStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Decrypting...")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
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
        .onChange(of: privacyModeEnabled) { _, newValue in
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
                    #if DEBUG
                    print(
                        "Thumbnail data empty for photo id=\(photo.id), thumbnailPath=\(photo.thumbnailPath), encryptedThumb=\(photo.encryptedThumbnailPath ?? "nil")"
                    )
                    #endif
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
                            #if DEBUG
                            print("Failed to create NSImage from decrypted data for photo id=\(photo.id)")
                            #endif
                            failedToLoad = true
                        }
                    #else
                        if let uiImage = UIImage(data: data) {
                            thumbnailImage = Image(uiImage: uiImage)
                        } else {
                            #if DEBUG
                            print(
                                "Failed to create UIImage from decrypted data for photo id=\(photo.id), size=\(data.count) bytes"
                            )
                            #endif
                            failedToLoad = true
                        }
                    #endif
                }
            } catch {
                #if DEBUG
                print("Error decrypting thumbnail for photo id=\(photo.id): \(error)")
                #endif
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var fullImage: Image?
    @State private var videoURL: URL?
    @State private var decryptTask: Task<Void, Never>?
    @State private var failedToLoad = false

    var body: some View {
        SecureWrapper {
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
                        #if os(iOS)
                            .padding(.top, -6)
                        #endif
                    }

                    Spacer()

                    Button {
                        cancelDecryptTask()
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
                        decryptingPlaceholder
                    }
                } else {
                    if let image = fullImage {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if failedToLoad {
                        VStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("Failed to load image")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        decryptingPlaceholder
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
                cancelDecryptTask()
                cleanupVideo()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else {
                    dismissViewer()
                    return
                }
            }
        }
    }

    private func loadFullImage() {
        cancelDecryptTask()
        decryptTask = Task {
            do {
                let decryptedData = try await vaultManager.decryptPhoto(photo)
                try Task.checkCancellation()
                #if os(macOS)
                    if let image = NSImage(data: decryptedData) {
                        await MainActor.run {
                            fullImage = Image(nsImage: image)
                        }
                    } else {
                        await MainActor.run { failedToLoad = true }
                    }
                #else
                    if let image = UIImage(data: decryptedData) {
                        await MainActor.run {
                            fullImage = Image(uiImage: image)
                        }
                    } else {
                        await MainActor.run { failedToLoad = true }
                    }
                #endif
            } catch is CancellationError {
                // Cancellation is expected when the viewer is dismissed mid-decrypt
            } catch {
                print("Failed to decrypt photo: \(error)")
            }
            await MainActor.run {
                decryptTask = nil
            }
        }
    }

    private func loadVideo() {
        cancelDecryptTask()
        decryptTask = Task {
            do {
                let tempURL = try await vaultManager.decryptPhotoToTemporaryURL(photo)
                try Task.checkCancellation()
                await MainActor.run {
                    self.videoURL = tempURL
                }
            } catch is CancellationError {
                // Expected when the viewer is dismissed; partial temp files are cleaned up downstream
            } catch {
                print("Failed to decrypt video: \(error)")
            }
            await MainActor.run {
                decryptTask = nil
            }
        }
    }

    private func cleanupVideo() {
        if let url = videoURL {
            try? FileManager.default.removeItem(at: url)
        }
        videoURL = nil
    }

    private func cancelDecryptTask() {
        decryptTask?.cancel()
        decryptTask = nil
    }

    private func dismissViewer() {
        cancelDecryptTask()
        cleanupVideo()
        dismiss()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private var decryptingPlaceholder: some View {
    VStack(spacing: 10) {
        ProgressView()
            .scaleEffect(1.2)
        Text("Decrypting...")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
