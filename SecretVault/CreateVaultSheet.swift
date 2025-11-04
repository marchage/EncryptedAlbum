import SwiftUI

struct CreateVaultSheet: View {
    @EnvironmentObject var vaultManager: VaultManager
    @Environment(\.dismiss) var dismiss
    
    @State private var vaultName = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var selectedColor = "blue"
    @State private var showError = false
    @State private var errorMessage = ""
    
    let colors = ["blue", "purple", "pink", "red", "green"]
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Create New Vault")
                .font(.title2)
                .fontWeight(.bold)
            
            // Preview
            ZStack {
                Circle()
                    .fill(getColor(selectedColor).gradient)
                    .frame(width: 80, height: 80)
                
                Image(systemName: "lock.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Vault Name")
                    .font(.headline)
                TextField("Enter vault name", text: $vaultName)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.headline)
                HStack {
                    ForEach(colors, id: \.self) { color in
                        Button {
                            selectedColor = color
                        } label: {
                            Circle()
                                .fill(getColor(color))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 3)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(.headline)
                SecureField("Enter password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm Password")
                    .font(.headline)
                SecureField("Re-enter password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
            }
            
            if showError {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Create Vault") {
                    createVault()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(vaultName.isEmpty || password.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
    
    private func createVault() {
        guard !vaultName.isEmpty else {
            errorMessage = "Please enter a vault name"
            showError = true
            return
        }
        
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            showError = true
            return
        }
        
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters"
            showError = true
            return
        }
        
        if vaultManager.createVault(name: vaultName, password: password, color: selectedColor) {
            dismiss()
        }
    }
    
    private func getColor(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "red": return .red
        case "green": return .green
        default: return .blue
        }
    }
}
