import SwiftUI
import UserNotifications

@main
struct SecretVaultApp: App {
    @StateObject private var vaultManager = VaultManager.shared
    @State private var hasNotifiedBackgroundActivity = false
    #if os(macOS)
        @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
            WindowGroup {
                ContentView()
                    .environmentObject(vaultManager)
                    .frame(minWidth: 900, minHeight: 600)
                    .overlay {
                        InactiveAppOverlay()
                    }
                    .onChange(of: vaultManager.isBusy) { isBusy in
                        if !isBusy {
                            hasNotifiedBackgroundActivity = false
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                        if vaultManager.isBusy {
                            if !hasNotifiedBackgroundActivity {
                                sendBackgroundActivityNotification()
                                hasNotifiedBackgroundActivity = true
                            }
                        } else {
                            vaultManager.lock()
                        }
                    }
            }
            Settings {
                PreferencesView()
                    .environmentObject(vaultManager)
            }
            .commands {
                // Remove "New Window" command to prevent multiple windows
                CommandGroup(replacing: .newItem) {}
            }
        #endif
        #if os(iOS)
        // This target should use SecretVault_iOSApp.swift as entry point
        // But if this file is included in iOS target by mistake, we provide a fallback
        WindowGroup {
            ContentView()
                .environmentObject(vaultManager)
        }
        #endif
    }

    private func sendBackgroundActivityNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Vault Remains Unlocked"
        content.body = "SecretVault is performing a task in the background and will remain unlocked until it completes."
        content.sound = .default

        let request = UNNotificationRequest(identifier: "backgroundActivity", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

#if os(macOS)
    class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
        func applicationDidFinishLaunching(_ notification: Notification) {
            UNUserNotificationCenter.current().delegate = self
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error = error {
                    print("Error requesting notification authorization: \(error)")
                }
            }
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
