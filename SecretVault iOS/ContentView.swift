//
//  ContentView.swift
//  SecretVault iOS
//
//  Created by Marc Hage on 15/11/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var vaultManager = VaultManager.shared
    
    var body: some View {
        if vaultManager.isUnlocked {
            MainVaultView()
        } else {
            UnlockView()
        }
    }
}

#Preview {
    ContentView()
}
