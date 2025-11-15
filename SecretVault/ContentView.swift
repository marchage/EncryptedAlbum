import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @State private var viewRefreshTrigger = false
    
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
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 600)
        #endif
        .onReceive(vaultManager.objectWillChange) { _ in
            // Force view refresh when vault manager changes
            viewRefreshTrigger.toggle()
        }
    }
}
