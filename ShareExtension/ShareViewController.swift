//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Marc Hage on 26/11/2025.
//

import MobileCoreServices
import Social
import UIKit
import UniformTypeIdentifiers
import os

private let shareLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "EncryptedAlbum.ShareExtension", category: "share")

class ShareViewController: SLComposeServiceViewController {

    // App Group used for handoff from share extension -> main app
    // Using the shared app group created for this product
    let appGroupIdentifier = "group.biz.front-end.EncryptedAlbum.shared"

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Import to Encrypted Album"
        self.navigationController?.navigationBar.topItem?.rightBarButtonItem?.title = "Save"
        self.placeholder = NSLocalizedString(
            "Share.Placeholder", value: "Tap Save to import photos/videos",
            comment: "Placeholder text in share extension compose")

        setupPreviewUI()
    }

    override func isContentValid() -> Bool {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return false }
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
                    || provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
                {
                    return true
                }
            }
        }
        return false
    }

    override func didSelectPost() {
        // Check app group's lockdown flag and refuse if Lockdown Mode is enabled
        if let suite = UserDefaults(suiteName: appGroupIdentifier), suite.bool(forKey: "lockdownModeEnabled") {
            let alert = UIAlertController(
                title: "Import blocked", message: "Encrypted Album is in Lockdown Mode. Imports are disabled.",
                preferredStyle: .alert)
            alert.addAction(
                UIAlertAction(title: "OK", style: .cancel) { _ in
                    self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                })
            DispatchQueue.main.async { self.present(alert, animated: true, completion: nil) }
            return
        }

        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
            return
        }

        // Shared state for the processing loop
        let dispatchGroup = DispatchGroup()
        let countSyncQueue = DispatchQueue(label: "share.saveCount")
        var savedCount = 0

        // Flatten providers and count
        var flatProviders: [NSItemProvider] = []
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments { flatProviders.append(provider) }
        }
        let totalCount = flatProviders.count

        for (idx, provider) in flatProviders.enumerated() {
            dispatchGroup.enter()

            func updateItemProgress(_ written: Int64, _ total: Int64) {
                DispatchQueue.main.async {
                    if idx < self.previewProgressViews.count {
                        let p = self.previewProgressViews[idx]
                        p.isHidden = false
                        let f = total > 0 ? Float(written) / Float(total) : 0
                        p.setProgress(f, animated: true)
                    }
                }
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] (item, _) in
                    guard let self = self else {
                        dispatchGroup.leave()
                        return
                    }
                    if let url = item as? URL {
                        guard
                            let containerURL = FileManager.default.containerURL(
                                forSecurityApplicationGroupIdentifier: self.appGroupIdentifier)
                        else {
                            dispatchGroup.leave()
                            return
                        }
                        self.copyFileToSharedContainerWithProgress(
                            to: containerURL, from: url, progress: { w, t in updateItemProgress(w, t) },
                            completion: { success in
                                if success {
                                    countSyncQueue.async {
                                        savedCount += 1
                                        DispatchQueue.main.async {
                                            self.updateProgress(saved: savedCount, total: totalCount)
                                        }
                                    }
                                }
                                dispatchGroup.leave()
                            })
                    } else if let image = item as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                        guard
                            let containerURL = FileManager.default.containerURL(
                                forSecurityApplicationGroupIdentifier: self.appGroupIdentifier)
                        else {
                            dispatchGroup.leave()
                            return
                        }
                        self.writeDataToSharedContainerWithProgress(
                            to: containerURL, data, chunkSize: 64 * 1024,
                            progress: { w, t in updateItemProgress(w, t) },
                            completion: { success in
                                if success {
                                    countSyncQueue.async {
                                        savedCount += 1
                                        DispatchQueue.main.async {
                                            self.updateProgress(saved: savedCount, total: totalCount)
                                        }
                                    }
                                }
                                dispatchGroup.leave()
                            })
                    } else {
                        dispatchGroup.leave()
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            {
                let typeId =
                    provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
                    ? UTType.movie.identifier : UTType.fileURL.identifier
                provider.loadItem(forTypeIdentifier: typeId, options: nil) { [weak self] (item, _) in
                    guard let self = self else {
                        dispatchGroup.leave()
                        return
                    }
                    if let url = item as? URL {
                        guard
                            let containerURL = FileManager.default.containerURL(
                                forSecurityApplicationGroupIdentifier: self.appGroupIdentifier)
                        else {
                            dispatchGroup.leave()
                            return
                        }
                        self.copyFileToSharedContainerWithProgress(
                            to: containerURL, from: url, progress: { w, t in updateItemProgress(w, t) },
                            completion: { success in
                                if success {
                                    countSyncQueue.async {
                                        savedCount += 1
                                        DispatchQueue.main.async {
                                            self.updateProgress(saved: savedCount, total: totalCount)
                                        }
                                    }
                                }
                                dispatchGroup.leave()
                            })
                    } else if let data = item as? Data {
                        guard
                            let containerURL = FileManager.default.containerURL(
                                forSecurityApplicationGroupIdentifier: self.appGroupIdentifier)
                        else {
                            dispatchGroup.leave()
                            return
                        }
                        self.writeDataToSharedContainerWithProgress(
                            to: containerURL, data, chunkSize: 64 * 1024,
                            progress: { w, t in updateItemProgress(w, t) },
                            completion: { success in
                                if success {
                                    countSyncQueue.async {
                                        savedCount += 1
                                        DispatchQueue.main.async {
                                            self.updateProgress(saved: savedCount, total: totalCount)
                                        }
                                    }
                                }
                                dispatchGroup.leave()
                            })
                    } else {
                        dispatchGroup.leave()
                    }
                }
            } else {
                dispatchGroup.leave()
            }
        }

        dispatchGroup.notify(queue: .main) {
            // show a clear confirmation UI so iOS and macOS behave consistently
            countSyncQueue.sync { /* ensure savedCount seen on main thread */  }
            let alertTitle: String
            let alertMessage: String
            if savedCount > 0 {
                alertTitle = String(
                    format: NSLocalizedString(
                        "Share.ImportedTitle", value: "Imported %d item(s)", comment: "Imported title with count"),
                    savedCount)
                alertMessage = NSLocalizedString(
                    "Share.ImportedMessage",
                    value: "Encrypted Album saved shared items to the ImportInbox. Open the app to finish importing.",
                    comment: "Imported informative message")
            } else {
                alertTitle = NSLocalizedString(
                    "Share.NothingImportedTitle", value: "Nothing imported", comment: "Nothing imported title")
                alertMessage = NSLocalizedString(
                    "Share.NothingImportedMessage", value: "No supported files were available to import.",
                    comment: "Nothing imported message")
            }

            let alert = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)
            alert.addAction(
                UIAlertAction(title: "OK", style: .default) { _ in
                    self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
                })
            DispatchQueue.main.async {
                self.present(alert, animated: true, completion: nil)
            }
        }
    }

    private func saveFileToSharedContainer(from url: URL, type: UTType) -> Bool {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else {
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
    }

    private func saveDataToSharedContainer(_ data: Data, type: UTType) -> Bool {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else {
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

    // Async copy with progress for extension (per-item)
    private func copyFileToSharedContainerWithProgress(
        to containerURL: URL, from url: URL, chunkSize: Int = 64 * 1024, progress: ((Int64, Int64) -> Void)?,
        completion: @escaping (Bool) -> Void
    ) {
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
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }

                let attr = try FileManager.default.attributesOfItem(atPath: url.path)
                let totalSize = (attr[FileAttributeKey.size] as? NSNumber)?.int64Value ?? 0

                guard let input = InputStream(url: url) else {
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                guard let outHandle = try? FileHandle(forWritingTo: destination) else {
                    DispatchQueue.main.async { completion(false) }
                    return
                }

                input.open()
                defer {
                    input.close()
                    try? outHandle.close()
                }

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

    private func writeDataToSharedContainerWithProgress(
        to containerURL: URL, _ data: Data, chunkSize: Int = 64 * 1024, progress: ((Int64, Int64) -> Void)?,
        completion: @escaping (Bool) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            let inboxURL = containerURL.appendingPathComponent("ImportInbox", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
                let base = "SharedItem_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString)"
                let destination = inboxURL.appendingPathComponent(base)
                guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                guard let outHandle = try? FileHandle(forWritingTo: destination) else {
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                defer { try? outHandle.close() }
                let totalSize = Int64(data.count)
                var offset = 0
                while offset < data.count {
                    let len = min(chunkSize, data.count - offset)
                    let chunk = data.subdata(in: offset..<offset + len)
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

    // MARK: - Preview UI + Progress helpers

    private var previewContainerView: UIView?
    private var previewStack: UIStackView?
    private var progressView: UIProgressView?
    private var previewProviders: [NSItemProvider] = []
    private var previewProgressViews: [UIProgressView] = []
    private var previewImageViews: [UIImageView] = []

    private func setupPreviewUI() {
        // simple horizontal stack showing filename/placeholder for each attachment
        guard let root = self.view else { return }
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(container)

        // place at top of safe area (above the existing compose text)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: root.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            container.trailingAnchor.constraint(equalTo: root.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            container.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 8),
        ])

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.previewContainerView = container
        self.previewStack = stack

        // populate previews from inputItems (make a small thumbnail + label for each attachment)
        if let items = extensionContext?.inputItems as? [NSExtensionItem] {
            for item in items {
                guard let attachments = item.attachments else { continue }
                for provider in attachments {
                    // provider container
                    let v = UIStackView()
                    v.axis = .vertical
                    v.alignment = .center
                    v.spacing = 4
                    v.translatesAutoresizingMaskIntoConstraints = false

                    // thumbnail
                    let img = UIImageView(image: UIImage(systemName: "photo"))
                    img.contentMode = .scaleAspectFill
                    img.clipsToBounds = true
                    img.layer.cornerRadius = 6
                    img.translatesAutoresizingMaskIntoConstraints = false
                    img.widthAnchor.constraint(equalToConstant: 48).isActive = true
                    img.heightAnchor.constraint(equalToConstant: 48).isActive = true

                    // label
                    let label = UILabel()
                    label.font = UIFont.preferredFont(forTextStyle: .footnote)
                    label.textColor = .secondaryLabel
                    if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                        label.text = NSLocalizedString(
                            "Share.Preview.ImageLabel", value: "Image", comment: "preview label for images")
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                        label.text = NSLocalizedString(
                            "Share.Preview.MovieLabel", value: "Video", comment: "preview label for video")
                    } else {
                        label.text = NSLocalizedString(
                            "Share.Preview.ItemLabel", value: "Item", comment: "preview generic item")
                    }

                    // per-item progress
                    let p = UIProgressView(progressViewStyle: .bar)
                    p.isHidden = true
                    p.setProgress(0, animated: false)
                    p.translatesAutoresizingMaskIntoConstraints = false
                    p.widthAnchor.constraint(equalToConstant: 48).isActive = true

                    v.addArrangedSubview(img)
                    v.addArrangedSubview(label)
                    v.addArrangedSubview(p)
                    stack.addArrangedSubview(v)

                    self.previewProviders.append(provider)
                    self.previewImageViews.append(img)
                    self.previewProgressViews.append(p)

                    // attempt loading an image thumbnail if possible
                    if provider.canLoadObject(ofClass: UIImage.self) {
                        provider.loadObject(ofClass: UIImage.self) { object, err in
                            DispatchQueue.main.async {
                                if let image = object as? UIImage {
                                    img.image = image
                                }
                            }
                        }
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                        // try to load file URL and generate a thumbnail if it's an image
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, err in
                            if let url = item as? URL, let data = try? Data(contentsOf: url),
                                let image = UIImage(data: data)
                            {
                                DispatchQueue.main.async { img.image = image }
                            }
                        }
                    }
                }
            }
        }
    }

    private func showProgress(total: Int) {
        guard let root = self.view else { return }
        if progressView == nil {
            let p = UIProgressView(progressViewStyle: .default)
            p.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(p)
            NSLayoutConstraint.activate([
                p.leadingAnchor.constraint(equalTo: root.safeAreaLayoutGuide.leadingAnchor, constant: 10),
                p.trailingAnchor.constraint(equalTo: root.safeAreaLayoutGuide.trailingAnchor, constant: -10),
                p.topAnchor.constraint(
                    equalTo: previewContainerView?.bottomAnchor ?? root.safeAreaLayoutGuide.topAnchor, constant: 8),
            ])
            self.progressView = p
        }
        progressView?.progress = 0
    }

    private func updateProgress(saved: Int, total: Int) {
        guard total > 0 else { return }
        let f = Float(saved) / Float(total)
        progressView?.setProgress(f, animated: true)
    }

    override func configurationItems() -> [Any]! {
        return []
    }
}
