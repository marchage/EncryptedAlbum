//
//  ImportSaver.swift
//  EncryptedAlbum
//
//  Small testable helper to save files/data into an import inbox for tests and extensions.
//

import Foundation

public enum ImportSaver {

    /// Save a file URL into a container specified by an app group identifier.
    /// Returns true on success.
    public static func saveFile(toAppGroupIdentifier appGroupIdentifier: String, from url: URL) -> Bool {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return false
        }
        return saveFile(toContainerURL: containerURL, from: url)
    }

    /// Save provided data into a container by building a unique filename.
    public static func saveData(toAppGroupIdentifier appGroupIdentifier: String, _ data: Data, suggestedFilename: String? = nil) -> Bool {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return false
        }
        return saveData(toContainerURL: containerURL, data, suggestedFilename: suggestedFilename)
    }

    // MARK: - Testable, container-based helpers

    /// Save a file into a concrete container URL (testable).
    public static func saveFile(toContainerURL containerURL: URL, from url: URL) -> Bool {
        let inboxURL = containerURL.appendingPathComponent("ImportInbox", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
            var destination = inboxURL.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                // make a safe unique filename
                let ext = (url.lastPathComponent as NSString).pathExtension
                let base = (url.lastPathComponent as NSString).deletingPathExtension
                let generated = "\(base)_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString).\(ext)"
                destination = inboxURL.appendingPathComponent(generated)
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            return true
        } catch {
            return false
        }
    }

    /// Asynchronously copy a file to a container URL providing periodic progress callbacks.
    /// - Parameters:
    ///   - containerURL: destination container URL
    ///   - url: source file URL
    ///   - chunkSize: size of read chunks (default 64KB)
    ///   - progress: closure called with (bytesWritten, totalBytes) on progress updates
    ///   - completion: completion handler called with success boolean
    public static func copyFileWithProgress(toContainerURL containerURL: URL, from url: URL, chunkSize: Int = 64 * 1024, progress: ((Int64, Int64) -> Void)? = nil, completion: @escaping (Bool) -> Void) {
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
                defer { input.close(); try? outHandle.close() }

                var buffer = [UInt8](repeating: 0, count: chunkSize)
                var totalWritten: Int64 = 0
                while input.hasBytesAvailable {
                    let read = input.read(&buffer, maxLength: buffer.count)
                    if read <= 0 { break }
                    let data = Data(bytes: buffer, count: read)
                    outHandle.write(data)
                    totalWritten += Int64(read)
                    DispatchQueue.main.async {
                        progress?(totalWritten, totalSize)
                    }
                }

                DispatchQueue.main.async { completion(true) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    /// Save Data into a container (testable).
    public static func saveData(toContainerURL containerURL: URL, _ data: Data, suggestedFilename: String? = nil) -> Bool {
        let inboxURL = containerURL.appendingPathComponent("ImportInbox", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
            let base = suggestedFilename ?? "SharedItem_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString)"
            let safe = base.replacingOccurrences(of: "/", with: "-")
            let destination = inboxURL.appendingPathComponent(safe)
            try data.write(to: destination, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    /// Write data to destination with progress callbacks.
    public static func writeDataWithProgress(toContainerURL containerURL: URL, _ data: Data, suggestedFilename: String? = nil, chunkSize: Int = 64 * 1024, progress: ((Int64, Int64) -> Void)? = nil, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let inboxURL = containerURL.appendingPathComponent("ImportInbox", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
                let base = suggestedFilename ?? "SharedItem_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString)"
                let safe = base.replacingOccurrences(of: "/", with: "-")
                let destination = inboxURL.appendingPathComponent(safe)

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
}
