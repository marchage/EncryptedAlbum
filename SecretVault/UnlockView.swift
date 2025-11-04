import SwiftUI

struct UnlockView: View {
    let vault: Vault
    @EnvironmentObject var vaultManager: VaultManager
    @State private var password = ""
    @State private var showError = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(vault.colorValue.gradient)
                    .frame(width: 100, height: 100)
                
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }
            
            Text(vault.name)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("This vault is locked")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 12) {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onSubmit {
                        unlock()
                    }
                
                if showError {
                    Text("Incorrect password")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
                
                Button {
                    unlock()
                } label: {
                    Text("Unlock Vault")
                        .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(password.isEmpty)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func unlock() {
        if vaultManager.unlockVault(vault, password: password) {
            showError = false
        } else {
            showError = true
            password = ""
        }
    }
}
