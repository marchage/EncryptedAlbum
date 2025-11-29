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

    override func loadView() {
        super.loadView()
    
        // Insert code here to customize the view
        let item = self.extensionContext!.inputItems[0] as! NSExtensionItem
        if let attachments = item.attachments {
            NSLog("Attachments = %@", attachments as NSArray)
        } else {
            NSLog("No Attachments")
        }
    }

    @IBAction func send(_ sender: AnyObject?) {
        guard let context = self.extensionContext else { return }

        let inputItems = context.inputItems as? [NSExtensionItem] ?? []
        let dispatchGroup = DispatchGroup()
        var savedCount = 0

        for item in inputItems {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                dispatchGroup.enter()

                if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                        defer { dispatchGroup.leave() }
                        if let url = item as? URL {
                            if self.saveFileToSharedContainer(from: url) {
                                savedCount += 1
                            }
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier("public.image") {
                    provider.loadItem(forTypeIdentifier: "public.image", options: nil) { item, error in
                        defer { dispatchGroup.leave() }
                        if let url = item as? URL {
                            if self.saveFileToSharedContainer(from: url) {
                                savedCount += 1
                            }
                        } else if let data = item as? Data {
                            if self.saveDataToSharedContainer(data, suggestedFilename: nil) {
                                savedCount += 1
                            }
                        } else if let image = item as? NSImage, let tiff = image.tiffRepresentation {
                            if self.saveDataToSharedContainer(tiff, suggestedFilename: nil) {
                                savedCount += 1
                            }
                        }
                    }
                } else {
                    // Unsupported type — skip
                    dispatchGroup.leave()
                }
            }
        }

        dispatchGroup.notify(queue: .main) {
            // Show a simple confirmation to the user so they know the import succeeded.
            let alert = NSAlert()
            if savedCount > 0 {
                alert.messageText = "Imported \(savedCount) item\(savedCount == 1 ? "" : "s")"
                alert.informativeText = "Encrypted Album saved shared items to the shared ImportInbox. Open the app to import them."
                alert.addButton(withTitle: "OK")
            } else {
                alert.messageText = "Nothing imported"
                alert.informativeText = "No supported files were available to import."
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

}
