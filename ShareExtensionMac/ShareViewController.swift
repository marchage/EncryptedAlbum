//  ShareViewController.swift
//  ShareExtensionMac (scaffold)
//
//  Minimal macOS Share Extension view controller intended as a starting point.
//  Add this code to an Xcode macOS Share target and enable App Groups for the
//  extension's App ID. The controller will copy incoming items into the app
//  group's "ImportInbox" directory so your main app can pick them up.

import Cocoa

private let shareLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "EncryptedAlbum.ShareExtensionMac", category: "share")

final class ShareViewController: NSViewController {
    // Match the app group used by the main app. Make sure this exact string
    // is enabled in your AppID + provisioning profile on developer.apple.com
    // before signing this extension.
    private let appGroupIdentifier = "group.biz.front-end.EncryptedAlbum"

    override func viewDidLoad() {
        super.viewDidLoad()
        // Basic UI placeholder for the extension; extensions usually show minimal UI
        // because a user action triggers them and they often run headless.
    }

    /// Called by the system when the user chooses the extension's action.
    /// We accept the incoming items and copy them into the shared container's
    /// ImportInbox directory so the main app can process them on next launch.
    func performShare() {
        // Block shares when lockdown sentinel is present in the shared suite
        if let suite = UserDefaults(suiteName: appGroupIdentifier), suite.bool(forKey: "lockdownModeEnabled") {
            let alert = NSAlert()
            alert.messageText = "Import blocked — Lockdown Mode"
            alert.informativeText = "Encrypted Album is currently in Lockdown Mode and is not accepting incoming shares. Disable Lockdown Mode in the app to allow imports."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            return
        }
        guard let context = self.extensionContext else { return }

        let inputItems = context.inputItems as? [NSExtensionItem] ?? []
        let dispatchGroup = DispatchGroup()

        for item in inputItems {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                dispatchGroup.enter()
                // Attempt file URLs first, then try raw data types
                if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                        defer { dispatchGroup.leave() }
                        if let url = item as? URL {
                            self.saveFileToSharedContainer(from: url)
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier("public.image") {
                    provider.loadItem(forTypeIdentifier: "public.image", options: nil) { item, error in
                        defer { dispatchGroup.leave() }
                        if let url = item as? URL {
                            self.saveFileToSharedContainer(from: url)
                        } else if let data = item as? Data {
                            self.saveDataToSharedContainer(data, suggestedFilename: nil)
                        }
                    }
                } else {
                    // Unsupported type — skip
                    dispatchGroup.leave()
                }
            }
        }

        dispatchGroup.notify(queue: .main) {
            // Inform the host app / system we're done
            context.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    private func saveFileToSharedContainer(from url: URL) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            shareLog.error("App group container not found — ensure the extension has the App Group entitlement enabled.")
            return
        }

        let inboxURL = containerURL.appendingPathComponent("ImportInbox", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
            let destination = inboxURL.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            shareLog.debug("Saved file to shared container: %{public}@", destination.path)
        } catch {
            shareLog.error("Failed to copy shared file: %{public}@", error.localizedDescription)
        }
    }

    private func saveDataToSharedContainer(_ data: Data, suggestedFilename: String?) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return
        }

        let inboxURL = containerURL.appendingPathComponent("ImportInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)

        let filename = suggestedFilename ?? "SharedItem_\(Date().timeIntervalSince1970)"
        let destination = inboxURL.appendingPathComponent(filename)
        do {
            try data.write(to: destination)
            shareLog.debug("Wrote data share to %{public}@", destination.path)
        } catch {
            shareLog.error("Failed to write data share: %{public}@", error.localizedDescription)
        }
    }
}
