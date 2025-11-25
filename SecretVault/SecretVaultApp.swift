import SwiftUI

@main
struct SecretVaultApp: App {
    @StateObject private var vaultManager = VaultManager.shared
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
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                        // Lock immediately when backgrounded, unless busy with import/export
                        if !vaultManager.isBusy {
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
}

#if os(macOS)
    class AppDelegate: NSObject, NSApplicationDelegate {
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
