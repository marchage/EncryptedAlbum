import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @State private var selectedVault: Vault?
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            VaultSidebar(selectedVault: $selectedVault)
        } detail: {
            if let vault = selectedVault {
                if vaultManager.isVaultUnlocked(vault.id) {
                    VaultDetailView(vault: vault)
                } else {
                    UnlockView(vault: vault)
                }
            } else {
                WelcomeView()
            }
        }
        .sheet(isPresented: $vaultManager.showCreateVault) {
            CreateVaultSheet()
        }
    }
}

struct VaultSidebar: View {
    @EnvironmentObject var vaultManager: VaultManager
    @Binding var selectedVault: Vault?
    
    var body: some View {
        List(selection: $selectedVault) {
            Section("Vaults") {
                ForEach(vaultManager.vaults) { vault in
                    VaultRow(vault: vault)
                        .tag(vault)
                }
            }
        }
        .navigationTitle("Secret Vault")
        .toolbar {
            Button {
                vaultManager.showCreateVault = true
            } label: {
                Image(systemName: "plus")
            }
        }
    }
}

struct VaultRow: View {
    let vault: Vault
    @EnvironmentObject var vaultManager: VaultManager
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(vault.colorValue.gradient)
                    .frame(width: 40, height: 40)
                
                Image(systemName: vaultManager.isVaultUnlocked(vault.id) ? "lock.open.fill" : "lock.fill")
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading) {
                Text(vault.name)
                    .font(.headline)
                Text("\(vault.photoCount) photos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct WelcomeView: View {
    @EnvironmentObject var vaultManager: VaultManager
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Welcome to Secret Vault")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Create your first vault to securely store photos")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            Button {
                vaultManager.showCreateVault = true
            } label: {
                Label("Create New Vault", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
