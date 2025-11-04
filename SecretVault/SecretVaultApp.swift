import SwiftUI

@main
struct SecretVaultApp: App {
    @StateObject private var vaultManager = VaultManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vaultManager)
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
