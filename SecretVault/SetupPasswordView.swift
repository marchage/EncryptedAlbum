import SwiftUI
import LocalAuthentication

struct SetupPasswordView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @State private var useAutoPassword = true
    @State private var generatedPasswords: [String] = []
    @State private var selectedPasswordIndex = 0
    @State private var manualPassword = ""
    @State private var confirmPassword = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var biometricsAvailable = false
    @State private var biometricType: LABiometryType = .none
    
    private var passwordStrength: PasswordStrength {
        evaluatePasswordStrength(useAutoPassword ? generatedPasswords[selectedPasswordIndex] : manualPassword)
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
            
            Text(biometricsAvailable ? "Your vault will be protected by \(biometricType == .faceID ? "Face ID" : "Touch ID")" : "Create a secure password for your vault")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            if biometricsAvailable {
                // Auto-generated password mode
                VStack(spacing: 16) {
                    Toggle(isOn: $useAutoPassword) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Use Auto-Generated Password")
                                .font(.headline)
                            Text("Secure password stored in Keychain, unlocked with biometrics")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .frame(width: 400)
                    
                    if useAutoPassword {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Choose a password:")
                                .font(.headline)
                            
                            ForEach(0..<3, id: \.self) { index in
                                Button {
                                    selectedPasswordIndex = index
                                } label: {
                                    HStack {
                                        Text(generatedPasswords[index])
                                            .font(.system(.body, design: .monospaced))
                                            .fontWeight(.medium)
                                        Spacer()
                                        if selectedPasswordIndex == index {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .frame(width: 400)
                                    .background(selectedPasswordIndex == index ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedPasswordIndex == index ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                                Text("Password is stored securely in Keychain. You'll never need to type it.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 400, alignment: .leading)
                        }
                    } else {
                        // Manual password entry
                        manualPasswordView
                    }
                }
            } else {
                // No biometrics - manual password only
                Text("Biometrics not available - manual password required")
                    .font(.caption)
                    .foregroundStyle(.orange)
                manualPasswordView
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
            .disabled(useAutoPassword ? false : manualPassword.isEmpty)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            checkBiometrics()
            generatePasswords()
        }
    }
    
    private var manualPasswordView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Create Master Password")
                    .font(.headline)
                SecureField("Enter password", text: $manualPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                
                // Password strength indicator
                if !manualPassword.isEmpty {
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
                        RequirementRow(met: manualPassword.count >= 8, text: "At least 8 characters")
                        RequirementRow(met: manualPassword.range(of: "[A-Z]", options: .regularExpression) != nil, text: "Uppercase letter")
                        RequirementRow(met: manualPassword.range(of: "[0-9]", options: .regularExpression) != nil, text: "Number")
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
        }
    }
    
    private func checkBiometrics() {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricsAvailable = true
            biometricType = context.biometryType
        }
    }
    
    private func generatePasswords() {
        generatedPasswords = [
            generateStrongPassword(),
            generateStrongPassword(),
            generateStrongPassword()
        ]
    }
    
    private func generateStrongPassword() -> String {
        let uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let lowercase = "abcdefghijklmnopqrstuvwxyz"
        let numbers = "0123456789"
        let symbols = "!@#$%^&*-_=+"
        
        var password = ""
        
        // Ensure at least one of each type
        password += String(uppercase.randomElement()!)
        password += String(lowercase.randomElement()!)
        password += String(numbers.randomElement()!)
        password += String(symbols.randomElement()!)
        
        // Fill the rest (total 16 chars)
        let allChars = uppercase + lowercase + numbers + symbols
        for _ in 0..<12 {
            password += String(allChars.randomElement()!)
        }
        
        // Shuffle to avoid predictable pattern
        return String(password.shuffled())
    }
    
    private func setupPassword() {
        let finalPassword: String
        
        if useAutoPassword {
            // Use generated password
            finalPassword = generatedPasswords[selectedPasswordIndex]
        } else {
            // Use manual password with validation
            guard manualPassword == confirmPassword else {
                errorMessage = "Passwords do not match"
                showError = true
                return
            }
            
            guard manualPassword.count >= 8 else {
                errorMessage = "Password must be at least 8 characters"
                showError = true
                return
            }
            
            // Enforce minimum requirements
            let hasUppercase = manualPassword.range(of: "[A-Z]", options: .regularExpression) != nil
            let hasNumber = manualPassword.range(of: "[0-9]", options: .regularExpression) != nil
            
            guard hasUppercase && hasNumber else {
                errorMessage = "Password must include uppercase letter and number"
                showError = true
                return
            }
            
            finalPassword = manualPassword
        }
        
        vaultManager.setupPassword(finalPassword)
        
        // Store in Keychain for biometric unlock if biometrics available
        if biometricsAvailable {
            vaultManager.saveBiometricPassword(finalPassword)
        }
        
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
