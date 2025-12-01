import LocalAuthentication
import SwiftUI

struct SetupPasswordView: View {
    @EnvironmentObject var albumManager: AlbumManager
    @ObservedObject private var appIconService = AppIconService.shared
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
                    // Prefer the appIconService runtime image if available (reflects selected alternate icon)
                    if let runtime = appIconService.runtimeMarketingImage {
                        Image(nsImage: runtime)
                            .resizable()
                            .renderingMode(.original)
                            .interpolation(.high)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: 180, maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 26))
                            .compositingGroup()
                            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                    } else if let appIcon = NSImage(named: "AppIcon") {
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
                        Image(systemName: "lock.fill")
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
                    let iconCap = min(CGFloat(150), UIScreen.main.bounds.width * 0.32)
                    let selectedIcon = appIconService.selectedIconName.isEmpty ? nil : appIconService.selectedIconName
                    let runtimeIcon = appIconService.runtimeMarketingImage
                    let generatedIcon = AppIconService.generateMarketingImage(from: selectedIcon)
                    if let marketingIcon = Image.chooseBestMarketingImage(
                        runtime: runtimeIcon, generated: generatedIcon, visualCap: iconCap)
                    {
                        Image(platformImage: marketingIcon)
                            .resizable()
                            .renderingMode(.original)
                            .interpolation(.high)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(width: iconCap, height: iconCap)
                            .clipShape(RoundedRectangle(cornerRadius: 26))
                            .compositingGroup()
                            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                    } else if let appIcon = UIImage(named: "AppIcon") {
                        Image(uiImage: appIcon)
                            .resizable()
                            .renderingMode(.original)
                            .interpolation(.high)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(width: iconCap, height: iconCap)
                            .clipShape(RoundedRectangle(cornerRadius: 26))
                            .compositingGroup()
                            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                    } else {
                        // Fallback to lock circle; attach an onAppear handler for diagnostics
                        Image(systemName: "lock.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .onAppear {
                                AppLog.debugPublic(
                                    "SetupPasswordView: no UIImage named 'AppIcon' found in asset catalog — using fallback symbol."
                                )
                            }
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
                        Image(systemName: "lock.fill")
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

                Text("Welcome to Encrypted Album")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                // .padding(.horizontal)

                Text(
                    biometricsAvailable
                        ? "Your album will be protected by \(biometricType == .faceID ? "Face ID" : "Touch ID")"
                        : "Create a secure password for your album"
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

                        Text(
                            "Too many failed attempts. You need to enter your system password to re-enable biometrics."
                        )
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
                                        Text(
                                            generatedPasswords.indices.contains(selectedPasswordIndex)
                                                ? generatedPasswords[selectedPasswordIndex] : ""
                                        )
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
                                    VStack(spacing: 8) {
                                        // Candidate passwords — horizontally scrollable so iOS users
                                        // can pick which generated password they prefer.
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 12) {
                                                ForEach(Array(generatedPasswords.enumerated()), id: \.offset) {
                                                    idx, pw in
                                                    Button(action: { selectedPasswordIndex = idx }) {
                                                        VStack(alignment: .leading, spacing: 6) {
                                                            // Show a masked preview in the candidate list so we don't
                                                            // accidentally expose the full password. The Reveal button
                                                            // shows the full secret intentionally.
                                                            Text(maskedPreview(for: pw))
                                                                .font(.system(.body, design: .monospaced))
                                                                .lineLimit(1)
                                                                .truncationMode(.middle)
                                                                .frame(maxWidth: 320, alignment: .leading)
                                                            Text(passwordStrength.text)
                                                                .font(.caption)
                                                                .foregroundStyle(.secondary)
                                                        }
                                                        .padding(10)
                                                        .background(
                                                            RoundedRectangle(cornerRadius: 10).fill(
                                                                selectedPasswordIndex == idx
                                                                    ? Color.blue.opacity(0.12)
                                                                    : Color.gray.opacity(0.06))
                                                        )
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 10).stroke(
                                                                selectedPasswordIndex == idx ? Color.blue : Color.clear,
                                                                lineWidth: 2))
                                                    }
                                                    .buttonStyle(.plain)
                                                    .frame(minWidth: 250)
                                                }
                                            }
                                        }

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
                    Text("Create Album")
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
        .scrollContentBackground(.hidden)
        .background(Color.clear)
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
                    .frame(maxWidth: 300)
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
                    .frame(maxWidth: 300)
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
        // Test hook: when running UI tests we expose a tiny, invisible button that
        // will auto-fill the manual password fields with the value provided in
        // the launch environment (UI_TEST_PASSWORD). This keeps the flow intact
        // but prevents flakiness related to synthesizing keyboard events.
        .overlay(
            Group {
                if ProcessInfo.processInfo.arguments.contains("--ui-tests") {
                    Button(action: {
                        let value = ProcessInfo.processInfo.environment["UI_TEST_PASSWORD"] ?? "TestPass123!"
                        manualPassword = value
                        confirmPassword = value
                    }) {
                        // Keep the view tiny and nearly invisible but hittable for UI tests
                        Text("")
                    }
                    .accessibilityIdentifier("test.fillSetupPassword")
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                }
            }
        )
    }

    /// Return a privacy-preserving preview of a generated password.
    /// We show only the last 4 characters (if available) and mask the rest using bullet characters.
    /// This gives users a recognizable short hint without exposing the full secret.
    private func maskedPreview(for pw: String) -> String {
        let visibleCount = min(4, pw.count)
        let maskCount = max(0, pw.count - visibleCount)
        let masked = String(repeating: "•", count: maskCount)
        let start = pw.index(pw.endIndex, offsetBy: -visibleCount)
        let suffix = String(pw[start...])
        return masked + suffix
    }

    private func checkBiometrics() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricsAvailable = true
            biometricLockout = false
            biometricType = context.biometryType
            AppLog.debugPublic("Biometrics available: \(biometricType == .faceID ? "Face ID" : "Touch ID")")
        } else {
            biometricsAvailable = false
            if let error = error, error.code == LAError.biometryLockout.rawValue {
                biometricLockout = true
                AppLog.debugPublic("Biometrics locked out (Code: -8)")
            } else {
                biometricLockout = false
            }

            if let error = error {
                AppLog.debugPrivate(
                    "Biometrics NOT available. Error: \(error.localizedDescription) (Code: \(error.code))")
            } else {
                AppLog.debugPublic("Biometrics NOT available. Unknown error.")
            }
        }
    }

    private func generatePasswords() {
        // Generate a few candidates so users can pick one they prefer.
        var list: [String] = []
        for _ in 0..<3 {
            list.append(generateStrongPassword())
        }
        generatedPasswords = list
        // Reset selection if we somehow re-generate while the view is showing
        selectedPasswordIndex = 0
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

        // Fill the rest (total 24 chars for maximum security).
        // We deliberately generate 24 characters because the UI reveals the last 4
        // characters in a masked preview — generating 24 ensures at least 20
        // characters remain secret even after exposing a short hint.
        let allChars = uppercase + lowercase + numbers + symbols
        for _ in 0..<20 {
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
                let password =
                    generatedPasswords.indices.contains(selectedPasswordIndex)
                    ? generatedPasswords[selectedPasswordIndex] : (generatedPasswords.first ?? "")
                Task {
                    await completeSetup(with: password)
                }
            #else
                // On macOS, verify biometric authentication first
                authenticateAndSetup()
            #endif
        } else {
            // Manual password validation
            let normalizedManual = PasswordService.normalizePassword(manualPassword)
            let normalizedConfirm = PasswordService.normalizePassword(confirmPassword)

            guard normalizedManual == normalizedConfirm else {
                errorMessage = "Passwords do not match"
                showError = true
                return
            }

            guard normalizedManual.count >= 8 else {
                errorMessage = "Password must be at least 8 characters"
                showError = true
                return
            }

            // Enforce minimum requirements
            // Use Unicode-aware checks so non-ASCII uppercase letters (e.g. Turkish İ) are recognized
            let hasUppercase = normalizedManual.contains { $0.isUppercase }
            let hasNumber = normalizedManual.contains { $0.isNumber }

            guard hasUppercase && hasNumber else {
                errorMessage = "Password must include uppercase letter and number"
                showError = true
                return
            }

            Task {
                // Store/use the normalized value for consistent behavior
                await completeSetup(with: normalizedManual)
            }
        }
    }

    private func authenticateAndSetup() {
        let context = LAContext()
        let reason = "Authenticate to set up your Encrypted Album"

        // Delay slightly so the biometric sheet does not pop immediately, matching unlock behavior.
        Thread.sleep(forTimeInterval: 1.0)

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                if success {
                    let password =
                        generatedPasswords.indices.contains(selectedPasswordIndex)
                        ? generatedPasswords[selectedPasswordIndex] : (generatedPasswords.first ?? "")
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
            // Respect the user's choice for storing in biometric-protected keychain.
            try await albumManager.setupPassword(password, storeBiometric: useAutoPassword)
            // Immediately unlock so session keys are derived and the user can start working
            try await albumManager.unlock(password: password)
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
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Enter password to re-enable biometrics") {
            success, error in
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
