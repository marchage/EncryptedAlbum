import SwiftUI
import LocalAuthentication

struct UnlockView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @State private var password = ""
    @State private var showError = false
    @State private var biometricType: LABiometryType = .none
    
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
                // Fallback to gradient circle with lock
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
                
                HStack(spacing: 12) {
                    if biometricType != .none {
                        Button {
                            authenticateWithBiometrics()
                        } label: {
                            HStack {
                                Image(systemName: biometricType == .faceID ? "faceid" : "touchid")
                                Text(biometricType == .faceID ? "Use Face ID" : "Use Touch ID")
                            }
                            .frame(width: 145)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    
                    Button {
                        unlock()
                    } label: {
                        Text("Unlock")
                            .frame(width: biometricType != .none ? 145 : 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(password.isEmpty)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            checkBiometricAvailability()
            // Auto-trigger biometric authentication if available
            if biometricType != .none {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    authenticateWithBiometrics()
                }
            }
        }
    }
    
    private func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricType = context.biometryType
        }
    }
    
    private func authenticateWithBiometrics() {
        let context = LAContext()
        let reason = "Unlock your Secret Vault"
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                if success {
                    // User authenticated successfully - get stored password
                    if let storedPassword = vaultManager.getBiometricPassword() {
                        password = storedPassword
                        unlock()
                    }
                } else {
                    // Authentication failed
                    if let error = error as? LAError {
                        switch error.code {
                        case .userCancel, .userFallback:
                            // User cancelled or wants to use password
                            break
                        default:
                            showError = true
                        }
                    }
                }
            }
        }
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
