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

    // TODO: REPLACE THIS WITH YOUR ACTUAL APP GROUP IDENTIFIER
    // You must create an App Group in Xcode (Signing & Capabilities) for both targets
    // Format is usually: "group.biz.front-end.EncryptedAlbum"
    let appGroupIdentifier = "group.biz.front-end.EncryptedAlbum"

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Import to Vault"
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
        
        for item in items {
            guard let attachments = item.attachments else { continue }
            
            for provider in attachments {
                dispatchGroup.enter()
                
                // Handle Images
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] (item, error) in
                        defer { dispatchGroup.leave() }
                        if let url = item as? URL {
                            self?.saveFileToSharedContainer(from: url, type: .image)
                        } else if let image = item as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                            self?.saveDataToSharedContainer(data, type: .image)
                        }
                    }
                }
                // Handle Videos
                else if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.movie.identifier, options: nil) { [weak self] (item, error) in
                        defer { dispatchGroup.leave() }
                        if let url = item as? URL {
                            self?.saveFileToSharedContainer(from: url, type: .movie)
                        }
                    }
                } else {
                    dispatchGroup.leave()
                }
            }
        }

        dispatchGroup.notify(queue: .main) {
            self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    private func saveFileToSharedContainer(from url: URL, type: UTType) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            shareLogger.error("App Group not configured correctly.")
            return
        }
        
        let inboxURL = containerURL.appendingPathComponent("ImportInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        
        let destinationURL = inboxURL.appendingPathComponent(url.lastPathComponent)
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: url, to: destinationURL)
        } catch {
            shareLogger.error("Error saving file to shared container: \(error.localizedDescription)")
        }
    }
    
    private func saveDataToSharedContainer(_ data: Data, type: UTType) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return
        }
        
        let inboxURL = containerURL.appendingPathComponent("ImportInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        
        let filename = "SharedImage_\(Date().timeIntervalSince1970).jpg"
        let destinationURL = inboxURL.appendingPathComponent(filename)
        
        try? data.write(to: destinationURL)
    }

    override func configurationItems() -> [Any]! {
        return []
    }
}
