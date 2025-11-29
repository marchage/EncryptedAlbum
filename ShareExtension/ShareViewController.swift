//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Marc Hage on 26/11/2025.
//

import UIKit
import os
import Social
import MobileCoreServices
import UniformTypeIdentifiers

private let shareLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "EncryptedAlbum.ShareExtension", category: "share")

class ShareViewController: SLComposeServiceViewController {

    // App Group used for handoff from share extension -> main app
    // Using the shared app group created for this product
    let appGroupIdentifier = "group.biz.front-end.EncryptedAlbum.shared"

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Import to Encrypted Album"
        self.navigationController?.navigationBar.topItem?.rightBarButtonItem?.title = "Save"
        self.placeholder = "Tap Save to import photos/videos"
    }

    override func isContentValid() -> Bool {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return false }
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
                   provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    return true
                }
            }
        }
        return false
    }

    override func didSelectPost() {
        // Check app group's lockdown flag and refuse if Lockdown Mode is enabled
        if let suite = UserDefaults(suiteName: appGroupIdentifier), suite.bool(forKey: "lockdownModeEnabled") {
            let alert = UIAlertController(title: "Import blocked", message: "Encrypted Album is in Lockdown Mode. Imports are disabled.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel) { _ in
                self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            })
            DispatchQueue.main.async {
                self.present(alert, animated: true, completion: nil)
            }
            return
        }
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
            return
        }

        let dispatchGroup = DispatchGroup()
        let countSyncQueue = DispatchQueue(label: "share.saveCount")
        var savedCount = 0
        
        for item in items {
            guard let attachments = item.attachments else { continue }
            
            for provider in attachments {
                dispatchGroup.enter()
                
                // Handle Images
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] (item, error) in
                        defer { dispatchGroup.leave() }
                        if let url = item as? URL {
                            if let success = self?.saveFileToSharedContainer(from: url, type: .image), success {
                                countSyncQueue.async { savedCount += 1 }
                            }
                        } else if let image = item as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                            if let success = self?.saveDataToSharedContainer(data, type: .image), success {
                                countSyncQueue.async { savedCount += 1 }
                            }
                        }
                    }
                }
                // Handle Videos
                else if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.movie.identifier, options: nil) { [weak self] (item, error) in
                        defer { dispatchGroup.leave() }
                        if let url = item as? URL {
                            if let success = self?.saveFileToSharedContainer(from: url, type: .movie), success {
                                countSyncQueue.async { savedCount += 1 }
                            }
                        }
                    }
                } else {
                    dispatchGroup.leave()
                }
            }
        }

        dispatchGroup.notify(queue: .main) {
            // show a clear confirmation UI so iOS and macOS behave consistently
            countSyncQueue.sync { /* ensure savedCount seen on main thread */ }
            let alertTitle: String
            let alertMessage: String
            if savedCount > 0 {
                alertTitle = "Imported \(savedCount) item\(savedCount == 1 ? "" : "s")"
                alertMessage = "Encrypted Album saved shared items to the ImportInbox. Open the app to finish importing."
            } else {
                alertTitle = "Nothing imported"
                alertMessage = "No supported files were available to import."
            }

            let alert = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
            })
            DispatchQueue.main.async {
                self.present(alert, animated: true, completion: nil)
            }
        }
    }

    private func saveFileToSharedContainer(from url: URL, type: UTType) -> Bool {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            shareLogger.error("App Group not configured correctly.")
            return false
        }
        
        let inboxURL = containerURL.appendingPathComponent("ImportInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        
        let destinationURL = inboxURL.appendingPathComponent(url.lastPathComponent)
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: url, to: destinationURL)
            return true
        } catch {
            shareLogger.error("Error saving file to shared container: \(error.localizedDescription)")
            return false
        }
        return false
    }
    
    private func saveDataToSharedContainer(_ data: Data, type: UTType) -> Bool {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return false
        }
        
        let inboxURL = containerURL.appendingPathComponent("ImportInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        
        let filename = "SharedImage_\(Date().timeIntervalSince1970).jpg"
        let destinationURL = inboxURL.appendingPathComponent(filename)
        
        do {
            try data.write(to: destinationURL)
            return true
        } catch {
            shareLogger.error("Error saving data to shared container: \(error.localizedDescription)")
            return false
        }
    }

    override func configurationItems() -> [Any]! {
        return []
    }
}
