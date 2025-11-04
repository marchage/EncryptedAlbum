import SwiftUI

struct SetupPasswordView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showError = false
    @State private var errorMessage = ""
    
    private var passwordStrength: PasswordStrength {
        evaluatePasswordStrength(password)
    }
    
    private enum PasswordStrength {
        case weak, medium, strong
        
        var color: Color {
            switch self {
            case .weak: return .red
            case .medium: return .orange
            case .strong: return .green
            }
        }
        
        var text: String {
            switch self {
            case .weak: return "Weak"
            case .medium: return "Medium"
            case .strong: return "Strong"
            }
        }
    }
    
    private func evaluatePasswordStrength(_ password: String) -> PasswordStrength {
        let length = password.count
        let hasUppercase = password.range(of: "[A-Z]", options: .regularExpression) != nil
        let hasLowercase = password.range(of: "[a-z]", options: .regularExpression) != nil
        let hasNumbers = password.range(of: "[0-9]", options: .regularExpression) != nil
        let hasSpecial = password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil
        
        var score = 0
        if length >= 8 { score += 1 }
        if length >= 12 { score += 1 }
        if hasUppercase { score += 1 }
        if hasLowercase { score += 1 }
        if hasNumbers { score += 1 }
        if hasSpecial { score += 1 }
        
        if score >= 5 { return .strong }
        if score >= 3 { return .medium }
        return .weak
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // App Icon
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 26))
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            } else {
                // Fallback to lock shield
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            Text("Welcome to Secret Vault")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Hide photos from your Photos Library")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create Master Password")
                        .font(.headline)
                    SecureField("Enter password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                    
                    // Password strength indicator
                    if !password.isEmpty {
                        HStack(spacing: 8) {
                            Text("Strength:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(passwordStrength.text)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(passwordStrength.color)
                            
                            Spacer()
                        }
                        .frame(width: 300)
                        
                        // Requirements
                        VStack(alignment: .leading, spacing: 4) {
                            RequirementRow(met: password.count >= 8, text: "At least 8 characters")
                            RequirementRow(met: password.range(of: "[A-Z]", options: .regularExpression) != nil, text: "Uppercase letter")
                            RequirementRow(met: password.range(of: "[0-9]", options: .regularExpression) != nil, text: "Number")
                        }
                        .font(.caption)
                        .frame(width: 300)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Confirm Password")
                        .font(.headline)
                    SecureField("Re-enter password", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                        .onSubmit {
                            setupPassword()
                        }
                }
                
                if showError {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
                
                Button {
                    setupPassword()
                } label: {
                    Text("Create Vault")
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
    
    private func setupPassword() {
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            showError = true
            return
        }
        
        guard password.count >= 8 else {
            errorMessage = "Password must be at least 8 characters"
            showError = true
            return
        }
        
        // Enforce minimum requirements
        let hasUppercase = password.range(of: "[A-Z]", options: .regularExpression) != nil
        let hasNumber = password.range(of: "[0-9]", options: .regularExpression) != nil
        
        guard hasUppercase && hasNumber else {
            errorMessage = "Password must include uppercase letter and number"
            showError = true
            return
        }
        
        // Warn about weak passwords but allow them
        if passwordStrength == .weak {
            errorMessage = "⚠️ Weak password. Your vault security depends on password strength."
            showError = true
            // Still allow it, but user sees the warning
        }
        
        vaultManager.setupPassword(password)
        vaultManager.isUnlocked = true
    }
}

struct RequirementRow: View {
    let met: Bool
    let text: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(met ? .green : .secondary)
                .font(.caption)
            Text(text)
                .foregroundStyle(met ? .primary : .secondary)
        }
    }
}
