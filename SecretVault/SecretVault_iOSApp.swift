import SwiftUI

@main
struct SecretVaultApp_iOS: App {
    @StateObject private var vaultManager = VaultManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vaultManager)
        }
    }
}
