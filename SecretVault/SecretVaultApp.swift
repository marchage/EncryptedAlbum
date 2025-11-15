import SwiftUI

@main
struct SecretVaultApp: App {
    @StateObject private var vaultManager = VaultManager.shared
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    
    var body: some Scene {
        #if os(iOS)
        WindowGroup {
            ContentView()
                .environmentObject(vaultManager)
        }
        #else
        WindowGroup {
            ContentView()
                .environmentObject(vaultManager)
                .frame(minWidth: 900, minHeight: 600)
        }
        Settings {
            PreferencesView()
                .environmentObject(vaultManager)
        }
        .commands {
            // Remove "New Window" command to prevent multiple windows
            CommandGroup(replacing: .newItem) { }
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
