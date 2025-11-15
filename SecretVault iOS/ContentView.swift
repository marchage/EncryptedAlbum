//
//  ContentView.swift
//  SecretVault iOS
//
//  Created by Marc Hage on 15/11/2025.
//

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
        .id(vaultManager.viewRefreshId)
    }
}

#Preview {
    ContentView()
}
