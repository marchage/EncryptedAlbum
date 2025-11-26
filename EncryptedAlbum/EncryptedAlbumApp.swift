import SwiftUI
import UserNotifications

@main
struct EncryptedAlbumApp: App {
    @StateObject private var albumManager = AlbumManager.shared
    @State private var hasNotifiedBackgroundActivity = false
    #if os(macOS)
        @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
            WindowGroup {
                ContentView()
                    .environmentObject(albumManager)
                    .frame(minWidth: 900, minHeight: 600)
                    .overlay {
                        InactiveAppOverlay()
                    }
                    .onChange(of: albumManager.isBusy) { isBusy in
                        if !isBusy {
                            hasNotifiedBackgroundActivity = false
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                        if albumManager.isBusy {
                            if !hasNotifiedBackgroundActivity {
                                sendBackgroundActivityNotification()
                                hasNotifiedBackgroundActivity = true
                            }
                        } else {
                            albumManager.lock()
                        }
                    }
            }
            Settings {
                PreferencesView()
                    .environmentObject(albumManager)
            }
            .commands {
                // Remove "New Window" command to prevent multiple windows
                CommandGroup(replacing: .newItem) {}
            }
        #endif
        #if os(iOS)
        // This target should use EncryptedAlbum_iOSApp.swift as entry point
        // But if this file is included in iOS target by mistake, we provide a fallback
        WindowGroup {
            ContentView()
                .environmentObject(albumManager)
        }
        #endif
    }

    private func sendBackgroundActivityNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Album Operation in Progress"
        content.body = "Encrypted Album is performing a task in the background and will remain unlocked until it completes."
        content.sound = nil

        let request = UNNotificationRequest(identifier: "backgroundActivity", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

#if os(macOS)
    class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
        func applicationDidFinishLaunching(_ notification: Notification) {
            // Register as a service provider
            NSApp.servicesProvider = self
            
            UNUserNotificationCenter.current().delegate = self
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error = error {
                    print("Error requesting notification authorization: \(error)")
                }
            }
        }
        
        func applicationDidBecomeActive(_ notification: Notification) {
            // Check for shared files from Share Extension
            AlbumManager.shared.checkAppGroupInbox()
        }

        // MARK: - Services Support
        
        @objc func importPhotosFromService(_ pboard: NSPasteboard, userData: String, error: NSErrorPointer) {
            guard AlbumManager.shared.isUnlocked else {
                let alert = NSAlert()
                alert.messageText = "Album Locked"
                alert.informativeText = "Please unlock Encrypted Album before importing items."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
                
                // Set error pointer if possible, though simple alert is better UX here
                return
            }
            
            // Handle file URLs (e.g. from Finder)
            if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                Task {
                    await importURLs(urls)
                }
                return
            }
            
            // Handle raw images (e.g. from some apps that copy image data directly)
            if let images = pboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
                let imageDatas = images.compactMap { $0.tiffRepresentation }
                Task {
                    await importImages(imageDatas)
                }
                return
            }
        }
        
        @MainActor
        private func importURLs(_ urls: [URL]) async {
            let manager = AlbumManager.shared
            
            // Show import progress
            manager.directImportProgress.reset(totalItems: urls.count)
            
            for url in urls {
                // Determine media type
                let fileExtension = url.pathExtension.lowercased()
                let mediaType: MediaType
                if ["mov", "mp4", "m4v"].contains(fileExtension) {
                    mediaType = .video
                } else {
                    mediaType = .photo
                }
                
                do {
                    try await manager.hidePhoto(
                        mediaSource: .fileURL(url),
                        filename: url.lastPathComponent,
                        mediaType: mediaType
                    )
                    manager.directImportProgress.itemsProcessed += 1
                } catch {
                    print("Failed to import \(url.lastPathComponent): \(error)")
                }
            }
            
            manager.directImportProgress.finish()
            
            // Notify user
            let content = UNMutableNotificationContent()
            content.title = "Import Complete"
            content.body = "Successfully imported \(urls.count) items from Service."
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
        
        @MainActor
        private func importImages(_ imageDatas: [Data]) async {
            let manager = AlbumManager.shared
            manager.directImportProgress.reset(totalItems: imageDatas.count)
            
            for (index, tiffData) in imageDatas.enumerated() {
                guard let bitmap = NSBitmapImageRep(data: tiffData),
                      let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                    continue
                }
                
                let filename = "Imported Image \(Date().timeIntervalSince1970) \(index).jpg"
                
                do {
                    try await manager.hidePhoto(
                        mediaSource: .data(jpegData),
                        filename: filename,
                        mediaType: .photo
                    )
                    manager.directImportProgress.itemsProcessed += 1
                } catch {
                    print("Failed to import image: \(error)")
                }
            }
            
            manager.directImportProgress.finish()
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .sound])
        }

        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
            return true
        }

        func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
            if !flag {
                // If no windows are visible, show the main window
                for window in sender.windows {
                    window.makeKeyAndOrderFront(self)
                }
            }
            return true
        }
    }
#endif

// InactiveAppOverlay moved to InactiveAppOverlay.swift
