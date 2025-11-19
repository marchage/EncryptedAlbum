import SwiftUI

@main
struct SecretVaultApp_iOS: App {
    @StateObject private var vaultManager = VaultManager.shared

    init() {
        #if DEBUG
        if CommandLine.arguments.contains("--reset-state") {
            print("⚠️ TEST MODE: Wiping Vault Data")
            let fileManager = FileManager.default
            if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                let vaultURL = documents.appendingPathComponent("SecretVault")
                try? fileManager.removeItem(at: vaultURL)
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vaultManager)
        }
    }
}
