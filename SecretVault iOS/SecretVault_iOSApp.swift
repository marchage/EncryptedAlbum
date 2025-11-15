//
//  SecretVault_iOSApp.swift
//  SecretVault iOS
//
//  Created by Marc Hage on 15/11/2025.
//

import SwiftUI

@main
struct SecretVault_iOSApp: App {
    @StateObject private var vaultManager = VaultManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vaultManager)
        }
    }
}
