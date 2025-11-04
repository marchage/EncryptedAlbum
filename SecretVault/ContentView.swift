import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vaultManager: VaultManager
    
    var body: some View {
        ZStack {
            if vaultManager.hasPassword() {
                if vaultManager.isUnlocked {
                    MainVaultView()
                } else {
                    UnlockView()
                }
            } else {
                SetupPasswordView()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
