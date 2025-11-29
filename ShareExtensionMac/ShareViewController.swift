//
//  ShareViewController.swift
//  ShareExtensionMac
//
//  Created by Marc Hage on 28/11/2025.
//

import Cocoa

final class ShareViewController: NSViewController {

    // Replace this with your App Group ID (kept in sync with the iOS extension)
    private let appGroupIdentifier = "group.biz.front-end.EncryptedAlbum.shared"

    override var nibName: NSNib.Name? {
        return NSNib.Name("ShareViewController")
    }

    // preview + progress UI
    private var previewStack: NSStackView?
    private var progressIndicator: NSProgressIndicator?
    private var previewProvidersList: [NSItemProvider] = []
    private var previewImageViews: [NSImageView] = []
    private var previewProgressIndicators: [NSProgressIndicator] = []

    override func loadView() {
        super.loadView()
    
        // Insert code here to customize the view
        // Add a short hint so the macOS share UI isn't an empty sheet and matches iOS wording
        let v = self.view
            let hintField = NSTextField(labelWithString: NSLocalizedString("Share.Placeholder", value: "Import to Encrypted Album — Save shared photos & videos to the app's ImportInbox", comment: "hint text in macOS share sheet"))
            hintField.translatesAutoresizingMaskIntoConstraints = false
            hintField.lineBreakMode = .byWordWrapping
            hintField.alignment = .center
            hintField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            hintField.textColor = NSColor.secondaryLabelColor
            v.addSubview(hintField)
            NSLayoutConstraint.activate([
                hintField.topAnchor.constraint(equalTo: v.topAnchor, constant: 16),
                hintField.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16),
                hintField.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16)
            ])
        
        // Build a compact preview strip with thumbnail + label + small progress
        if let items = self.extensionContext?.inputItems as? [NSExtensionItem] {
            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
            v.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: hintField.bottomAnchor, constant: 8),
                stack.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor, constant: -16)
            ])
            self.previewStack = stack

            var providers: [NSItemProvider] = []
            var imageViews: [NSImageView] = []
            var progressIndicators: [NSProgressIndicator] = []

            for item in items {
                guard let attachments = item.attachments else { continue }
                for provider in attachments {
                    let container = NSStackView()
                    container.orientation = .vertical
                    container.spacing = 4
                    container.translatesAutoresizingMaskIntoConstraints = false

                    let img = NSImageView()
                    img.imageScaling = .scaleAxesIndependently
                    img.wantsLayer = true
                    img.layer?.cornerRadius = 6
                    img.layer?.masksToBounds = true
                    img.translatesAutoresizingMaskIntoConstraints = false
                    img.widthAnchor.constraint(equalToConstant: 48).isActive = true
                    img.heightAnchor.constraint(equalToConstant: 48).isActive = true

                    let label = NSTextField(labelWithString: provider.hasItemConformingToTypeIdentifier("public.image") ? NSLocalizedString("Share.Preview.ImageLabel", value: "Image", comment: "preview label for images") : provider.hasItemConformingToTypeIdentifier("public.movie") ? NSLocalizedString("Share.Preview.MovieLabel", value: "Video", comment: "preview label for video") : NSLocalizedString("Share.Preview.ItemLabel", value: "Item", comment: "preview generic item"))
                    label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                    label.textColor = NSColor.secondaryLabelColor

                    let p = NSProgressIndicator()
                    p.isIndeterminate = false
                    p.minValue = 0
                    p.maxValue = 1
                    p.doubleValue = 0
                    p.isHidden = true
                    p.controlSize = .small
                    p.translatesAutoresizingMaskIntoConstraints = false
                    p.widthAnchor.constraint(equalToConstant: 48).isActive = true

                    container.addArrangedSubview(img)
                    container.addArrangedSubview(label)
                    container.addArrangedSubview(p)
                    stack.addArrangedSubview(container)

                    providers.append(provider)
                    imageViews.append(img)
                    progressIndicators.append(p)

                    if provider.canLoadObject(ofClass: NSImage.self) {
                        provider.loadObject(ofClass: NSImage.self) { object, err in
                            if let image = object as? NSImage {
                                DispatchQueue.main.async { img.image = image }
                            }
                        }
                    } else if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                            if let url = item as? URL, let image = NSImage(contentsOf: url) {
                                DispatchQueue.main.async { img.image = image }
                            }
                        }
                    }
                }
            }

            self.previewProvidersList = providers
            self.previewImageViews = imageViews
            self.previewProgressIndicators = progressIndicators
        }
    }

    @IBAction func send(_ sender: AnyObject?) {
        guard let context = self.extensionContext else { return }

        // Respect Lockdown Mode configured in shared suite (same behavior as iOS extension)
        if let suite = UserDefaults(suiteName: appGroupIdentifier), suite.bool(forKey: "lockdownModeEnabled") {
            let alert = NSAlert()
            alert.messageText = "Import blocked"
            alert.informativeText = "Encrypted Album is in Lockdown Mode. Imports are disabled."
            alert.addButton(withTitle: "OK")
            alert.alertStyle = .warning
            alert.beginSheetModal(for: self.view.window ?? NSApp.mainWindow ?? NSWindow()) { _ in
                context.completeRequest(returningItems: [], completionHandler: nil)
            }
            return
        }

        let inputItems = context.inputItems as? [NSExtensionItem] ?? []
        let dispatchGroup = DispatchGroup()
        var savedCount = 0
        let countSyncQueue = DispatchQueue(label: "share.saveCount.mac")

        // Determine how many items we'll process (used for progress)
        var totalCount = 0
        for item in inputItems {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier("public.file-url") || provider.hasItemConformingToTypeIdentifier("public.image") || provider.hasItemConformingToTypeIdentifier("public.movie") {
                    totalCount += 1
                }
            }
        }

        if totalCount > 0 {
            if progressIndicator == nil {
                let p = NSProgressIndicator()
                p.translatesAutoresizingMaskIntoConstraints = false
                p.isIndeterminate = false
                p.minValue = 0
                p.maxValue = Double(totalCount)
                p.doubleValue = 0
                // attach to the view of this controller
                let v = self.view
                v.addSubview(p)
                NSLayoutConstraint.activate([
                    p.topAnchor.constraint(equalTo: previewStack?.bottomAnchor ?? v.topAnchor, constant: 8),
                    p.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16),
                    p.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16)
                ])
                self.progressIndicator = p
            }
            progressIndicator?.isHidden = false
        }

        // Flatten providers so we can map per-item progress
        let flatProviders: [NSItemProvider] = inputItems.flatMap { $0.attachments ?? [] }
        for (idx, provider) in flatProviders.enumerated() {
            dispatchGroup.enter()

            // per-item progress updater
            func updateItemProgress(_ written: Int64, _ total: Int64) {
                DispatchQueue.main.async {
                    if idx < self.previewProgressIndicators.count {
                        let p = self.previewProgressIndicators[idx]
                        p.isHidden = false
                        p.doubleValue = total > 0 ? Double(written) / Double(total) : 0
                    }
                }
            }

            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                    if let url = item as? URL {
                        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: self.appGroupIdentifier) else { dispatchGroup.leave(); return }
                        self.copyFileToSharedContainerWithProgress(to: containerURL, from: url, chunkSize: 64 * 1024, progress: { written, total in
                            updateItemProgress(written, total)
                        }, completion: { success in
                            if success {
                                countSyncQueue.async {
                                    savedCount += 1
                                    DispatchQueue.main.async { self.updateProgress(saved: savedCount, total: totalCount) }
                                }
                            }
                            dispatchGroup.leave()
                        })
                    } else {
                        dispatchGroup.leave()
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier("public.image") {
                provider.loadItem(forTypeIdentifier: "public.image", options: nil) { item, error in
                    if let url = item as? URL {
                        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: self.appGroupIdentifier) else { dispatchGroup.leave(); return }
                        self.copyFileToSharedContainerWithProgress(to: containerURL, from: url, chunkSize: 64 * 1024, progress: { written, total in
                            updateItemProgress(written, total)
                        }, completion: { success in
                            if success { countSyncQueue.async { savedCount += 1; DispatchQueue.main.async { self.updateProgress(saved: savedCount, total: totalCount) } } }
                            dispatchGroup.leave()
                        })
                    } else if let data = item as? Data {
                        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: self.appGroupIdentifier) else { dispatchGroup.leave(); return }
                        self.writeDataToSharedContainerWithProgress(to: containerURL, data, chunkSize: 64 * 1024, progress: { written, total in
                            updateItemProgress(written, total)
                        }, completion: { success in
                            if success { countSyncQueue.async { savedCount += 1; DispatchQueue.main.async { self.updateProgress(saved: savedCount, total: totalCount) } } }
                            dispatchGroup.leave()
                        })
                    } else if let image = item as? NSImage, let tiff = image.tiffRepresentation {
                        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: self.appGroupIdentifier) else { dispatchGroup.leave(); return }
                        self.writeDataToSharedContainerWithProgress(to: containerURL, tiff, chunkSize: 64 * 1024, progress: { written, total in
                            updateItemProgress(written, total)
                        }, completion: { success in
                            if success { countSyncQueue.async { savedCount += 1; DispatchQueue.main.async { self.updateProgress(saved: savedCount, total: totalCount) } } }
                            dispatchGroup.leave()
                        })
                    } else {
                        dispatchGroup.leave()
                    }
                }
            } else {
                // Unsupported type — skip
                dispatchGroup.leave()
            }
        }

        dispatchGroup.notify(queue: .main) {
            // Show a simple confirmation to the user so they know the import succeeded.
            let alert = NSAlert()
            if savedCount > 0 {
                alert.messageText = String(format: NSLocalizedString("Share.ImportedTitle", value: "Imported %d item(s)", comment: "Imported title with count"), savedCount)
                alert.informativeText = NSLocalizedString("Share.ImportedMessage", value: "Encrypted Album saved shared items to the ImportInbox. Open the app to finish importing.", comment: "Imported informative message")
                alert.addButton(withTitle: "OK")
            } else {
                alert.messageText = NSLocalizedString("Share.NothingImportedTitle", value: "Nothing imported", comment: "Nothing imported title")
                alert.informativeText = NSLocalizedString("Share.NothingImportedMessage", value: "No supported files were available to import.", comment: "Nothing imported message")
                alert.addButton(withTitle: "OK")
            }

            // Show the alert and finish after the user dismisses it so the extension provides feedback
            alert.alertStyle = .informational
            alert.beginSheetModal(for: self.view.window ?? NSApp.mainWindow ?? NSWindow()) { _ in
                context.completeRequest(returningItems: [], completionHandler: nil)
            }
        }
    }

    @IBAction func cancel(_ sender: AnyObject?) {
        let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
        self.extensionContext!.cancelRequest(withError: cancelError)
    }

    // MARK: - Helpers

    private func saveFileToSharedContainer(from url: URL) -> Bool {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            NSLog("ShareExtensionMac: App group container not found for id: %@", appGroupIdentifier)
            return false
        }

        let inboxURL = containerURL.appendingPathComponent("ImportInbox", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
            var destination = inboxURL.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                let ext = (url.lastPathComponent as NSString).pathExtension
                let base = (url.lastPathComponent as NSString).deletingPathExtension
                let generated = "\(base)_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString).\(ext)"
                destination = inboxURL.appendingPathComponent(generated)
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            NSLog("ShareExtensionMac: copied file to %@", destination.path)
            return true
        } catch {
            NSLog("ShareExtensionMac: failed to copy file: %@", error.localizedDescription)
            return false
        }
    }

    private func saveDataToSharedContainer(_ data: Data, suggestedFilename: String?) -> Bool {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            NSLog("ShareExtensionMac: App group container not found for id: %@", appGroupIdentifier)
            return false
        }

        let inboxURL = containerURL.appendingPathComponent("ImportInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)

        let base = suggestedFilename ?? "SharedItem_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString)"
        let safe = base.replacingOccurrences(of: "/", with: "-")
        let destination = inboxURL.appendingPathComponent(safe)
        do {
            try data.write(to: destination, options: [.atomic])
            NSLog("ShareExtensionMac: wrote data to %@", destination.path)
            return true
        } catch {
            NSLog("ShareExtensionMac: failed to write data: %@", error.localizedDescription)
            return false
        }
    }

    // Async copy/write helpers with progress support for macOS extension
    private func copyFileToSharedContainerWithProgress(to containerURL: URL, from url: URL, chunkSize: Int = 64 * 1024, progress: ((Int64, Int64) -> Void)?, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let inboxURL = containerURL.appendingPathComponent("ImportInbox", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
                var destination = inboxURL.appendingPathComponent(url.lastPathComponent)
                if FileManager.default.fileExists(atPath: destination.path) {
                    let ext = (url.lastPathComponent as NSString).pathExtension
                    let base = (url.lastPathComponent as NSString).deletingPathExtension
                    let generated = "\(base)_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString).\(ext)"
                    destination = inboxURL.appendingPathComponent(generated)
                }
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }

                let attr = try FileManager.default.attributesOfItem(atPath: url.path)
                let totalSize = (attr[FileAttributeKey.size] as? NSNumber)?.int64Value ?? 0

                guard let input = InputStream(url: url) else { DispatchQueue.main.async { completion(false) }; return }
                guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { DispatchQueue.main.async { completion(false) }; return }
                guard let outHandle = try? FileHandle(forWritingTo: destination) else { DispatchQueue.main.async { completion(false) }; return }

                input.open()
                defer { input.close(); try? outHandle.close() }

                var buffer = [UInt8](repeating: 0, count: chunkSize)
                var totalWritten: Int64 = 0
                while input.hasBytesAvailable {
                    let read = input.read(&buffer, maxLength: buffer.count)
                    if read <= 0 { break }
                    let data = Data(bytes: buffer, count: read)
                    outHandle.write(data)
                    totalWritten += Int64(read)
                    DispatchQueue.main.async { progress?(totalWritten, totalSize) }
                }

                DispatchQueue.main.async { completion(true) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    private func writeDataToSharedContainerWithProgress(to containerURL: URL, _ data: Data, chunkSize: Int = 64 * 1024, progress: ((Int64, Int64) -> Void)?, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let inboxURL = containerURL.appendingPathComponent("ImportInbox", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
                let base = "SharedItem_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString)"
                let destination = inboxURL.appendingPathComponent(base)
                guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { DispatchQueue.main.async { completion(false) }; return }
                guard let outHandle = try? FileHandle(forWritingTo: destination) else { DispatchQueue.main.async { completion(false) }; return }
                defer { try? outHandle.close() }
                let totalSize = Int64(data.count)
                var offset = 0
                while offset < data.count {
                    let len = min(chunkSize, data.count - offset)
                    let chunk = data.subdata(in: offset..<offset+len)
                    outHandle.write(chunk)
                    offset += len
                    DispatchQueue.main.async { progress?(Int64(offset), totalSize) }
                }

                DispatchQueue.main.async { completion(true) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    private func updateProgress(saved: Int, total: Int) {
        guard total > 0 else { return }
        progressIndicator?.doubleValue = Double(saved)
    }

}
