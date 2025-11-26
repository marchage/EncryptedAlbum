//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Marc Hage on 26/11/2025.
//

import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {

    // TODO: REPLACE THIS WITH YOUR ACTUAL APP GROUP IDENTIFIER
    // You must create an App Group in Xcode (Signing & Capabilities) for both targets
    // Format is usually: "group.biz.front-end.EncryptedAlbum"
    let appGroupIdentifier = "group.biz.front-end.EncryptedAlbum"

    override func isContentValid() -> Bool {
        return true
    }

    override func didSelectPost() {
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
            print("Error: App Group not configured correctly.")
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
            print("Error saving file to shared container: \(error)")
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
