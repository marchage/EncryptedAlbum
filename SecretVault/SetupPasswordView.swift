import LocalAuthentication
import SwiftUI

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
    @State private var revealPassword = false
    @State private var flashScreen = false
    @State private var biometricLockout = false

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
        ScrollView {
            VStack(spacing: 24) {
                // Top spacing
                Color.clear.frame(height: 20)

                // App Icon
                #if os(macOS)
                    if let appIcon = NSImage(named: "AppIcon") {
                        Image(nsImage: appIcon)
                            .resizable()
                            .renderingMode(.original)
                            .interpolation(.high)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: 180, maxHeight: 180)
                            //.padding(.top, 8)
                            .clipShape(RoundedRectangle(cornerRadius: 26))
                            .compositingGroup()
                            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                    } else {
                        // Fallback to lock circle
                        Image(systemName: "lock.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                #elseif os(iOS)
                    if let appIcon = UIImage(named: "AppIcon") {
                        Image(uiImage: appIcon)
                            .resizable()
                            .renderingMode(.original)
                            .interpolation(.high)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: 120, maxHeight: 120)
                            //.padding(.top, 28)
                            .clipShape(RoundedRectangle(cornerRadius: 26))
                            .compositingGroup()
                            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                    } else {
                        // Fallback to lock circle
                        Image(systemName: "lock.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                #else
                    // Default fallback for other platforms: keep existing behavior
                    if let appIcon = UIImage(named: "AppIcon") {
                        Image(uiImage: appIcon)
                            .resizable()
                            .renderingMode(.original)
                            .interpolation(.high)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: 140, maxHeight: 140)
                            //.padding(.top, 24)
                            .clipShape(RoundedRectangle(cornerRadius: 26))
                            .compositingGroup()
                            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                    } else {
                        Image(systemName: "lock.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                #endif

                Text("Welcome to Secret Vault")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                // .padding(.horizontal)

                Text(
                    biometricsAvailable
                        ? "Your vault will be protected by \(biometricType == .faceID ? "Face ID" : "Touch ID")"
                        : "Create a secure password for your vault"
                )
                .font(.title3)
                .foregroundStyle(.secondary)

                if biometricLockout {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text("Biometrics Locked Out")
                                .font(.headline)
                                .foregroundStyle(.red)
                        }
                        
                        Text("Too many failed attempts. You need to enter your system password to re-enable biometrics.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Button("Reset Biometrics") {
                            resetBiometricLockout()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .frame(width: 400)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(12)
                }

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
                        .padding(.horizontal)
                        .frame(width: 400)
                        .accessibilityIdentifier("biometricToggle")

                        if useAutoPassword {
                            VStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "key.fill")
                                        .foregroundStyle(.green)
                                        .font(.title2)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Secure password generated")
                                            .font(.headline)
                                        Text(
                                            "Stored in Keychain • Unlocked with \(biometricType == .faceID ? "Face ID" : "Touch ID")"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding()
                                .frame(width: 400)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(12)

                                if revealPassword {
                                    VStack(spacing: 8) {
                                        Text(generatedPasswords[0])
                                            .font(.system(.title3, design: .monospaced))
                                            .fontWeight(.semibold)
                                            .padding()
                                            .frame(width: 400)
                                            .background(Color.red.opacity(0.1))
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.red, lineWidth: 2)
                                            )

                                        Button {
                                            withAnimation {
                                                revealPassword = false
                                            }
                                        } label: {
                                            HStack {
                                                Image(systemName: "eye.slash.fill")
                                                Text("Hide Password")
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                } else {
                                    HStack {
                                        Image(systemName: "eye.slash.fill")
                                            .foregroundStyle(.secondary)
                                        Text("Password hidden for security.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Spacer()

                                        Button {
                                            revealPasswordWithFlash()
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "eye.fill")
                                                Text("Reveal")
                                            }
                                            .font(.caption)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.orange)
                                    }
                                    .padding(.horizontal)
                                    .frame(width: 400, alignment: .leading)
                                }
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

                // Bottom spacing
                Color.clear.frame(height: 20)
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            // Flash overlay
            Rectangle()
                .fill(.white)
                .opacity(flashScreen ? 1.0 : 0.0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        )
        .onAppear {
            checkBiometrics()
            generatePasswords()
        }
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 36)
        }
    }

    private var manualPasswordView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Create Master Password")
                    .font(.headline)
                    .padding(.horizontal)
                SecureField("Enter password", text: $manualPassword)
                    .textFieldStyle(.roundedBorder)
                    #if os(macOS)
                        .textContentType(.password)
                    #else
                        .textContentType(.newPassword)
                    #endif
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                    .padding(.horizontal)

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
                    .padding(.horizontal)

                    // Requirements
                    VStack(alignment: .leading, spacing: 4) {
                        RequirementRow(met: manualPassword.count >= 8, text: "At least 8 characters")
                        RequirementRow(
                            met: manualPassword.range(of: "[A-Z]", options: .regularExpression) != nil,
                            text: "Uppercase letter")
                        RequirementRow(
                            met: manualPassword.range(of: "[0-9]", options: .regularExpression) != nil, text: "Number")
                    }
                    .font(.caption)
                    .padding(.horizontal)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm Password")
                    .font(.headline)
                    .padding(.horizontal)
                SecureField("Re-enter password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                    #if os(macOS)
                        .textContentType(.password)
                    #else
                        .textContentType(.newPassword)
                    #endif
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                    .padding(.horizontal)
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
            biometricLockout = false
            biometricType = context.biometryType
            #if DEBUG
            print("✅ Biometrics available: \(biometricType == .faceID ? "Face ID" : "Touch ID")")
            #endif
        } else {
            biometricsAvailable = false
            if let error = error, error.code == LAError.biometryLockout.rawValue {
                biometricLockout = true
                #if DEBUG
                print("❌ Biometrics locked out (Code: -8)")
                #endif
            } else {
                biometricLockout = false
            }
            
            #if DEBUG
            if let error = error {
                print("❌ Biometrics NOT available. Error: \(error.localizedDescription) (Code: \(error.code))")
            } else {
                print("❌ Biometrics NOT available. Unknown error.")
            }
            #endif
        }
    }

    private func generatePasswords() {
        // Only generate one password - no need to show it
        generatedPasswords = [generateStrongPassword()]
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

        // Fill the rest (total 20 chars for maximum security)
        let allChars = uppercase + lowercase + numbers + symbols
        for _ in 0..<16 {
            password += String(allChars.randomElement()!)
        }

        // Shuffle to avoid predictable pattern
        return String(password.shuffled())
    }

    private func setupPassword() {
        if useAutoPassword && biometricsAvailable {
            #if os(iOS)
            // On iOS, the Keychain will prompt for Face ID when storing with .biometryAny
            // No need to authenticate first
            let password = generatedPasswords[0]
            Task {
                await completeSetup(with: password)
            }
            #else
            // On macOS, verify biometric authentication first
            authenticateAndSetup()
            #endif
        } else {
            // Manual password validation
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

            Task {
                await completeSetup(with: manualPassword)
            }
        }
    }

    private func authenticateAndSetup() {
        let context = LAContext()
        let reason = "Authenticate to set up your Secret Vault"

        // Delay slightly so the biometric sheet does not pop immediately, matching unlock behavior.
        Thread.sleep(forTimeInterval: 1.0)

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                if success {
                    let password = generatedPasswords[0]
                    Task {
                        await completeSetup(with: password)
                    }
                } else {
                    // Authentication failed
                    if let error = error as? LAError {
                        switch error.code {
                        case .userCancel:
                            errorMessage = "Setup cancelled"
                        case .userFallback:
                            errorMessage = "Biometric authentication required"
                        default:
                            errorMessage = "Biometric authentication failed"
                        }
                        showError = true
                    }
                }
            }
        }
    }

    private func completeSetup(with password: String) async {
        do {
            try await vaultManager.setupPassword(password)
            // Immediately unlock so session keys are derived and the user can start working
            try await vaultManager.unlock(password: password)
        } catch {
            errorMessage = "Failed to set password: \(error.localizedDescription)"
            showError = true
        }
    }

    private func revealPasswordWithFlash() {
        // Flash the screen white
        withAnimation(.easeInOut(duration: 0.15)) {
            flashScreen = true
        }

        // Hold the flash briefly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.15)) {
                flashScreen = false
            }

            // Reveal password after flash
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation {
                    revealPassword = true
                }
            }
        }
    }

    private func resetBiometricLockout() {
        let context = LAContext()
        // .deviceOwnerAuthentication allows passcode/password fallback which clears the lockout
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Enter password to re-enable biometrics") { success, error in
            DispatchQueue.main.async {
                if success {
                    self.biometricLockout = false
                    self.checkBiometrics()
                } else {
                    if let error = error {
                        self.errorMessage = "Failed to reset: \(error.localizedDescription)"
                        self.showError = true
                    }
                }
            }
        }
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
