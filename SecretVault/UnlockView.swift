import SwiftUI

struct UnlockView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @State private var password = ""
    @State private var showError = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }
            
            Text("Secret Vault")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Enter your password to unlock")
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
                    Text("Unlock")
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
        if vaultManager.unlock(password: password) {
            showError = false
        } else {
            showError = true
            password = ""
        }
    }
}
